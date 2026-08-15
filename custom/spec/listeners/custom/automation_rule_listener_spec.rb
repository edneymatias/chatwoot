require 'rails_helper'

RSpec.describe AutomationRuleListener do
  let!(:account) { create(:account) }
  let!(:stage1) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let!(:stage2) { PipelineStage.create!(account: account, name: 'Won Stage', position: 2) }
  let!(:contact) { create(:contact, account: account, name: 'Charlie', email: 'charlie@example.com') }
  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage1,
      status: :open,
      title: 'Deal Charlie'
    )
  end

  describe 'event processing' do
    let(:listener) { described_class.instance }

    context 'when opportunity_won event is received' do
      let!(:rule) do
        create(:automation_rule, account: account, event_name: 'opportunity_won',
                                 conditions: [],
                                 actions: [
                                   { 'action_name' => 'update_contact_custom_attribute', 'action_params' => [{ 'attribute_key' => 'won_customer', 'attribute_value' => 'yes' }] }
                                 ])
      end

      it 'processes matching automation rules and executes actions' do
        event = Events::Base.new('opportunity_won', Time.zone.now, { opportunity: opportunity, changed_attributes: { 'status' => %w[open won] } })
        listener.opportunity_won(event)

        contact.reload
        expect(contact.custom_attributes['won_customer']).to eq('yes')
      end

      it 'ignores event if performed by an automation rule (loop prevention)' do
        event = Events::Base.new('opportunity_won', Time.zone.now, { opportunity: opportunity, performed_by: rule })
        listener.opportunity_won(event)

        contact.reload
        expect(contact.custom_attributes&.dig('won_customer')).to be_nil
      end
    end

    context 'when opportunity_stage_changed event is received' do
      let!(:rule) do
        create(:automation_rule, account: account, event_name: 'opportunity_stage_changed',
                                 conditions: [
                                   { 'attribute_key' => 'from_pipeline_stage_id', 'filter_operator' => 'equal_to', 'values' => [stage1.id.to_s], 'query_operator' => 'and' }
                                 ],
                                 actions: [
                                   { 'action_name' => 'update_opportunity_value', 'action_params' => [7777] }
                                 ])
      end

      it 'matches from_pipeline_stage_id and executes action' do
        event = Events::Base.new('opportunity_stage_changed', Time.zone.now, {
                                   opportunity: opportunity,
                                   from_pipeline_stage_id: stage1.id,
                                   changed_attributes: { 'pipeline_stage_id' => [stage1.id, stage2.id] }
                                 })
        listener.opportunity_stage_changed(event)

        opportunity.reload
        expect(opportunity.value).to eq(7777)
      end
    end
  end
end
