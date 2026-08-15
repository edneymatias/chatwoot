require 'rails_helper'

RSpec.describe Custom::AutomationRules::OpportunityActionService do
  let!(:account) { create(:account) }
  let!(:stage1) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let!(:stage2) { PipelineStage.create!(account: account, name: 'Proposal', position: 2) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:contact) { create(:contact, account: account, name: 'Bob', email: 'bob@example.com') }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage1,
      origin_conversation: conversation,
      status: :open,
      title: 'Deal Bob',
      value: 1000
    )
  end

  describe '#perform' do
    context 'with opportunity actions' do
      let(:rule) do
        create(:automation_rule, account: account, event_name: 'opportunity_created',
                                 actions: [
                                   { 'action_name' => 'update_opportunity_stage', 'action_params' => [stage2.id] },
                                   { 'action_name' => 'update_opportunity_assignee', 'action_params' => [agent.id] },
                                   { 'action_name' => 'update_opportunity_value', 'action_params' => [2500] },
                                   { 'action_name' => 'update_opportunity_custom_attribute',
                                     'action_params' => [{ 'attribute_key' => 'plan', 'attribute_value' => 'pro' }] }
                                 ])
      end

      it 'updates stage, assignee, value and custom attributes on the opportunity' do
        service = described_class.new(rule, account, opportunity)
        service.perform

        opportunity.reload
        expect(opportunity.pipeline_stage_id).to eq(stage2.id)
        expect(opportunity.assignee_id).to eq(agent.id)
        expect(opportunity.value).to eq(2500)
        expect(opportunity.custom_attributes['plan']).to eq('pro')
      end

      it 'sets and resets Current.executed_by for loop prevention' do
        executed_by_inside = nil
        allow(opportunity).to receive(:update!).and_wrap_original do |m, *args|
          executed_by_inside = Current.executed_by
          m.call(*args)
        end

        service = described_class.new(rule, account, opportunity)
        service.perform

        expect(executed_by_inside).to eq(rule)
        expect(Current.executed_by).to be_nil
      end
    end

    context 'with contact and conversation actions' do
      let(:rule) do
        create(:automation_rule, account: account, event_name: 'opportunity_won',
                                 actions: [
                                   { 'action_name' => 'update_contact_custom_attribute',
                                     'action_params' => [{ 'attribute_key' => 'tier', 'attribute_value' => 'gold' }] },
                                   { 'action_name' => 'add_private_note', 'action_params' => ['Automated deal note'] },
                                   { 'action_name' => 'resolve_conversation', 'action_params' => [] }
                                 ])
      end

      it 'updates contact and conversation successfully' do
        service = described_class.new(rule, account, opportunity)
        expect { service.perform }.to change { conversation.messages.count }.by(1)

        contact.reload
        conversation.reload
        expect(contact.custom_attributes['tier']).to eq('gold')
        expect(conversation.status).to eq('resolved')
        expect(conversation.messages.last.content).to eq('Automated deal note')
        expect(conversation.messages.last.private).to be(true)
      end
    end

    context 'when opportunity has no linked conversation (graceful fallback)' do
      let!(:standalone_opp) do
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage1,
          status: :open,
          title: 'Standalone Deal'
        )
      end

      let(:rule) do
        create(:automation_rule, account: account, event_name: 'opportunity_created',
                                 actions: [
                                   { 'action_name' => 'update_opportunity_stage', 'action_params' => [stage2.id] },
                                   { 'action_name' => 'update_contact_custom_attribute',
                                     'action_params' => [{ 'attribute_key' => 'tier', 'attribute_value' => 'silver' }] },
                                   { 'action_name' => 'add_private_note', 'action_params' => ['Should be safely skipped'] },
                                   { 'action_name' => 'resolve_conversation', 'action_params' => [] }
                                 ])
      end

      it 'executes opportunity and contact actions while safely skipping conversation actions' do
        service = described_class.new(rule, account, standalone_opp)
        expect { service.perform }.not_to raise_error

        standalone_opp.reload
        contact.reload
        expect(standalone_opp.pipeline_stage_id).to eq(stage2.id)
        expect(contact.custom_attributes['tier']).to eq('silver')
      end
    end
  end
end
