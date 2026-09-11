# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ValueEstimationService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Triage', position: 1) }
  let(:interest_attribute) do
    CustomAttributeDefinition.create!(
      account: account,
      attribute_key: 'interesse',
      attribute_display_name: 'Interesse',
      attribute_display_type: 'list',
      attribute_model: 'opportunity_attribute',
      attribute_values: %w[Implante Clareamento Outro]
    )
  end
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Sales Qualifier',
      enabled: true,
      interest_attribute_definition: interest_attribute,
      value_by_interest: { 'Implante' => 2500.0, 'Clareamento' => 400.0 }
    )
  end
  let(:service) { described_class.new(scout: scout) }

  describe '#sync!' do
    it 'updates opportunity value when interest option has a configured value in the table' do
      opportunity = Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        title: 'Lead Implante',
        custom_attributes: { 'interesse' => 'Implante' }
      )

      service.sync!(opportunity)
      expect(opportunity.value).to eq(2500.0)
    end

    it 'leaves existing opportunity value untouched when option is unmapped in the table' do
      opportunity = Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        title: 'Lead Outro',
        value: 1200.0,
        custom_attributes: { 'interesse' => 'Outro' }
      )

      service.sync!(opportunity)
      expect(opportunity.value).to eq(1200.0)
    end

    it 'leaves value untouched when opportunity custom_attributes does not contain interest key' do
      opportunity = Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        title: 'Lead Sem Interesse',
        value: 800.0,
        custom_attributes: { 'budget' => 1000 }
      )

      service.sync!(opportunity)
      expect(opportunity.value).to eq(800.0)
    end

    it 'leaves value untouched when scout has no interest_attribute_definition' do
      scout.update!(interest_attribute_definition: nil)
      opportunity = Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        title: 'Lead Implante',
        value: 500.0,
        custom_attributes: { 'interesse' => 'Implante' }
      )

      service.sync!(opportunity)
      expect(opportunity.value).to eq(500.0)
    end

    it 'leaves value untouched when scout has empty value_by_interest' do
      scout.update!(value_by_interest: {})
      opportunity = Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        title: 'Lead Implante',
        value: 500.0,
        custom_attributes: { 'interesse' => 'Implante' }
      )

      service.sync!(opportunity)
      expect(opportunity.value).to eq(500.0)
    end

    it 'does not retroactively change existing opportunity value when value table is edited later (FR-009)' do
      opportunity = Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        title: 'Lead Antigo',
        value: 2500.0,
        custom_attributes: { 'interesse' => 'Implante' }
      )

      scout.update!(value_by_interest: { 'Implante' => 3500.0, 'Clareamento' => 500.0 })

      expect(opportunity.reload.value).to eq(2500.0)
    end

    it 'handles nil opportunity safely without raising' do
      expect { service.sync!(nil) }.not_to raise_error
    end
  end
end
