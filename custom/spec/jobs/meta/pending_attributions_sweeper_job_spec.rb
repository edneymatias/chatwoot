# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Meta::PendingAttributionsSweeperJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }

  before do
    CampaignAttributionSetting.create!(account: account, enabled: true, provider_config: { 'access_token' => 'test_token' })
  end

  describe '#perform' do
    it 'enqueues DrainPendingAttributionsJob when account has pending opportunities older than 15 minutes' do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        status: :open,
        title: 'Old Pending Op',
        campaign_source_id: '12345',
        campaign_resolution_status: 'pending',
        created_at: 20.minutes.ago
      )

      expect do
        described_class.perform_now
      end.to have_enqueued_job(Meta::DrainPendingAttributionsJob).with(account.id)
    end

    it 'does not enqueue DrainPendingAttributionsJob if pending opportunities are newer than 15 minutes' do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        status: :open,
        title: 'Recent Pending Op',
        campaign_source_id: '12345',
        campaign_resolution_status: 'pending',
        created_at: 5.minutes.ago
      )

      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(Meta::DrainPendingAttributionsJob)
    end
  end
end
