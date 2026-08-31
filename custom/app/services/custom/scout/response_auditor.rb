# frozen_string_literal: true

class Custom::Scout::ResponseAuditor
  # The confirmation call must run at a different temperature than the initial call (0.0). At
  # temperature 0.0 the model is near-deterministic, so a second call with the identical prompt is
  # not an independent draw — it reliably reproduces the same hallucination instead of catching it,
  # defeating the whole point of requiring two calls to agree (see handoff_confirmed? below).
  CONFIRMATION_TEMPERATURE = 0.7

  REPAIR_INSTRUCTION = <<~INSTRUCTION
    ATENÇÃO: Sua resposta anterior afirmou que uma ação foi concluída ou prometeu uma ação futura, mas a ação não foi executada com sucesso pelas ferramentas disponíveis.
    Por favor, reavalie: se a ferramenta adequada estiver disponível e couber executá-la agora, execute-a; caso contrário, responda ao cliente de forma transparente sem afirmar ou prometer ações que não foram realizadas.
  INSTRUCTION

  def initialize(scout:, conversation:)
    @scout = scout
    @conversation = conversation
    @account = conversation.account
  end

  def audit(chat:, response_text:, message_history:, recorded_tool_calls:)
    return { action: :proceed, reply: response_text } unless conversation_pending?

    action_outcome = evaluate_action(message_history)
    return action_outcome if action_outcome
    return { action: :proceed, reply: response_text } unless conversation_pending?

    consistency_result = check_claim_consistency(message_history, response_text, recorded_tool_calls)
    return { action: :proceed, reply: response_text } if consistency_safe_or_unclear?(consistency_result)

    perform_repair_and_reverify(chat, response_text, message_history, recorded_tool_calls)
  rescue StandardError => e
    handle_audit_error(e, response_text)
  end

  private

  def conversation_pending?
    return false if @conversation.blank?

    status = Conversation.uncached { Conversation.where(id: @conversation.id).pick(:status) }
    status == 'pending' || status == Conversation.statuses[:pending]
  end

  def evaluate_action(message_history)
    return nil unless conversation_pending?

    action_result = check_action_classification(message_history)
    return nil unless action_handoff?(action_result)

    reason = action_result['action_reason'] || action_result[:action_reason]
    return nil unless handoff_confirmed?(message_history, reason)

    execute_handoff(reason)
    { action: :handoff }
  end

  # A single classifier call is a stochastic draw and can hallucinate 'handoff' even with a
  # correctly-filtered prompt (observed in production on conversations with no real human-offer
  # content). Since handoff is irreversible and customer-facing, require a second independent
  # call — at CONFIRMATION_TEMPERATURE, not the initial call's 0.0 — to agree on both the action
  # and the exact reason before acting on it — this bounds the false-positive rate to roughly the
  # square of the single-call hallucination rate instead of trusting one draw outright.
  def handoff_confirmed?(message_history, reason)
    confirmation = check_action_classification(message_history, temperature: CONFIRMATION_TEMPERATURE)
    return false unless action_handoff?(confirmation)

    (confirmation['action_reason'] || confirmation[:action_reason]) == reason
  end

  def perform_repair_and_reverify(chat, original_reply, message_history, recorded_tool_calls)
    return { action: :proceed, reply: original_reply } unless conversation_pending?

    repaired_response = execute_repair(chat)
    return { action: :escalate, reason: 'Resposta inconsistente com as ações executadas.' } if repaired_response.blank?

    action_outcome = evaluate_action(message_history)
    return action_outcome if action_outcome

    reverify_consistency(repaired_response, message_history, recorded_tool_calls)
  end

  # By this point `execute_repair` has already run a fresh `chat.ask`, which can itself trigger
  # `handover_to_human` (the model reconsidering during repair and deciding to hand off instead of
  # answering). If the conversation is no longer pending here, that tool call is the only realistic
  # cause — it already sent its own customer-facing message and assigned a human. Returning
  # `:proceed` in that case would make `process_audited_reply` dispatch a second, redundant reply
  # right after a real handoff (observed in production: fixed handoff phrase followed immediately by
  # the model's own repaired text). `:handoff` matches the same "stop, nothing else to send" contract
  # already used everywhere else in this file for a non-pending conversation.
  def reverify_consistency(repaired_response, message_history, recorded_tool_calls)
    return { action: :handoff } unless conversation_pending?

    reverify_result = check_claim_consistency(message_history, repaired_response, recorded_tool_calls)
    if consistency_safe_or_unclear?(reverify_result)
      { action: :proceed, reply: repaired_response }
    else
      { action: :escalate, reason: 'Resposta inconsistente com as ações executadas.' }
    end
  end

  def handle_audit_error(error, fallback_reply)
    ChatwootExceptionTracker.new(error, account: @scout.account).capture_exception
    Rails.logger.warn(
      "[Scout][ResponseAuditor] Failed for conversation #{@conversation.id}: #{error.class.name}: #{error.message}"
    )
    { action: :proceed, reply: fallback_reply }
  end

  def check_action_classification(message_history, temperature: 0.0)
    Custom::Scout::ActionClassifierService.new(scout: @scout, conversation: @conversation).classify(
      message_history: message_history, temperature: temperature
    )
  end

  def action_handoff?(result)
    action = result['action'] || result[:action]
    action == 'handoff'
  end

  def execute_handoff(reason)
    Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation).perform(reason: reason)
  end

  def check_claim_consistency(message_history, response_text, recorded_tool_calls)
    Custom::Scout::ClaimConsistencyService.new(scout: @scout, conversation: @conversation).check(
      message_history: message_history,
      assistant_response: response_text,
      recorded_tool_calls: recorded_tool_calls
    )
  end

  def consistency_safe_or_unclear?(result)
    decision = result['decision'] || result[:decision]
    decision == 'safe' || decision.blank?
  end

  def execute_repair(chat)
    repair_msg = chat.ask(REPAIR_INSTRUCTION)
    parse_repaired_content(repair_msg&.content)
  end

  def parse_repaired_content(content)
    return nil if content.blank?
    return content['response'] || content[:response] if content.is_a?(Hash)

    sanitized = content.to_s.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
    json = JSON.parse(sanitized)
    json['response']
  rescue JSON::ParserError
    content.to_s.presence
  end
end
