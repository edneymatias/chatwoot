# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::OneoffCampaignService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:label) { create(:label, account: account) }
  let(:contact1) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:contact_no_phone) { create(:contact, account: account, phone_number: nil) }
  let(:campaign) do
    create(
      :campaign,
      inbox: whatsapp_inbox,
      account: account,
      message: 'Hello {{contact.name}}!',
      audience: [{ type: 'Label', id: label.id }],
      template_params: template_params
    )
  end
  let(:template_params) do
    {
      'name' => 'sample_template',
      'namespace' => '123_456',
      'category' => 'MARKETING',
      'language' => 'en',
      'processed_params' => { 'body' => { '1' => 'John' } }
    }
  end

  before do
    account.enable_features!(:whatsapp_campaign)
    stub_request(:post, /graph\.facebook\.com.*messages/)
      .to_return(status: 200, body: { messages: [{ id: 'wamid_test_123' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    allow_any_instance_of(Whatsapp::OneoffCampaignService).to receive(:channel).and_return(whatsapp_channel) # rubocop:disable RSpec/AnyInstance
  end

  describe '#perform' do
    it 'creates Custom::CampaignRecipient records and not enterprise CampaignRecipient records' do
      contact1.update!(label_list: [label.title])

      expect do
        Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
      end.to change(Custom::CampaignRecipient, :count).by(1)
                                                      .and not_change(CampaignRecipient, :count)

      recipient = campaign.ichatr_campaign_recipients.find_by(contact: contact1)
      expect(recipient).to be_present
      expect(recipient.status).to eq('sent')
      expect(recipient.source_id).to eq('wamid_test_123')
      expect(recipient.sent_at).to be_present
      expect(recipient.message_content).to eq("Hello #{contact1.name}!")
      expect(campaign.reload).to be_completed
    end

    it 'marks recipient as skipped when contact has no phone number' do
      contact_no_phone.update!(label_list: [label.title])

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      recipient = campaign.ichatr_campaign_recipients.find_by(contact: contact_no_phone)
      expect(recipient).to be_present
      expect(recipient.status).to eq('skipped')
      expect(recipient.error_message).to eq('Phone number is missing')
    end

    it 'marks recipient as failed when provider returns an error' do
      contact1.update!(label_list: [label.title])
      allow(whatsapp_channel).to receive(:send_template).and_raise(StandardError.new('Provider error'))

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      recipient = campaign.ichatr_campaign_recipients.find_by(contact: contact1)
      expect(recipient).to be_present
      expect(recipient.status).to eq('failed')
      expect(recipient.error_message).to eq('Provider error')
    end
  end
end
