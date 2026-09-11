require 'rails_helper'

RSpec.describe Custom::AutomationRules::ActionService do
  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }
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

      context 'when account attribution is disabled' do
        before do
          CampaignAttributionSetting.create!(account: account, enabled: false)
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

      context 'when account attribution is enabled' do
        before do
          CampaignAttributionSetting.create!(account: account, enabled: true)
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

    context 'when referral data is from an organic post' do
      before do
        first_message.update!(content_attributes: {
                                'referral' => {
                                  'source_type' => 'post',
                                  'source_id' => '17892348912',
                                  'source_url' => 'https://instagram.com/p/Cxyz123',
                                  'headline' => 'Organic Post Title',
                                  'body' => 'Organic Post Body Content',
                                  'thumbnail_url' => 'https://example.com/thumb.jpg'
                                }
                              })
        CampaignAttributionSetting.create!(account: account, enabled: true)
      end

      it 'sets organic_post status, extracts metadata, and does NOT enqueue CampaignResolutionJob' do
        expect do
          described_class.process_campaign_attribution(opportunity, first_message)
        end.not_to have_enqueued_job(Custom::CampaignResolutionJob)

        opportunity.reload
        expect(opportunity.campaign_platform).to eq('instagram')
        expect(opportunity.campaign_source_id).to eq('17892348912')
        expect(opportunity.campaign_headline).to eq('Organic Post Title')
        expect(opportunity.campaign_body).to eq('Organic Post Body Content')
        expect(opportunity.campaign_thumbnail_url).to eq('https://example.com/thumb.jpg')
        expect(opportunity.campaign_resolution_status).to eq('organic_post')
      end
    end
  end

  describe '#create_opportunity' do
    let(:rule) { create(:automation_rule, account: account) }
    let(:action_service) { AutomationRules::ActionService.new(rule, account, test_conversation) }

    context 'when contact has zero open deals' do
      let(:new_contact) { create(:contact, account: account) }
      let(:test_conversation) { create(:conversation, account: account, contact: new_contact) }

      it 'creates a new opportunity for the conversation without private note' do
        expect do
          action_service.send(:create_opportunity, [stage.id, nil])
        end.to change(Opportunity, :count).by(1)

        created_opp = Opportunity.where(contact_id: new_contact.id, status: :open).last
        expect(created_opp.origin_conversation_id).to eq(test_conversation.id)
        expect(created_opp.pipeline_stage_id).to eq(stage.id)
        expect(created_opp.title).to eq("Oportunidade ##{test_conversation.display_id}")
        expect(test_conversation.messages.where(private: true)).to be_empty
      end

      it 'assigns same assignee as conversation when requested' do
        agent = create(:user, account: account)
        test_conversation.update!(assignee: agent)

        action_service.send(:create_opportunity, [stage.id, 'same_as_conversation'])

        created_opp = Opportunity.where(contact_id: new_contact.id, status: :open).last
        expect(created_opp.assignee_id).to eq(agent.id)
      end
    end

    context 'when contact already has one or more open deals' do
      let(:test_conversation) { create(:conversation, account: account, contact: contact) }

      it 'does not create a duplicate deal or modify existing, and adds an ambiguity private note' do
        expect do
          action_service.send(:create_opportunity, [stage.id, nil])
        end.not_to change(Opportunity, :count)

        opportunity.reload
        expect(opportunity.title).to eq('Test Opportunity')

        private_note = test_conversation.messages.where(private: true).last
        expect(private_note).to be_present
        expect(private_note.content).to include('⚠️ [Continuidade de Oportunidade]')
        expect(private_note.content).to include('1 open opportunity candidate(s)')
      end
    end
  end
end
