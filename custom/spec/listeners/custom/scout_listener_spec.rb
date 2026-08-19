# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutListener do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false) }
  let(:whatsapp_inbox) { create(:inbox, account: account, channel: whatsapp_channel) }
  let(:email_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: whatsapp_inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, contact_inbox: contact_inbox, status: :pending)
  end
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'WhatsApp SDR',
      provider: :gemini,
      model_name: 'gemini-2.0-flash',
      enabled: true
    )
  end

  before do
    stub_request(:post, %r{waba.360dialog.io/v1/configs/webhook}).to_return(status: 200, body: '', headers: {})
    ScoutInbox.create!(scout: scout, inbox: whatsapp_inbox)
    allow(Custom::Scout::ProcessMessageJob).to receive(:enqueue_debounced)
  end

  describe '#message_created' do
    it 'enqueues debounced message job for incoming WhatsApp messages on enabled Scout inboxes' do
      message = create(:message, account: account, inbox: whatsapp_inbox, conversation: conversation, message_type: :incoming, private: false)
      event = Events::Base.new('message.created', Time.current, message: message)

      described_class.instance.message_created(event)
      expect(Custom::Scout::ProcessMessageJob).to have_received(:enqueue_debounced).with(conversation, scout)
    end

    it 'ignores private messages' do
      message = create(:message, account: account, inbox: whatsapp_inbox, conversation: conversation, message_type: :incoming, private: true)
      event = Events::Base.new('message.created', Time.current, message: message)

      described_class.instance.message_created(event)
      expect(Custom::Scout::ProcessMessageJob).not_to have_received(:enqueue_debounced)
    end

    it 'ignores non-WhatsApp inboxes' do
      email_contact_inbox = create(:contact_inbox, contact: contact, inbox: email_inbox)
      email_conv = create(:conversation, account: account, inbox: email_inbox, contact: contact, contact_inbox: email_contact_inbox, status: :pending)
      message = create(:message, account: account, inbox: email_inbox, conversation: email_conv, message_type: :incoming, private: false)
      event = Events::Base.new('message.created', Time.current, message: message)

      described_class.instance.message_created(event)
      expect(Custom::Scout::ProcessMessageJob).not_to have_received(:enqueue_debounced)
    end

    it 'ignores inboxes where Scout is disabled' do
      scout.update!(enabled: false)
      message = create(:message, account: account, inbox: whatsapp_inbox, conversation: conversation, message_type: :incoming, private: false)
      event = Events::Base.new('message.created', Time.current, message: message)

      described_class.instance.message_created(event)
      expect(Custom::Scout::ProcessMessageJob).not_to have_received(:enqueue_debounced)
    end

    it 'ignores non-pending conversations' do
      conversation.update!(status: :open)
      message = create(:message, account: account, inbox: whatsapp_inbox, conversation: conversation, message_type: :incoming, private: false)
      event = Events::Base.new('message.created', Time.current, message: message)

      described_class.instance.message_created(event)
      expect(Custom::Scout::ProcessMessageJob).not_to have_received(:enqueue_debounced)
    end
  end
end
