# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ResponseAuditor do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Auditor Scout',
      enabled: true,
      feature_response_auditor: true
    )
  end
  let(:auditor) { described_class.new(scout: scout, conversation: conversation) }

  let(:fake_chat) { instance_double(RubyLLM::Chat) }
  let(:message_history) do
    [
      { role: 'user', content: 'Qual o valor?' }
    ]
  end
  let(:recorded_tool_calls) { [] }
  let(:original_reply) { 'O valor é R$ 500,00 e já atualizei sua oportunidade.' }

  let(:claim_service) { instance_double(Custom::Scout::ClaimConsistencyService) }
  let(:action_service) { instance_double(Custom::Scout::ActionClassifierService) }

  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)

    allow(Custom::Scout::ClaimConsistencyService).to receive(:new).with(scout: scout, conversation: conversation).and_return(claim_service)
    allow(Custom::Scout::ActionClassifierService).to receive(:new).with(scout: scout, conversation: conversation).and_return(action_service)
    allow(action_service).to receive(:classify).and_return({ 'action' => 'continue', 'action_reason' => nil })
  end

  describe '#audit (US1: claim consistency)' do
    it 'leaves reply unchanged when consistency decision is safe' do
      allow(claim_service).to receive(:check).and_return({ 'decision' => 'safe', 'reason' => 'All good' })

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: original_reply })
    end

    it 'triggers one internal repair on false_completed_action and returns repaired reply when reverified as safe' do
      allow(claim_service).to receive(:check).and_return(
        { 'decision' => 'false_completed_action', 'reason' => 'No tool call executed' },
        { 'decision' => 'safe', 'reason' => 'Repaired' }
      )

      repaired_json = { 'response' => 'O valor é R$ 500,00.', 'reasoning' => 'Fixed' }.to_json
      repaired_llm_message = instance_double(RubyLLM::Message, content: repaired_json)
      expect(fake_chat).to receive(:ask).with(/ATENÇÃO|não foi executada/i).once.and_return(repaired_llm_message)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: 'O valor é R$ 500,00.' })
    end

    it 'signals escalation when reply remains inconsistent after one repair' do
      allow(claim_service).to receive(:check).and_return(
        { 'decision' => 'false_completed_action', 'reason' => 'No tool call executed' },
        { 'decision' => 'false_completed_action', 'reason' => 'Still claiming update' }
      )

      repaired_json = { 'response' => 'Oportunidade já atualizada!', 'reasoning' => 'Repeated' }.to_json
      repaired_llm_message = instance_double(RubyLLM::Message, content: repaired_json)
      expect(fake_chat).to receive(:ask).once.and_return(repaired_llm_message)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result[:action]).to eq(:escalate)
      expect(result[:reason]).to be_present
    end

    it 'signals handoff instead of dispatching a second reply when the repair call itself triggers a handoff' do
      allow(claim_service).to receive(:check).and_return({ 'decision' => 'false_completed_action', 'reason' => 'No tool call executed' })

      repaired_json = { 'response' => 'Vou te transferir para um especialista.', 'reasoning' => 'Handed off during repair' }.to_json
      repaired_llm_message = instance_double(RubyLLM::Message, content: repaired_json)
      expect(fake_chat).to receive(:ask).once do
        conversation.update!(status: :open)
        repaired_llm_message
      end

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :handoff })
    end

    it 'rescues any StandardError, logs warning, captures exception, and returns original reply unchanged' do
      allow(claim_service).to receive(:check).and_raise(StandardError, 'Unexpected auditor crash')
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      expect(tracker).to receive(:capture_exception).at_least(:once)
      expect(Rails.logger).to receive(:warn).with(/ResponseAuditor/)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: original_reply })
    end

    it 'does not call ClaimConsistencyService if conversation is no longer pending' do
      conversation.update!(status: :resolved)

      expect(claim_service).not_to receive(:check)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: original_reply })
    end

    it 'skips reverification and repair if conversation stops being pending mid-turn' do
      allow(claim_service).to receive(:check) do
        conversation.update!(status: :open)
        { 'decision' => 'false_completed_action', 'reason' => 'No tool call' }
      end

      expect(fake_chat).not_to receive(:ask)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: original_reply })
    end
  end

  describe '#audit (US2: action classifier and broad promise repair)' do
    let(:handoff_service) { instance_double(Custom::Scout::HandoffService) }

    before do
      allow(Custom::Scout::HandoffService).to receive(:new).with(scout: scout, conversation: conversation).and_return(handoff_service)
      allow(claim_service).to receive(:check).and_return({ 'decision' => 'safe', 'reason' => 'All good' })
    end

    it 'calls HandoffService and skips ClaimConsistencyService when two independent classifications agree on handoff' do
      expect(action_service).to receive(:classify).twice.and_return({ 'action' => 'handoff', 'action_reason' => 'explicit_human_request' })
      expect(handoff_service).to receive(:perform).with(reason: 'explicit_human_request')
      expect(claim_service).not_to receive(:check)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :handoff })
    end

    it 'does not handoff and falls through to claim consistency when the confirmation call disagrees (single-call hallucination guard)' do
      expect(action_service).to receive(:classify).twice.and_return(
        { 'action' => 'handoff', 'action_reason' => 'human_offer_accepted' },
        { 'action' => 'continue', 'action_reason' => nil }
      )
      expect(handoff_service).not_to receive(:perform)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: original_reply })
    end

    it 'confirms the initial handoff decision with a higher temperature so the second call is a genuinely independent draw' do
      allow(action_service).to receive(:classify)
        .with(message_history: message_history, temperature: 0.0)
        .and_return({ 'action' => 'handoff', 'action_reason' => 'human_offer_accepted' })
      allow(action_service).to receive(:classify)
        .with(message_history: message_history, temperature: described_class::CONFIRMATION_TEMPERATURE)
        .and_return({ 'action' => 'handoff', 'action_reason' => 'human_offer_accepted' })
      expect(handoff_service).to receive(:perform).with(reason: 'human_offer_accepted')

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :handoff })
    end

    it 'does not handoff when the confirmation call agrees on handoff but with a different reason' do
      expect(action_service).to receive(:classify).twice.and_return(
        { 'action' => 'handoff', 'action_reason' => 'human_offer_accepted' },
        { 'action' => 'handoff', 'action_reason' => 'explicit_human_request' }
      )
      expect(handoff_service).not_to receive(:perform)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: original_reply })
    end

    it 'triggers repair on false_promise decision and reverifies both action classifier and claim consistency' do
      allow(claim_service).to receive(:check).and_return(
        { 'decision' => 'false_promise', 'reason' => 'Promised callback' },
        { 'decision' => 'safe', 'reason' => 'Repaired' }
      )

      repaired_json = { 'response' => 'Vou verificar as informações agora.', 'reasoning' => 'Fixed promise' }.to_json
      repaired_llm_message = instance_double(RubyLLM::Message, content: repaired_json)
      expect(fake_chat).to receive(:ask).once.and_return(repaired_llm_message)
      expect(action_service).to receive(:classify).twice.and_return({ 'action' => 'continue', 'action_reason' => nil })

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: 'Vou verificar as informações agora.' })
    end

    it 'stops and does not call HandoffService or ClaimConsistencyService if status changes to non-pending after ActionClassifier' do
      allow(action_service).to receive(:classify) do
        conversation.update!(status: :resolved)
        { 'action' => 'continue', 'action_reason' => nil }
      end

      expect(claim_service).not_to receive(:check)
      expect(handoff_service).not_to receive(:perform)

      result = auditor.audit(
        chat: fake_chat,
        response_text: original_reply,
        message_history: message_history,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result).to eq({ action: :proceed, reply: original_reply })
    end
  end
end
