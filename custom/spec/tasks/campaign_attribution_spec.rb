require 'rails_helper'

RSpec.describe 'meta_marketing rake tasks', type: :task do
  include ActiveJob::TestHelper

  before do
    Rails.application.load_tasks
  end

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }

  describe 'meta_marketing:backfill_referral_attribution' do
    before do
      Rake::Task['meta_marketing:backfill_referral_attribution'].reenable
    end

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
        create(:message,
               account: account,
               conversation: conversation,
               message_type: :incoming,
               content_attributes: { 'referral' => { 'source_url' => 'https://facebook.com?ad_id=123' } })
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
        create(:message,
               account: account,
               conversation: conversation,
               message_type: :incoming,
               content_attributes: { 'referral' => { 'source_url' => 'https://facebook.com?ad_id=123' } })
        CampaignAttributionSetting.create!(account: account, enabled: false)
      end

      it 'skips the opportunity and does not enqueue a resolution job' do
        Rake::Task['meta_marketing:backfill_referral_attribution'].invoke

        opportunity.reload
        expect(opportunity.campaign_source_id).to be_nil
        expect(enqueued_jobs.none? { |j| j[:job] == Custom::CampaignResolutionJob }).to be(true)
      end
    end

    context 'when referral is an organic post' do
      before do
        create(:message,
               account: account,
               conversation: conversation,
               message_type: :incoming,
               content_attributes: {
                 'referral' => {
                   'source_type' => 'post',
                   'source_id' => '17892348912',
                   'source_url' => 'https://instagram.com/p/Cxyz123',
                   'headline' => 'Organic Headline',
                   'body' => 'Organic Body',
                   'thumbnail_url' => 'https://example.com/thumb.jpg'
                 }
               })
        CampaignAttributionSetting.create!(account: account, enabled: true)
      end

      it 'backfills organic post metadata and sets organic_post status' do
        Rake::Task['meta_marketing:backfill_referral_attribution'].invoke

        opportunity.reload
        expect(opportunity.campaign_platform).to eq('instagram')
        expect(opportunity.campaign_headline).to eq('Organic Headline')
        expect(opportunity.campaign_body).to eq('Organic Body')
        expect(opportunity.campaign_resolution_status).to eq('organic_post')
      end
    end
  end

  describe 'meta_marketing:backfill_missing_previews' do
    before do
      Rake::Task['meta_marketing:backfill_missing_previews'].reenable
      CampaignAttributionSetting.create!(account: account, enabled: true, provider_config: { 'access_token' => 'token_123' })
    end

    it 'enqueues resolution for resolved ads lacking thumbnail_url' do
      resolved_op = Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        status: :open,
        title: 'Resolved Op',
        campaign_source_id: '999',
        campaign_resolution_status: 'resolved',
        campaign_thumbnail_url: nil
      )

      expect do
        Rake::Task['meta_marketing:backfill_missing_previews'].invoke
      end.to have_enqueued_job(Custom::CampaignResolutionJob).with(resolved_op.id, force: true).at_least(:once)
    end
  end
end
