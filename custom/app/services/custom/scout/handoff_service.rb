# frozen_string_literal: true

class Custom::Scout::HandoffService
  def initialize(scout:, conversation:)
    @scout = scout
    @conversation = conversation
  end

  def perform(assignee_id: nil, team_id: nil, reason: nil, message: nil)
    @action_reason = reason
    assign_team_and_user(assignee_id, team_id)
    handed_off = perform_handoff(message: message)
    create_transfer_note(reason) if handed_off
    generate_contact_memory if @scout.feature_memory?

    'Conversation transferred to human queue successfully.'
  end

  private

  def account_locale
    @conversation.account.locale.presence || I18n.default_locale.to_s
  end

  def assign_team_and_user(assignee_id, team_id)
    resolved_team_id = team_id.presence || @scout.handover_team_id
    @conversation.team_id = resolved_team_id if resolved_team_id.present?
    @conversation.assignee_id = assignee_id if assignee_id.present?
    @conversation.save!
  end

  def perform_handoff(message: nil)
    status = Conversation.uncached { Conversation.where(id: @conversation.id).pick(:status) }
    return false unless status == 'pending' || status == Conversation.statuses[:pending]

    send_public_handoff_message(message: message)
    @conversation.bot_handoff!
    true
  end

  def send_public_handoff_message(message: nil)
    content = message.presence ||
              reason_message(@action_reason, conversation_locale) ||
              I18n.t('conversations.scout.handoff', locale: conversation_locale)
    Messages::MessageBuilder.new(
      nil,
      @conversation,
      { content: content, message_type: 'outgoing', private: false }
    ).perform
  end

  def reason_message(reason, locale)
    known_reasons = %w[
      explicit_human_request
      human_offer_accepted
      repeated_frustration_or_loop
      out_of_scope_commercial_request
    ]

    return nil unless reason.present? && known_reasons.include?(reason)

    I18n.t("conversations.scout.handoff_reasons.#{reason}.message", locale: locale, default: nil)
  end

  def conversation_locale
    @conversation.language.presence || @conversation.account.locale.presence || I18n.default_locale.to_s
  end

  def create_transfer_note(_reason)
    content = reason_label_and_prefix(@action_reason, account_locale) + opportunity_reference
    Messages::MessageBuilder.new(
      nil,
      @conversation,
      { content: content, private: true }
    ).perform
  end

  # Every handoff path (tool-triggered, stage-transition, or the response auditor's own
  # classifier-based path) funnels through here, so this is the single point that can tag ANY
  # handoff with its opportunity — sparing the agent from hunting the Kanban board to find which
  # deal a transferred conversation is about.
  def opportunity_reference
    opp = associated_opportunity
    return '' if opp.blank?

    " | Oportunidade ##{opp.id} - #{opp.title}"
  end

  def associated_opportunity
    Opportunity.joins(:opportunity_conversations)
               .where(opportunity_conversations: { conversation_id: @conversation.id })
               .order(updated_at: :desc)
               .first
  end

  def generate_contact_memory
    Custom::Scout::ContactNotesService.new(@scout, @conversation).generate_and_update_notes
  end

  def reason_label_and_prefix(reason, locale)
    known_reasons = %w[
      explicit_human_request
      human_offer_accepted
      repeated_frustration_or_loop
      out_of_scope_commercial_request
    ]

    return default_handoff_message(reason) unless reason.present? && known_reasons.include?(reason)

    resolved_note = I18n.t("conversations.scout.handoff_reasons.#{reason}.note",
                           locale: locale, default: nil)
    return "📋 Transferência para atendimento humano: #{reason}" if resolved_note.blank?

    prefix = I18n.t('conversations.scout.handoff_note_prefix', locale: locale)
    "#{prefix}: #{resolved_note}"
  end

  def default_handoff_message(reason)
    "📋 Transferência para atendimento humano: #{reason.presence || 'motivo não informado pelo modelo'}"
  end
end
