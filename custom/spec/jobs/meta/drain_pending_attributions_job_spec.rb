# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Meta::DrainPendingAttributionsJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let!(:setting) { CampaignAttributionSetting.create!(account: account, enabled: true, provider_config: { 'access_token' => 'test_token' }) }

  let!(:pending_op_1) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage,
      status: :open,
      title: 'Pending Op 1',
      campaign_source_id: '12345',
      campaign_resolution_status: 'pending'
    )
  end

  let!(:pending_op_2) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage,
      status: :open,
      title: 'Pending Op 2',
      campaign_source_id: '67890',
      campaign_resolution_status: 'pending'
    )
  end

  before do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage,
      status: :open,
      title: 'Resolved Op',
      campaign_source_id: '99999',
      campaign_resolution_status: 'resolved'
    )
  end

  describe '#perform' do
    it 'enqueues CampaignResolutionJob for all pending opportunities with campaign_source_id' do
      clear_enqueued_jobs
      expect do
        described_class.perform_now(account.id)
      end.to have_enqueued_job(Custom::CampaignResolutionJob).with(pending_op_1.id)
         .and have_enqueued_job(Custom::CampaignResolutionJob).with(pending_op_2.id)
         .and have_enqueued_job(Custom::CampaignResolutionJob).exactly(2).times
    end

    it 'does nothing if setting is disabled' do
      setting.update!(enabled: false)

      expect do
        described_class.perform_now(account.id)
      end.not_to have_enqueued_job(Custom::CampaignResolutionJob)
    end
  end
end
