# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::RoutingSnapshot::Builder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  let(:default_stage) { PipelineStage.create!(account: account, name: 'Default', position: 1) }

  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      default_pipeline_stage_id: default_stage.id,
      enabled: true
    )
  end

  let!(:scout_inbox) { ScoutInbox.create!(scout: scout, inbox: inbox) }

  let(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: default_stage,
      origin_conversation: conversation,
      active_conversation: conversation,
      title: 'Test Deal',
      custom_attributes: {}
    )
  end

  let(:playbook_a) do
    Custom::ScoutV2::Playbook.new(
      name: 'playbook_a',
      title: 'Playbook A',
      priority: 10,
      trigger: 'trigger_a',
      file_path: 'playbook_a.md'
    )
  end

  let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([playbook_a]) }

  describe '.call' do
    it 'assembles snapshot with linked contact, inbox, scout, and active opportunity' do
      opportunity # ensure opportunity exists
      snapshot = described_class.call(conversation: conversation, catalog: catalog)

      expect(snapshot.conversation).to eq(conversation)
      expect(snapshot.contact).to eq(contact)
      expect(snapshot.inbox).to eq(inbox)
      expect(snapshot.scout).to eq(scout)
      expect(snapshot.opportunity).to eq(opportunity)
    end

    describe 'opportunity stage role derivation' do
      it 'derives :initial when stage matches scout default_pipeline_stage_id' do
        opportunity.update!(pipeline_stage: default_stage)
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.opportunity_stage_role).to eq(:initial)
      end

      it 'derives :qualified when stage matches scout qualified_stage_id' do
        qualified_stage = PipelineStage.create!(account: account, name: 'Qualified', position: 2)
        scout.update!(qualified_stage_id: qualified_stage.id)
        opportunity.update!(pipeline_stage: qualified_stage)
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.opportunity_stage_role).to eq(:qualified)
      end

      it 'derives :unqualified when stage matches scout unqualified_stage_id' do
        unqualified_stage = PipelineStage.create!(account: account, name: 'Unqualified', position: 3)
        scout.update!(unqualified_stage_id: unqualified_stage.id)
        opportunity.update!(pipeline_stage: unqualified_stage)
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.opportunity_stage_role).to eq(:unqualified)
      end

      it 'derives :none when stage matches none of the three scout stages' do
        other_stage = PipelineStage.create!(account: account, name: 'Other', position: 4)
        opportunity.update!(pipeline_stage: other_stage)
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.opportunity_stage_role).to eq(:none)
      end

      it 'derives :none when opportunity is absent' do
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.opportunity_stage_role).to eq(:none)
      end

      it 'derives :none when scout is absent' do
        scout_inbox.destroy!
        opportunity # exists
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.opportunity_stage_role).to eq(:none)
      end
    end

    describe 'pending_fields derivation' do
      let(:cad_email) do
        create(:custom_attribute_definition, account: account, attribute_key: 'lead_email', attribute_model: 'contact_attribute')
      end
      let(:cad_phone) do
        create(:custom_attribute_definition, account: account, attribute_key: 'lead_phone', attribute_model: 'opportunity_attribute')
      end
      let(:cad_budget) do
        create(:custom_attribute_definition, account: account, attribute_key: 'deal_budget', attribute_model: 'opportunity_attribute')
      end

      before do
        ScoutRequiredField.create!(account: account, scout: scout, custom_attribute_definition: cad_email)
        ScoutRequiredField.create!(account: account, scout: scout, custom_attribute_definition: cad_phone)
        PipelineStageRequiredField.create!(account: account, pipeline_stage: default_stage, custom_attribute_definition: cad_phone)
        PipelineStageRequiredField.create!(account: account, pipeline_stage: default_stage, custom_attribute_definition: cad_budget)
      end

      it 'returns scout qualification requirement keys when there is no opportunity' do
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.pending_fields).to match_array(%w[lead_email lead_phone])
      end

      it 'unions and deduplicates scout and stage required fields blank in custom_attributes' do
        opportunity.update!(custom_attributes: { 'lead_email' => 'test@example.com' })
        snapshot = described_class.call(conversation: conversation, catalog: catalog)

        expect(snapshot.pending_fields).to match_array(%w[lead_phone deal_budget])
        expect(snapshot.pending_fields).to be_frozen
      end

      it 'returns empty array when all required fields are satisfied' do
        opportunity.update!(
          custom_attributes: {
            'lead_email' => 'test@example.com',
            'lead_phone' => '123456789',
            'deal_budget' => '1000'
          }
        )
        snapshot = described_class.call(conversation: conversation, catalog: catalog)

        expect(snapshot.pending_fields).to eq([])
      end
    end

    describe 'active_playbook resolution' do
      it 'resolves active playbook from persisted ScoutConversationState' do
        ScoutConversationState.create!(
          account: account,
          conversation: conversation,
          active_playbook: 'playbook_a'
        )

        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.active_playbook).to eq(playbook_a)
      end

      it 'resolves to nil when persisted state has no active_playbook' do
        ScoutConversationState.create!(
          account: account,
          conversation: conversation,
          active_playbook: nil
        )

        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.active_playbook).to be_nil
      end

      it 'resolves to nil when active_playbook name is not in catalog' do
        ScoutConversationState.create!(
          account: account,
          conversation: conversation,
          active_playbook: 'unknown_playbook'
        )

        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.active_playbook).to be_nil
      end

      it 'resolves to nil when conversation has no persisted state row yet' do
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.active_playbook).to be_nil
      end
    end

    describe 'turn_transition_count' do
      it 'defaults transitions to 0 when omitted' do
        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.transitions).to eq(0)
      end

      it 'passes through provided turn_transition_count' do
        snapshot = described_class.call(conversation: conversation, catalog: catalog, turn_transition_count: 2)
        expect(snapshot.transitions).to eq(2)
      end
    end

    describe 'missing associations and defaults' do
      let(:bare_conversation) { create(:conversation, account: account) }

      it 'links the conversation and leaves associations nil when missing' do
        snapshot = described_class.call(conversation: bare_conversation, catalog: catalog)

        expect(snapshot.conversation).to eq(bare_conversation)
        expect(snapshot.scout).to be_nil
        expect(snapshot.opportunity).to be_nil
      end

      it 'returns default routing fields when missing associations' do
        snapshot = described_class.call(conversation: bare_conversation, catalog: catalog)

        expect(snapshot.opportunity_stage_role).to eq(:none)
        expect(snapshot.pending_fields).to eq([])
        expect(snapshot.active_playbook).to be_nil
        expect(snapshot.transitions).to eq(0)
        expect(snapshot.satisfied_capabilities).to eq([])
        expect(snapshot.completed_playbooks).to eq([])
        expect(snapshot.satisfied_business_facts).to eq([])
      end

      it 'reads completed_playbooks from the state row' do
        ScoutConversationState.create!(
          account: account,
          conversation: conversation,
          completed_playbooks: %w[identificacao qualificacao]
        )

        snapshot = described_class.call(conversation: conversation, catalog: catalog)
        expect(snapshot.completed_playbooks).to eq(%w[identificacao qualificacao])
      end

      describe 'satisfied_capabilities resolution' do
        before do
          account.enable_features!('erp_integration')
          stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
            .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
        end

        it 'resolves all capabilities when hook has all identifiers' do
          create(
            :integrations_hook,
            account: account,
            app_id: 'younus',
            status: :enabled,
            settings: {
              'token' => 'tok',
              'id_empresa' => '648',
              'id_usuario' => '172793',
              'id_convenio' => '1',
              'nr_convenio' => '12345',
              'id_origem_pessoa' => '11',
              'id_agenda' => '3',
              'id_servico' => '1'
            }
          )

          snapshot = described_class.call(conversation: conversation, catalog: catalog)
          expect(snapshot.satisfied_capabilities).to eq(%w[scheduling customer_registry])
        end

        it 'resolves customer_registry only when hook lacks id_agenda' do
          create(
            :integrations_hook,
            account: account,
            app_id: 'younus',
            status: :enabled,
            settings: {
              'token' => 'tok',
              'id_empresa' => '648',
              'id_usuario' => '172793',
              'id_convenio' => '1',
              'nr_convenio' => '12345',
              'id_origem_pessoa' => '11',
              'id_servico' => '1'
            }
          )

          snapshot = described_class.call(conversation: conversation, catalog: catalog)
          expect(snapshot.satisfied_capabilities).to eq(%w[customer_registry])
        end

        it 'returns empty array when account has no hook' do
          snapshot = described_class.call(conversation: conversation, catalog: catalog)
          expect(snapshot.satisfied_capabilities).to eq([])
        end
      end
    end
  end
end
