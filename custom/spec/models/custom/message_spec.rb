# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Message do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:scout) { Scout.create!(account: account, name: 'SDR Bot', enabled: true) }

  describe '#mark_pending_conversation_as_open_for_human_response' do
    context 'when Scout is enabled on the inbox' do
      before do
        ScoutInbox.create!(scout: scout, inbox: inbox)
      end

      it 'marks the pending conversation as open when a human agent sends a public outgoing message' do
        create(:message, message_type: :outgoing, conversation: conversation, private: false)

        expect(conversation.reload.open?).to be true
      end

      it 'does not mark the conversation as open when the outgoing message is a private note' do
        create(:message, message_type: :outgoing, conversation: conversation, private: true)

        expect(conversation.reload.pending?).to be true
      end

      it 'does not mark the conversation as open when the message is incoming' do
        create(:message, message_type: :incoming, conversation: conversation, private: false)

        expect(conversation.reload.pending?).to be true
      end

      it 'does not mark the conversation as open when the outgoing message is sent by a bot/system' do
        create(:message, :bot_message, conversation: conversation, private: false)

        expect(conversation.reload.pending?).to be true
      end
    end

    context 'when Scout is disabled on the inbox' do
      before do
        scout.update!(enabled: false)
        ScoutInbox.create!(scout: scout, inbox: inbox)
      end

      it 'does not mark the pending conversation as open when a human agent sends a public outgoing message' do
        create(:message, message_type: :outgoing, conversation: conversation, private: false)

        expect(conversation.reload.pending?).to be true
      end
    end

    context 'when inbox has no Scout attached' do
      it 'does not mark the pending conversation as open when a human agent sends a public outgoing message' do
        create(:message, message_type: :outgoing, conversation: conversation, private: false)

        expect(conversation.reload.pending?).to be true
      end
    end

    context 'when Captain is also present on the inbox' do
      let(:captain_assistant) { create(:captain_assistant, account: account) }

      before do
        create(:captain_inbox, inbox: inbox, captain_assistant: captain_assistant)
      end

      it 'delegates to super and marks conversation as open via Captain handling' do
        create(:message, message_type: :outgoing, conversation: conversation, private: false)

        expect(conversation.reload.open?).to be true
      end
    end
  end
end
