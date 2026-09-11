# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Message do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:inbox, :with_email, account: account) }
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

      it 'marks the pending conversation as open on a non-WhatsApp (Email) inbox' do
        ScoutInbox.create!(scout: scout, inbox: email_inbox)
        email_conversation = create(:conversation, account: account, inbox: email_inbox, status: :pending)
        create(:message, message_type: :outgoing, conversation: email_conversation, private: false)

        expect(email_conversation.reload.open?).to be true
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

  describe '#reopen_resolved_conversation' do
    let(:matching_contact) { create(:contact, account: account, phone_number: '+5511999999999') }
    let(:non_matching_contact) { create(:contact, account: account, phone_number: '+5511888888888') }

    before do
      ScoutInbox.create!(scout: scout, inbox: inbox)
      scout.update!(
        audience: [
          {
            'attribute_key' => 'phone_number',
            'filter_operator' => 'equal_to',
            'values' => ['+5511999999999']
          }
        ]
      )
    end

    context 'when Scout has audience configured' do
      it 'reopens conversation as pending when contact matches the audience' do
        resolved_conv = create(:conversation, account: account, inbox: inbox, contact: matching_contact)
        resolved_conv.resolved!
        create(:message, account: account, inbox: inbox, message_type: :incoming, conversation: resolved_conv, sender: matching_contact,
                         private: false)

        expect(resolved_conv.reload.status).to eq('pending')
      end

      it 'reopens conversation as open when contact does not match the audience' do
        resolved_conv = create(:conversation, account: account, inbox: inbox, contact: non_matching_contact)
        resolved_conv.resolved!
        create(:message, account: account, inbox: inbox, message_type: :incoming, conversation: resolved_conv, sender: non_matching_contact,
                         private: false)

        expect(resolved_conv.reload.status).to eq('open')
      end

      it 'preserves Current.executed_by attribution on API channels when reopened by contact' do
        channel_api = create(:channel_api, account: account)
        api_inbox = channel_api.inbox
        ScoutInbox.create!(scout: scout, inbox: api_inbox)

        resolved_conv = create(:conversation, account: account, inbox: api_inbox, contact: non_matching_contact)
        resolved_conv.resolved!

        expect do
          create(:message, account: account, inbox: api_inbox, conversation: resolved_conv, sender: non_matching_contact, message_type: :incoming,
                           private: false)
        end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
          resolved_conv,
          hash_including(content: I18n.t('conversations.activity.status.system_auto_open'))
        )

        expect(resolved_conv.reload.status).to eq('open')
      end
    end

    context 'when Scout is disabled' do
      before do
        scout.update!(enabled: false)
      end

      it 'calls super and reopens as open' do
        resolved_conv = create(:conversation, account: account, inbox: inbox, contact: matching_contact)
        resolved_conv.resolved!
        create(:message, account: account, inbox: inbox, message_type: :incoming, conversation: resolved_conv, sender: matching_contact,
                         private: false)

        expect(resolved_conv.reload.status).to eq('open')
      end
    end

    context 'when inbox has no Scout' do
      let(:other_inbox) { create(:inbox, account: account) }

      it 'calls super and reopens as open' do
        resolved_conv = create(:conversation, account: account, inbox: other_inbox, contact: matching_contact)
        resolved_conv.resolved!
        create(:message, account: account, inbox: other_inbox, message_type: :incoming, conversation: resolved_conv, sender: matching_contact,
                         private: false)

        expect(resolved_conv.reload.status).to eq('open')
      end
    end

    context 'when Captain is also present on the inbox' do
      let(:captain_assistant) { create(:captain_assistant, account: account) }

      before do
        create(:captain_inbox, inbox: inbox, captain_assistant: captain_assistant)
      end

      it 'short-circuits to open for non-matching contact without delegating to Captain' do
        resolved_conv = create(:conversation, account: account, inbox: inbox, contact: non_matching_contact)
        resolved_conv.resolved!
        create(:message, account: account, inbox: inbox, message_type: :incoming, conversation: resolved_conv, sender: non_matching_contact,
                         private: false)

        expect(resolved_conv.reload.status).to eq('open')
      end

      it 'delegates to super (Enterprise Captain) when contact matches Scout audience' do
        resolved_conv = create(:conversation, account: account, inbox: inbox, contact: matching_contact)
        resolved_conv.resolved!
        create(:message, account: account, inbox: inbox, message_type: :incoming, conversation: resolved_conv, sender: matching_contact,
                         private: false)

        expect(resolved_conv.reload.status).to eq('pending')
      end

      it 'routes to open if Captain assistant does not engage even though Scout matches' do
        captain_assistant.config['audience'] = {
          'attribute_key' => 'phone_number',
          'filter_operator' => 'equal_to',
          'values' => ['+10000000000']
        }
        captain_assistant.save!

        resolved_conv = create(:conversation, account: account, inbox: inbox, contact: matching_contact)
        resolved_conv.resolved!
        create(:message, account: account, inbox: inbox, message_type: :incoming, conversation: resolved_conv, sender: matching_contact,
                         private: false)

        expect(resolved_conv.reload.status).to eq('open')
      end
    end
  end
end
