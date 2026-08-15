require 'rails_helper'

RSpec.describe 'meta_marketing:backfill_referral_attribution', type: :task do
  include ActiveJob::TestHelper

  before :all do
    Rails.application.load_tasks
  end

  before do
    Rake::Task['meta_marketing:backfill_referral_attribution'].reenable
  end

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }

  # Message with referral
  let!(:message_with_referral) do
    create(:message,
           account: account,
           conversation: conversation,
           message_type: :incoming,
           content_attributes: { 'referral' => { 'source_url' => 'https://facebook.com?ad_id=123' } })
  end

  let!(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage,
      origin_conversation: conversation,
      status: :open,
      title: 'Test Opportunity',
      campaign_resolution_status: nil
    )
  end

  context 'when account has enabled attribution' do
    before do
      CampaignAttributionSetting.create!(account: account, enabled: true)
    end

    it 'processes the attribution and enqueues a resolution job' do
      Rake::Task['meta_marketing:backfill_referral_attribution'].invoke

      opportunity.reload
      expect(opportunity.campaign_source_id).to eq('123')
      expect(opportunity.campaign_platform).to eq('facebook')
      expect(opportunity.campaign_resolution_status).to eq('pending')
      expect(enqueued_jobs.any? { |j| j[:job] == Custom::CampaignResolutionJob && j[:args] == [opportunity.id] }).to be(true)
    end
  end

  context 'when account has disabled attribution' do
    before do
      CampaignAttributionSetting.create!(account: account, enabled: false)
    end

    it 'skips the opportunity and does not enqueue a resolution job' do
      Rake::Task['meta_marketing:backfill_referral_attribution'].invoke

      opportunity.reload
      expect(opportunity.campaign_source_id).to be_nil
      expect(enqueued_jobs.none? { |j| j[:job] == Custom::CampaignResolutionJob }).to be(true)
    end
  end

  context 'when opportunity has no origin_conversation matching the referral message' do
    let!(:other_conversation) { create(:conversation, account: account, contact: contact) }
    let!(:unlinked_opportunity) do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        origin_conversation: other_conversation,
        status: :open,
        title: 'Unlinked Opportunity'
      )
    end

    before do
      CampaignAttributionSetting.create!(account: account, enabled: true)
    end

    it 'leaves the opportunity untouched' do
      Rake::Task['meta_marketing:backfill_referral_attribution'].invoke

      unlinked_opportunity.reload
      expect(unlinked_opportunity.campaign_source_id).to be_nil
    end
  end
end
