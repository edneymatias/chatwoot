# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::UnsatisfiedItems do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:scout) { Scout.create!(account: account, name: 'Test Scout') }
  let(:contact) { create(:contact, account: account, name: 'Carlos Silva', phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:lead_stage) { PipelineStage.create!(account: account, name: 'Lead', position: 0) }

  let(:cad_orcamento) do
    CustomAttributeDefinition.create!(
      account: account,
      attribute_display_name: 'Orçamento',
      attribute_key: 'orcamento',
      attribute_model: :opportunity_attribute,
      attribute_display_type: :text
    )
  end

  before do
    account.enable_features!('scout', 'scout_v2', 'opportunities')
    scout.sync_required_attribute_ids!([cad_orcamento.id])
  end

  describe '.call' do
    context 'when no procedure is in effect (playbook is nil)' do
      it 'returns a record with procedure: nil and all lists empty' do
        ctx = Custom::ScoutV2::RoutingSnapshot.new
        record = described_class.call(playbook: nil, conversation: conversation, scout: scout, ctx: ctx)

        expect(record).to eq(
          procedure: nil,
          pending_fields: [],
          unmet_requires: [],
          unmet_needs: []
        )
      end
    end

    context 'with an in-spec procedure' do
      let(:playbook) do
        Custom::ScoutV2::Playbook.new(
          name: 'agendamento_mock',
          title: 'Agendamento Mock',
          priority: 20,
          trigger: 't',
          requires: %w[scheduling customer_registry],
          needs: %w[politica_reagendamento],
          when_state: []
        )
      end

      it 'returns the record with procedure, fresh pending_fields, unmet_requires, and unmet_needs' do
        opportunity = Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: lead_stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal',
          status: :open,
          custom_attributes: {}
        )

        ctx = Custom::ScoutV2::RoutingSnapshot.new(
          conversation: conversation,
          contact: contact,
          scout: scout,
          opportunity: opportunity,
          satisfied_capabilities: ['customer_registry'],
          satisfied_business_facts: []
        )

        record = described_class.call(playbook: playbook, conversation: conversation, scout: scout, ctx: ctx)

        expect(record[:procedure]).to eq('agendamento_mock')
        expect(record[:pending_fields]).to eq(['orcamento'])
        expect(record[:unmet_requires]).to eq(['scheduling'])
        expect(record[:unmet_needs]).to eq(['politica_reagendamento'])
      end

      it 'recomputes pending_fields freshly when active opportunity was updated mid-turn' do
        opportunity = Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: lead_stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal',
          status: :open,
          custom_attributes: {}
        )

        ctx = Custom::ScoutV2::RoutingSnapshot.new(
          conversation: conversation,
          contact: contact,
          scout: scout,
          opportunity: opportunity,
          pending_fields: ['orcamento'],
          satisfied_capabilities: [],
          satisfied_business_facts: []
        )

        # Opportunity gets updated during the turn
        opportunity.update!(custom_attributes: { 'orcamento' => '5000' })

        record = described_class.call(playbook: playbook, conversation: conversation, scout: scout, ctx: ctx)
        expect(record[:pending_fields]).to eq([])
      end
    end

    context 'with the shipped agendamento playbook' do
      let(:shipped_catalog) { Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('custom/playbooks')) }
      let(:agendamento) { shipped_catalog['agendamento'] }

      it 'returns empty unmet lists when all capabilities and business facts are satisfied' do
        expect(agendamento).to be_present

        opportunity = Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: lead_stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal',
          status: :open,
          custom_attributes: { 'orcamento' => '5000' }
        )

        ctx = Custom::ScoutV2::RoutingSnapshot.new(
          conversation: conversation,
          contact: contact,
          scout: scout,
          opportunity: opportunity,
          satisfied_capabilities: %w[scheduling customer_registry],
          satisfied_business_facts: []
        )

        record = described_class.call(playbook: agendamento, conversation: conversation, scout: scout, ctx: ctx)

        expect(record[:procedure]).to eq('agendamento')
        expect(record[:pending_fields]).to eq([])
        expect(record[:unmet_requires]).to eq([])
        expect(record[:unmet_needs]).to eq([])
      end
    end
  end
end
