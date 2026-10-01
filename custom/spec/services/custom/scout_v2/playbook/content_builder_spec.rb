# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Playbook::ContentBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:scout) { Scout.create!(account: account, name: 'Test Scout') }
  let(:contact) { create(:contact, account: account, name: 'lindo-peixe-123', phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

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
    ScoutInbox.create!(scout: scout, inbox: inbox)
    scout.sync_required_attribute_ids!([cad_orcamento.id])
  end

  describe '.call' do
    context 'when playbook when_state includes in_qualification' do
      let(:playbook) do
        Custom::ScoutV2::Playbook.new(
          name: 'qualificacao',
          title: 'Qualificação',
          priority: 10,
          trigger: 'trigger',
          when_state: [['in_qualification', nil]],
          body: 'Instruções de qualificação.'
        )
      end

      it 'appends scout qualification requirement keys when there is no opportunity' do
        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to include('Instruções de qualificação.')
        expect(rendered).to include('Campos pendentes para esta oportunidade:')
        expect(rendered).to include('- Orçamento (chave: orcamento)')
      end

      it 'appends opportunity pending fields when opportunity exists' do
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: PipelineStage.create!(account: account, name: 'Stage 1', position: 0),
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal',
          custom_attributes: {}
        )

        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to include('Instruções de qualificação.')
        expect(rendered).to include('Campos pendentes para esta oportunidade:')
        expect(rendered).to include('- Orçamento (chave: orcamento)')
      end
    end

    context 'when playbook when_state includes pending_required_fields' do
      let(:playbook) do
        Custom::ScoutV2::Playbook.new(
          name: 'qualificacao_legada',
          title: 'Qualificação Legada',
          priority: 10,
          trigger: 'trigger',
          when_state: [['pending_required_fields', nil]],
          body: 'Instruções legadas.'
        )
      end

      it 'appends pending fields block' do
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: PipelineStage.create!(account: account, name: 'Stage 2', position: 0),
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal',
          custom_attributes: {}
        )

        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to include('Instruções legadas.')
        expect(rendered).to include('Campos pendentes para esta oportunidade:')
        expect(rendered).to include('- Orçamento (chave: orcamento)')
      end
    end

    context 'when playbook when_state includes contact_identity_incomplete' do
      let(:playbook) do
        Custom::ScoutV2::Playbook.new(
          name: 'identificacao',
          title: 'Identificação',
          priority: 30,
          trigger: 'trigger',
          when_state: [['contact_identity_incomplete', nil]],
          body: 'Instruções de identificação.'
        )
      end

      it 'appends missing-contact-data block naming both nome (with warning) and telefone when both are missing' do
        contact.update!(name: 'lindo-peixe-123', phone_number: nil)
        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to include('Instruções de identificação.')
        expect(rendered).to include('Dados de contato faltando:')
        expect(rendered).to include('- nome (o nome registrado é um identificador gerado pelo sistema — não o use para se dirigir ao cliente)')
        expect(rendered).to include('- telefone')
      end

      it 'appends missing-contact-data block naming only telefone when name is real' do
        contact.update!(name: 'Carlos Silva', phone_number: nil)
        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to include('Instruções de identificação.')
        expect(rendered).to include('Dados de contato faltando:')
        expect(rendered).not_to include('- nome')
        expect(rendered).to include('- telefone')
      end

      it 'appends missing-contact-data block naming only nome when phone is present but name is placeholder' do
        contact.update!(name: 'lindo-peixe-123', phone_number: '+5511999999999')
        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to include('Instruções de identificação.')
        expect(rendered).to include('Dados de contato faltando:')
        expect(rendered).to include('- nome (o nome registrado é um identificador gerado pelo sistema — não o use para se dirigir ao cliente)')
        expect(rendered).not_to include('- telefone')
      end

      it 'does not append missing-contact-data block when contact identity is fully complete' do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to eq('Instruções de identificação.')
      end
    end

    context 'when playbook is situational (empty when_state)' do
      let(:playbook) do
        Custom::ScoutV2::Playbook.new(
          name: 'pausa',
          title: 'Pausa',
          priority: 50,
          trigger: 'trigger',
          when_state: [],
          body: 'Instruções de pausa.'
        )
      end

      it 'returns body verbatim with no context blocks' do
        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to eq('Instruções de pausa.')
      end
    end

    context 'when procedure when_state does not read pending fields or contact gaps' do
      let(:playbook) do
        Custom::ScoutV2::Playbook.new(
          name: 'outro_procedimento',
          title: 'Outro',
          priority: 25,
          trigger: 'trigger',
          when_state: [['opportunity_open', nil]],
          body: 'Instruções gerais.'
        )
      end

      it 'returns body verbatim without context blocks' do
        ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: Custom::ScoutV2::Playbook::Catalog.new([playbook]))
        rendered = described_class.call(playbook: playbook, ctx: ctx)

        expect(rendered).to eq('Instruções gerais.')
      end

      context 'when playbook contains [[depends: ...]] markers (US3: degradation)' do
        let(:marked_playbook) do
          Custom::ScoutV2::Playbook.new(
            name: 'agendamento_teste',
            title: 'Agendamento Teste',
            priority: 20,
            trigger: 'trigger',
            requires: %w[scheduling customer_registry],
            needs: %w[politica_reagendamento],
            when_state: [],
            body: <<~BODY.strip
              1. Localize o cliente [[depends: customer_registry]]
              2. Ofereça horários [[depends: scheduling]]
              3. Regras de reagendamento [[depends: politica_reagendamento]]
            BODY
          )
        end

        it 'replaces markers with (PENDENTE — indisponível: ...) and appends PENDING_STEPS_NOTICE when unsatisfied' do
          ctx = Custom::ScoutV2::RoutingSnapshot.new(
            conversation: conversation,
            contact: contact,
            scout: scout,
            satisfied_capabilities: [],
            satisfied_business_facts: []
          )
          rendered = described_class.call(playbook: marked_playbook, ctx: ctx)

          expect(rendered).to include('1. Localize o cliente (PENDENTE — indisponível: customer_registry)')
          expect(rendered).to include('2. Ofereça horários (PENDENTE — indisponível: scheduling)')
          expect(rendered).to include('3. Regras de reagendamento (PENDENTE — indisponível: politica_reagendamento)')
          expect(rendered).to include(described_class::PENDING_STEPS_NOTICE)
        end

        it 'strips markers and omits PENDING_STEPS_NOTICE when all markers are satisfied' do
          ctx = Custom::ScoutV2::RoutingSnapshot.new(
            conversation: conversation,
            contact: contact,
            scout: scout,
            satisfied_capabilities: %w[scheduling customer_registry],
            satisfied_business_facts: %w[politica_reagendamento]
          )
          rendered = described_class.call(playbook: marked_playbook, ctx: ctx)

          expect(rendered).to include('1. Localize o cliente')
          expect(rendered).to include('2. Ofereça horários')
          expect(rendered).to include('3. Regras de reagendamento')
          expect(rendered).not_to include('PENDENTE')
          expect(rendered).not_to include(described_class::PENDING_STEPS_NOTICE)
        end

        it 'renders the unmodified shipped agendamento with empty vs full satisfaction lists' do
          shipped_catalog = Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('custom/playbooks'))
          agendamento = shipped_catalog['agendamento']
          expect(agendamento).to be_present

          # Empty satisfaction
          ctx_empty = Custom::ScoutV2::RoutingSnapshot.new(
            conversation: conversation,
            contact: contact,
            scout: scout,
            satisfied_capabilities: [],
            satisfied_business_facts: []
          )
          rendered_empty = described_class.call(playbook: agendamento, ctx: ctx_empty)
          expect(rendered_empty.scan(/\(PENDENTE — indisponível: customer_registry\)/).count).to eq(1)
          expect(rendered_empty.scan(/\(PENDENTE — indisponível: scheduling\)/).count).to eq(3)
          expect(rendered_empty.scan(/\(PENDENTE — indisponível: politica_reagendamento\)/).count).to eq(0)
          expect(rendered_empty).to include(described_class::PENDING_STEPS_NOTICE)

          # Full satisfaction
          ctx_full = Custom::ScoutV2::RoutingSnapshot.new(
            conversation: conversation,
            contact: contact,
            scout: scout,
            satisfied_capabilities: %w[scheduling customer_registry],
            satisfied_business_facts: []
          )
          rendered_full = described_class.call(playbook: agendamento, ctx: ctx_full)
          expect(rendered_full).not_to include('PENDENTE')
          expect(rendered_full).not_to include(described_class::PENDING_STEPS_NOTICE)
        end
      end

      context 'when playbook requires customer_registry (FR-020)' do
        let(:playbook_with_req) do
          Custom::ScoutV2::Playbook.new(
            name: 'agendamento_test',
            title: 'Agendamento Test',
            priority: 10,
            trigger: 'trigger',
            when_state: [],
            requires: %w[customer_registry scheduling],
            body: 'Corpo agendamento.'
          )
        end

        it 'appends PHONE_MISSING_NOTICE when contact phone is blank' do
          contact.update!(phone_number: nil)
          ctx = Custom::ScoutV2::RoutingSnapshot.new(
            conversation: conversation,
            contact: contact,
            scout: scout,
            satisfied_capabilities: %w[scheduling customer_registry],
            satisfied_business_facts: []
          )
          rendered = described_class.call(playbook: playbook_with_req, ctx: ctx)
          expect(rendered).to include(
            'O contato não tem telefone registrado. Não chame ferramentas customer_registry_*, ' \
            'não peça o telefone ao cliente e chame exit_handoff neste mesmo turno informando que o telefone está ausente.'
          )
        end

        it 'does not append PHONE_MISSING_NOTICE when contact has a phone number' do
          contact.update!(phone_number: '+5511999990648')
          ctx = Custom::ScoutV2::RoutingSnapshot.new(
            conversation: conversation,
            contact: contact,
            scout: scout,
            satisfied_capabilities: %w[scheduling customer_registry],
            satisfied_business_facts: []
          )
          rendered = described_class.call(playbook: playbook_with_req, ctx: ctx)
          expect(rendered).not_to include('O contato não tem telefone registrado')
        end
      end
    end
  end
end
