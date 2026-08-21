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
  end
end
