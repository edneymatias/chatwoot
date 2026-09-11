# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Inbox do
  let(:account) { create(:account) }
  let(:widget_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:inbox, :with_email, account: account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false) }
  let(:whatsapp_inbox) { create(:inbox, account: account, channel: whatsapp_channel) }
  let(:scout) { Scout.create!(account: account, name: 'SDR Bot', enabled: true) }

  before do
    stub_request(:post, %r{waba.360dialog.io/v1/configs/webhook}).to_return(status: 200, body: '', headers: {})
  end

  describe '#active_bot?' do
    context 'when Scout is enabled on the inbox' do
      it 'returns true for a WebWidget inbox' do
        ScoutInbox.create!(scout: scout, inbox: widget_inbox)

        expect(widget_inbox.active_bot?).to be true
      end

      it 'returns true for an Email inbox' do
        ScoutInbox.create!(scout: scout, inbox: email_inbox)

        expect(email_inbox.active_bot?).to be true
      end

      it 'returns true for a WhatsApp inbox' do
        ScoutInbox.create!(scout: scout, inbox: whatsapp_inbox)

        expect(whatsapp_inbox.active_bot?).to be true
      end

      it 'causes newly created conversations to start as pending' do
        ScoutInbox.create!(scout: scout, inbox: widget_inbox)
        contact = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: widget_inbox)
        conversation = create(:conversation, account: account, inbox: widget_inbox, contact: contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('pending')
      end
    end

    context 'when Scout is disabled on the inbox' do
      before do
        scout.update!(enabled: false)
        ScoutInbox.create!(scout: scout, inbox: widget_inbox)
      end

      it 'returns false' do
        expect(widget_inbox.active_bot?).to be false
      end

      it 'causes newly created conversations to start as open' do
        contact = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: widget_inbox)
        conversation = create(:conversation, account: account, inbox: widget_inbox, contact: contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('open')
      end
    end

    context 'when inbox has no Scout attached' do
      it 'returns false' do
        expect(widget_inbox.active_bot?).to be false
      end

      it 'causes newly created conversations to start as open' do
        contact = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: widget_inbox)
        conversation = create(:conversation, account: account, inbox: widget_inbox, contact: contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('open')
      end
    end

    context 'when legacy agent bot is active on the inbox' do
      let(:agent_bot) { create(:agent_bot) }

      before do
        create(:agent_bot_inbox, inbox: widget_inbox, agent_bot: agent_bot)
      end

      it 'delegates to super and returns true even without Scout' do
        expect(widget_inbox.active_bot?).to be true
      end
    end

    context 'when Captain is active on the inbox' do
      let(:captain_assistant) { create(:captain_assistant, account: account) }

      before do
        create(:captain_inbox, inbox: widget_inbox, captain_assistant: captain_assistant)
      end

      it 'delegates to super and returns true even without Scout' do
        expect(widget_inbox.active_bot?).to be true
      end
    end
  end
end
