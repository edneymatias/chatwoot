# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::IncomingMessageBaseService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, campaign_type: :one_off) }
  let!(:recipient) do
    Custom::CampaignRecipient.create!(
      account: account,
      campaign: campaign,
      contact: contact,
      inbox: inbox,
      status: :sent,
      source_id: 'outbound_wamid_123',
      message_content: 'Promotional offer!',
      sent_at: 2.hours.ago
    )
  end

  before do
    account.enable_features!(:whatsapp_campaign)
  end

  describe '#process_statuses' do
    let(:status_payload) do
      {
        'statuses' => [
          {
            'id' => 'outbound_wamid_123',
            'status' => 'delivered',
            'timestamp' => Time.current.to_i.to_s
          }
        ]
      }.with_indifferent_access
    end

    it 'updates Custom::CampaignRecipient status without calling enterprise logic' do
      Whatsapp::IncomingMessageService.new(inbox: inbox, params: status_payload).perform

      expect(recipient.reload.status).to eq('delivered')
      expect(recipient.delivered_at).to be_present
    end

    context 'when neither a Custom::CampaignRecipient nor a Message is persisted yet' do
      let(:status_payload) do
        {
          'statuses' => [
            {
              'id' => 'wamid.not-persisted-yet',
              'status' => 'delivered',
              'timestamp' => Time.current.to_i.to_s
            }
          ]
        }.with_indifferent_access
      end

      it 'defers reconciliation via Custom::UpdateCampaignRecipientStatusJob' do
        expect do
          Whatsapp::IncomingMessageService.new(inbox: inbox, params: status_payload).perform
        end.to have_enqueued_job(Custom::UpdateCampaignRecipientStatusJob)
          .with(inbox.id, status_payload['statuses'].first).on_queue('low')
      end
    end
  end

  describe '#set_conversation reply correlation' do
    context 'when reply contains context.id matching recipient source_id (quick-reply button)' do
      let(:button_payload) do
        {
          'contacts' => [{ 'profile' => { 'name' => 'Jane' }, 'wa_id' => '15551234567' }],
          'messages' => [
            {
              'id' => 'inbound_wamid_btn',
              'from' => '15551234567',
              'timestamp' => Time.current.to_i.to_s,
              'type' => 'interactive',
              'interactive' => {
                'button_reply' => { 'id' => 'btn_1', 'title' => 'Yes, schedule now' }
              },
              'context' => { 'id' => 'outbound_wamid_123' }
            }
          ]
        }.with_indifferent_access
      end

      it 'attributes conversation to campaign and backfills context message first' do
        expect do
          Whatsapp::IncomingMessageService.new(inbox: inbox, params: button_payload).perform
        end.to change(Conversation, :count).by(1)

        conversation = Conversation.last
        expect(conversation.campaign_id).to eq(campaign.id)
        expect(conversation.messages.count).to eq(2)
        expect(conversation.messages.first.message_type).to eq('outgoing')
        expect(conversation.messages.first.source_id).to eq('outbound_wamid_123')
        expect(conversation.messages.second.message_type).to eq('incoming')
      end

      it 'marks recipient replied with attribution details and campaign message id' do
        payload = button_payload.deep_dup
        payload['messages'].first['id'] = 'inbound_wamid_btn_2'
        Whatsapp::IncomingMessageService.new(inbox: inbox, params: payload).perform

        first_msg = Conversation.last.messages.first
        expect(recipient.reload.status).to eq('replied')
        expect(recipient.reply_type).to eq('quick_reply')
        expect(recipient.reply_label).to eq('Yes, schedule now')
        expect(recipient.reply_source_id).to eq('inbound_wamid_btn_2')
        expect(recipient.campaign_message_id).to eq(first_msg.id)
      end
    end

    context 'when reply is unambiguous free text without context.id within 72h window' do
      let(:free_text_payload) do
        {
          'contacts' => [{ 'profile' => { 'name' => 'Jane' }, 'wa_id' => '15551234567' }],
          'messages' => [
            {
              'id' => 'inbound_wamid_text',
              'from' => '15551234567',
              'timestamp' => Time.current.to_i.to_s,
              'type' => 'text',
              'text' => { 'body' => 'I would like more info' }
            }
          ]
        }.with_indifferent_access
      end

      it 'correlates to single candidate campaign, backfills context, and marks recipient replied' do
        Whatsapp::IncomingMessageService.new(inbox: inbox, params: free_text_payload).perform

        conversation = Conversation.last
        expect(conversation.campaign_id).to eq(campaign.id)
        expect(conversation.messages.first.content).to eq('Promotional offer!')

        expect(recipient.reload.status).to eq('replied')
        expect(recipient.reply_type).to eq('free_text')
        expect(recipient.reply_label).to be_nil
        expect(recipient.reply_source_id).to eq('inbound_wamid_text')
      end
    end

    context 'when free text reply is ambiguous due to multiple candidate sends within 72h' do
      let(:free_text_payload) do
        {
          'contacts' => [{ 'profile' => { 'name' => 'Jane' }, 'wa_id' => '15551234567' }],
          'messages' => [
            {
              'id' => 'inbound_wamid_ambig',
              'from' => '15551234567',
              'timestamp' => Time.current.to_i.to_s,
              'type' => 'text',
              'text' => { 'body' => 'Ambiguous response' }
            }
          ]
        }.with_indifferent_access
      end

      before do
        campaign2 = create(:campaign, account: account, inbox: inbox, campaign_type: :one_off)
        Custom::CampaignRecipient.create!(
          account: account,
          campaign: campaign2,
          contact: contact,
          inbox: inbox,
          status: :sent,
          source_id: 'outbound_wamid_456',
          message_content: 'Second campaign message',
          sent_at: 1.hour.ago
        )
      end

      it 'does not attribute campaign and does not backfill context message' do
        Whatsapp::IncomingMessageService.new(inbox: inbox, params: free_text_payload).perform

        conversation = Conversation.last
        expect(conversation.campaign_id).to be_nil
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.source_id).to eq('inbound_wamid_ambig')

        expect(recipient.reload.status).to eq('sent')
      end
    end

    context 'when contact already has an open conversation' do
      let!(:existing_conversation) do
        create(
          :conversation,
          account: account,
          inbox: inbox,
          contact: contact,
          contact_inbox: create(:contact_inbox, contact: contact, inbox: inbox),
          campaign_id: nil,
          status: :open
        )
      end
      let(:reply_payload) do
        {
          'contacts' => [{ 'profile' => { 'name' => 'Jane' }, 'wa_id' => '15551234567' }],
          'messages' => [
            {
              'id' => 'inbound_wamid_open',
              'from' => '15551234567',
              'timestamp' => Time.current.to_i.to_s,
              'type' => 'text',
              'text' => { 'body' => 'Replying while open' },
              'context' => { 'id' => 'outbound_wamid_123' }
            }
          ]
        }.with_indifferent_access
      end

      it 'leaves existing conversation campaign attribution untouched and does not backfill context' do
        expect do
          Whatsapp::IncomingMessageService.new(inbox: inbox, params: reply_payload).perform
        end.not_to change(Conversation, :count)

        expect(existing_conversation.reload.campaign_id).to be_nil
        # Only the incoming reply is added, not the context backfill
        expect(existing_conversation.messages.count).to eq(1)
        expect(existing_conversation.messages.first.source_id).to eq('inbound_wamid_open')
      end
    end
  end
end
