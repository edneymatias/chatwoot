# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Campaign recipients API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago) }

  let(:delivered_contact) { create(:contact, :with_phone_number, account: account) }
  let(:read_contact) { create(:contact, :with_phone_number, account: account) }
  let(:btn_contact1) { create(:contact, :with_phone_number, account: account) }
  let(:btn_contact2) { create(:contact, :with_phone_number, account: account) }
  let(:free_contact) { create(:contact, :with_phone_number, account: account) }
  let(:failed_contact) { create(:contact, :with_phone_number, account: account) }
  let(:skipped_contact) { create(:contact, account: account) }

  before do
    account.enable_features!(:whatsapp_campaign)

    Custom::CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: delivered_contact,
                                      status: :delivered, source_id: 'wamid.delivered')
    Custom::CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: read_contact,
                                      status: :read, source_id: 'wamid.read')
    Custom::CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: btn_contact1,
                                      status: :replied, source_id: 'wamid.btn1', replied_at: Time.current,
                                      reply_type: :quick_reply, reply_label: 'Yes, schedule')
    Custom::CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: btn_contact2,
                                      status: :replied, source_id: 'wamid.btn2', replied_at: Time.current,
                                      reply_type: :quick_reply, reply_label: 'Yes, schedule')
    Custom::CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: free_contact,
                                      status: :replied, source_id: 'wamid.free', replied_at: Time.current,
                                      reply_type: :free_text)
    Custom::CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: failed_contact, status: :failed)
    Custom::CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: skipped_contact, status: :skipped)
  end

  describe 'GET /api/v1/accounts/:account_id/campaigns/:campaign_id/recipients/metrics' do
    it 'returns cumulative metrics, replied count, and status counts' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/recipients/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'audience' => 7,
        'sent' => 5,
        'delivered' => 5,
        'read' => 1,
        'replied' => 3,
        'failed' => 1,
        'skipped' => 1,
        'status_counts' => include('delivered' => 1, 'read' => 1, 'replied' => 3, 'failed' => 1, 'skipped' => 1)
      )
    end

    it 'requires the WhatsApp campaign feature' do
      account.disable_features!(:whatsapp_campaign)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/recipients/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires administrator access' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/recipients/metrics",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/campaigns/:campaign_id/recipients/contacts' do
    it 'returns paginated recipient contacts and allows filtering by status' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/recipients/contacts",
          params: { status: 'replied' },
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload.size).to eq(3)
      expect(payload.pluck('status').uniq).to eq(['replied'])
      expect(response.parsed_body['meta']['total_count']).to eq(3)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/campaigns/:campaign_id/recipients/reply_breakdown' do
    it 'returns button clicks breakdown ordered by count with a trailing other row and click rates' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/recipients/reply_breakdown",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body
      expect(rows).to be_an(Array)
      expect(rows.size).to eq(2)

      # 5 total sent (source_id present)
      # 2 clicked 'Yes, schedule' -> rate: 2/5 = 0.4
      expect(rows.first).to eq(
        'label' => 'Yes, schedule',
        'total_clicks' => 2,
        'click_rate' => 0.4
      )

      # 1 other (free text) -> rate: 1/5 = 0.2
      expect(rows.second).to eq(
        'label' => 'other',
        'total_clicks' => 1,
        'click_rate' => 0.2
      )
    end
  end
end
