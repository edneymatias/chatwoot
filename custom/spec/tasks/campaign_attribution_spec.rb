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

  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      origin_conversation: conversation,
      status: :open,
      title: 'Test Opportunity',
      campaign_resolution_status: nil
    )
  end

  context 'when account has enabled attribution' do
    before do
      create(:campaign_attribution_setting, account: account, enabled: true)
    end

    it 'processes the attribution and enqueues a resolution job' do
      expect do
        Rake::Task['meta_marketing:backfill_referral_attribution'].invoke
      end.to have_enqueued_job(Custom::CampaignResolutionJob).with(opportunity.id)

      opportunity.reload
      expect(opportunity.campaign_source_id).to eq('123')
      expect(opportunity.campaign_platform).to eq('facebook')
      expect(opportunity.campaign_resolution_status).to eq('pending')
    end
  end

  context 'when account has disabled attribution' do
    before do
      create(:campaign_attribution_setting, account: account, enabled: false)
    end

    it 'processes attribution but does not enqueue a resolution job' do
      expect do
        Rake::Task['meta_marketing:backfill_referral_attribution'].invoke
      end.not_to have_enqueued_job(Custom::CampaignResolutionJob)

      opportunity.reload
      expect(opportunity.campaign_source_id).to eq('123')
      expect(opportunity.campaign_platform).to eq('facebook')
      expect(opportunity.campaign_resolution_status).to eq('pending')
    end
  end

  context 'when message does not have referral' do
    let!(:message_with_referral) do
      create(:message,
             account: account,
             conversation: conversation,
             message_type: :incoming,
             content_attributes: {})
    end

    it 'skips the opportunity' do
      Rake::Task['meta_marketing:backfill_referral_attribution'].invoke

      opportunity.reload
      expect(opportunity.campaign_source_id).to be_nil
    end
  end
end
