require 'rails_helper'

RSpec.describe Custom::AutomationRules::ActionService do
  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }
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

  describe '.process_campaign_attribution' do
    let(:first_message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }

    context 'when referral data is missing' do
      it 'does not update opportunity or enqueue job' do
        first_message.update!(content_attributes: {})

        expect do
          described_class.process_campaign_attribution(opportunity, first_message)
        end.not_to have_enqueued_job(Custom::CampaignResolutionJob)

        opportunity.reload
        expect(opportunity.campaign_platform).to be_nil
        expect(opportunity.campaign_source_id).to be_nil
      end
    end

    context 'when referral data is present without ad_id' do
      before do
        first_message.update!(content_attributes: {
                                'referral' => { 'source_url' => 'https://facebook.com/something' }
                              })
      end

      it 'sets the platform but leaves source_id nil and resolution_status not_applicable' do
        expect do
          described_class.process_campaign_attribution(opportunity, first_message)
        end.not_to have_enqueued_job(Custom::CampaignResolutionJob)

        opportunity.reload
        expect(opportunity.campaign_platform).to eq('facebook')
        expect(opportunity.campaign_source_id).to be_nil
        expect(opportunity.campaign_resolution_status).to eq('not_applicable')
      end
    end

    context 'when referral data is present with ad_id' do
      before do
        first_message.update!(content_attributes: {
                                'referral' => { 'source_url' => 'https://instagram.com/p/something?ad_id=999' }
                              })
      end

      context 'and account attribution is disabled' do
        before do
          create(:campaign_attribution_setting, account: account, enabled: false)
        end

        it 'sets the attributes but does not enqueue a job' do
          expect do
            described_class.process_campaign_attribution(opportunity, first_message)
          end.not_to have_enqueued_job(Custom::CampaignResolutionJob)

          opportunity.reload
          expect(opportunity.campaign_platform).to eq('instagram')
          expect(opportunity.campaign_source_id).to eq('999')
          expect(opportunity.campaign_resolution_status).to eq('pending')
        end
      end

      context 'and account attribution is enabled' do
        before do
          create(:campaign_attribution_setting, account: account, enabled: true)
        end

        it 'sets the attributes and enqueues a job' do
          expect do
            described_class.process_campaign_attribution(opportunity, first_message)
          end.to have_enqueued_job(Custom::CampaignResolutionJob).with(opportunity.id)

          opportunity.reload
          expect(opportunity.campaign_platform).to eq('instagram')
          expect(opportunity.campaign_source_id).to eq('999')
          expect(opportunity.campaign_resolution_status).to eq('pending')
        end
      end
    end
  end
end
