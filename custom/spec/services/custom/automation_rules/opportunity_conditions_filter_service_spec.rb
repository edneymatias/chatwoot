require 'rails_helper'

RSpec.describe Custom::AutomationRules::OpportunityConditionsFilterService do
  let!(:account) { create(:account) }
  let!(:stage1) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let!(:stage2) { PipelineStage.create!(account: account, name: 'Proposal', position: 2) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:contact) { create(:contact, account: account, name: 'Alice', email: 'alice@example.com') }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage1,
      origin_conversation: conversation,
      status: :open,
      title: 'Deal 1',
      value: 5000,
      assignee: agent,
      custom_attributes: { 'tier' => 'enterprise', 'loss_reason' => 'Budget' }
    )
  end

  describe '#perform' do
    context 'with opportunity conditions' do
      it 'matches when stage and value conditions match' do
        rule = create(:automation_rule, account: account, event_name: 'opportunity_stage_changed',
                                        conditions: [
                                          { 'attribute_key' => 'pipeline_stage_id', 'filter_operator' => 'equal_to', 'values' => [stage1.id.to_s],
                                            'query_operator' => 'and' },
                                          { 'attribute_key' => 'value', 'filter_operator' => 'greater_than', 'values' => ['1000'],
                                            'query_operator' => 'and' }
                                        ])

        service = described_class.new(rule, opportunity)
        expect(service.perform).to be(true)
      end

      it 'matches from_pipeline_stage_id when passed in options' do
        rule = create(:automation_rule, account: account, event_name: 'opportunity_stage_changed',
                                        conditions: [
                                          { 'attribute_key' => 'from_pipeline_stage_id', 'filter_operator' => 'equal_to', 'values' => [stage1.id.to_s], 'query_operator' => 'and' }
                                        ])

        service = described_class.new(rule, opportunity, { from_pipeline_stage_id: stage1.id })
        expect(service.perform).to be(true)
      end

      it 'returns false when condition does not match' do
        rule = create(:automation_rule, account: account, event_name: 'opportunity_stage_changed',
                                        conditions: [
                                          { 'attribute_key' => 'value', 'filter_operator' => 'greater_than', 'values' => ['10000'], 'query_operator' => 'and' }
                                        ])

        service = described_class.new(rule, opportunity)
        expect(service.perform).to be(false)
      end
    end

    context 'with contact and conversation conditions' do
      it 'matches contact email and conversation inbox' do
        rule = create(:automation_rule, account: account, event_name: 'opportunity_created',
                                        conditions: [
                                          { 'attribute_key' => 'email', 'filter_operator' => 'equal_to', 'values' => ['alice@example.com'],
                                            'query_operator' => 'and' },
                                          { 'attribute_key' => 'inbox_id', 'filter_operator' => 'equal_to', 'values' => [conversation.inbox_id.to_s],
                                            'query_operator' => 'and' }
                                        ])

        service = described_class.new(rule, opportunity)
        expect(service.perform).to be(true)
      end

      it 'safely evaluates to false without crashing when conversation is nil' do
        standalone_opp = Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage1,
          status: :open,
          title: 'Standalone Deal'
        )

        rule = create(:automation_rule, account: account, event_name: 'opportunity_created',
                                        conditions: [
                                          { 'attribute_key' => 'inbox_id', 'filter_operator' => 'equal_to', 'values' => ['999'], 'query_operator' => 'and' }
                                        ])

        service = described_class.new(rule, standalone_opp)
        expect(service.perform).to be(false)
      end
    end
  end
end
