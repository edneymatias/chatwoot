# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ProcessMessageJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Debounce Scout',
      debounce_delay_seconds: 4,
      enabled: true
    )
  end

  before do
    ScoutInbox.create!(scout: scout, inbox: inbox)
    Redis::Alfred.delete(format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id))
    Redis::Alfred.delete(format(described_class::ENQUEUED_KEY, conversation_id: conversation.id))
  end

  describe '.enqueue_debounced' do
    it 'sets last_message_at and enqueues job on first message' do
      expect do
        described_class.enqueue_debounced(conversation, scout)
      end.to have_enqueued_job(described_class).with(conversation.id)

      last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
      enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)

      expect(Redis::Alfred.get(last_msg_key)).to be_present
      expect(Redis::Alfred.get(enqueued_key)).to be_present
    end

    it 'does not enqueue duplicate jobs for subsequent messages in the same burst' do
      described_class.enqueue_debounced(conversation, scout)

      expect do
        described_class.enqueue_debounced(conversation, scout)
      end.not_to have_enqueued_job(described_class)
    end
  end

  describe '#perform' do
    let(:runner_instance) { instance_double(Custom::Scout::AgentRunner, perform: true) }

    before do
      allow(Custom::Scout::AgentRunner).to receive(:new).and_return(runner_instance)
    end

    it 'triggers runner and cleans up Redis keys when delay has elapsed' do
      last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
      enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)

      # Simulate message arrived 5 seconds ago (delay is 4 seconds)
      Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
      Redis::Alfred.set(enqueued_key, true)

      described_class.new.perform(conversation.id)

      expect(Custom::Scout::AgentRunner).to have_received(:new).with(scout: scout, conversation: conversation)
      expect(runner_instance).to have_received(:perform)
      expect(Redis::Alfred.get(last_msg_key)).to be_nil
      expect(Redis::Alfred.get(enqueued_key)).to be_nil
    end

    it 'reschedules job when delay has not yet elapsed (sliding window reset)' do
      last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
      enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)

      # Simulate message arrived 2 seconds ago (delay is 4 seconds)
      Redis::Alfred.set(last_msg_key, Time.current.to_f - 2.0)
      Redis::Alfred.set(enqueued_key, true)

      expect do
        described_class.new.perform(conversation.id)
      end.to have_enqueued_job(described_class).with(conversation.id)

      expect(Custom::Scout::AgentRunner).not_to have_received(:new)
    end

    context 'when Scout has audience configured' do
      before do
        scout.update!(
          audience: [
            {
              'attribute_key' => 'labels',
              'filter_operator' => 'equal_to',
              'values' => ['vip']
            }
          ]
        )
      end

      it 'opens conversation and does not run AgentRunner when contact does not match audience' do
        contact.update_labels(['other'])
        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        expect(Custom::Scout::AgentRunner).not_to have_received(:new)
        expect(conversation.reload.status).to eq('open')
        expect(Redis::Alfred.get(last_msg_key)).to be_nil
        expect(Redis::Alfred.get(enqueued_key)).to be_nil
      end
    end

    context 'when scout_v2 feature flag is enabled' do
      let(:v2_runner_instance) do
        instance_double(Custom::ScoutV2::TurnRunner, perform: { reply: 'Resposta do Scout V2', tool_calls: [] })
      end

      before do
        account.enable_features!('scout_v2')
        allow(Custom::ScoutV2::TurnRunner).to receive(:new).and_return(v2_runner_instance)
      end

      it 'dispatches via TurnRunner, creates an outgoing Message, and increments responses_consumed' do
        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        expect do
          described_class.new.perform(conversation.id)
        end.to change { conversation.messages.where(message_type: :outgoing).count }.by(1)

        expect(scout.reload.responses_consumed).to eq(1)

        expect(Custom::ScoutV2::TurnRunner).to have_received(:new).with(scout: scout, conversation: conversation)
        expect(v2_runner_instance).to have_received(:perform)
        expect(Custom::Scout::AgentRunner).not_to have_received(:new)
        expect(conversation.messages.where(message_type: :outgoing).last.content).to eq('Resposta do Scout V2')
      end

      it 'switches immediately back to AgentRunner when flag is disabled' do
        account.disable_features!('scout_v2')
        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        expect(Custom::Scout::AgentRunner).to have_received(:new).with(scout: scout, conversation: conversation)
        expect(Custom::ScoutV2::TurnRunner).not_to have_received(:new)
      end
    end
  end
end
