# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::TurnScope do
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

  let(:playbook) do
    Custom::ScoutV2::Playbook.new(
      name: 'identificacao',
      title: 'Identificação',
      priority: 30,
      trigger: 'trigger',
      when_state: [['contact_identity_incomplete', nil]],
      body: 'Identifique o contato.'
    )
  end
  let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([playbook]) }

  before do
    account.enable_features!('scout', 'scout_v2', 'opportunities')
    ScoutInbox.create!(scout: scout, inbox: inbox)
    ScoutAccountConfig.create!(account_id: account.id, api_key: 'test-key', model_name: 'gemini-2.0-flash')
    scout.sync_required_attribute_ids!([cad_orcamento.id])
  end

  describe '#content_for' do
    let(:chat) { scout.llm_chat }
    let(:tool_wrapper) { ->(tool) { tool } }
    let(:turn_scope) do
      described_class.new(
        chat: chat,
        catalog: catalog,
        baseline_instructions: 'Baseline',
        tool_wrapper: tool_wrapper
      )
    end

    it 'fails loudly when content_for is called before setup_initial_tools! stores a snapshot' do
      expect { turn_scope.content_for(playbook) }.to raise_error(RuntimeError, /snapshot/i)
    end

    it 'returns the ContentBuilder rendering for the stored snapshot after setup_initial_tools!' do
      ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: catalog)
      decision = Custom::ScoutV2::Router::Decision.new(playbook: playbook, confidence: 1.0)

      turn_scope.setup_initial_tools!(
        decision: decision,
        ctx: ctx,
        scout: scout,
        conversation: conversation,
        openable: []
      )

      rendered = turn_scope.content_for(playbook)
      expect(rendered).to include('Identifique o contato.')
      expect(rendered).to include('Dados de contato faltando:')
      expect(rendered).to include('- nome (o nome registrado é um identificador gerado pelo sistema — não o use para se dirigir ao cliente)')
      expect(rendered).to include('- telefone')
    end
  end

  describe '#actions_for (US3: exit withholding)' do
    let(:chat) { scout.llm_chat }
    let(:tool_wrapper) { ->(tool) { tool } }
    let(:turn_scope) do
      described_class.new(
        chat: chat,
        catalog: catalog,
        baseline_instructions: 'Baseline',
        tool_wrapper: tool_wrapper
      )
    end

    let(:declared_exit) do
      Custom::ScoutV2::Playbook::ExitDeclaration.new(
        name: 'sucesso',
        kind: 'terminal',
        fields: {}
      )
    end

    let(:playbook_with_reqs) do
      Custom::ScoutV2::Playbook.new(
        name: 'teste_reqs',
        title: 'Teste Reqs',
        priority: 20,
        trigger: 't',
        requires: ['scheduling'],
        needs: ['politica_reagendamento'],
        tools: ['manage_opportunity'],
        exits: { 'sucesso' => declared_exit }
      )
    end

    it 'omits declared exits when any requires is unsatisfied, but keeps tools' do
      ctx = Custom::ScoutV2::RoutingSnapshot.new(satisfied_capabilities: [])
      turn_scope.setup_initial_tools!(
        decision: Custom::ScoutV2::Router::Decision.new(playbook: playbook_with_reqs, confidence: 1.0),
        ctx: ctx,
        scout: scout,
        conversation: conversation,
        openable: []
      )

      actions = turn_scope.actions_for(playbook_with_reqs, scout: scout, conversation: conversation)
      action_names = actions.map(&:name)
      expect(action_names).to include('manage_opportunity')
      expect(action_names).not_to include('exit_sucesso')
    end

    it 'offers declared exits when needs is unsatisfied but requires is satisfied' do
      ctx = Custom::ScoutV2::RoutingSnapshot.new(
        satisfied_capabilities: ['scheduling'],
        satisfied_business_facts: []
      )
      turn_scope.setup_initial_tools!(
        decision: Custom::ScoutV2::Router::Decision.new(playbook: playbook_with_reqs, confidence: 1.0),
        ctx: ctx,
        scout: scout,
        conversation: conversation,
        openable: []
      )

      actions = turn_scope.actions_for(playbook_with_reqs, scout: scout, conversation: conversation)
      action_names = actions.map(&:name)
      expect(action_names).to include('manage_opportunity', 'exit_sucesso')
    end

    it 'withholds agendamento declared exits with empty capabilities and offers them with satisfied capabilities' do
      shipped_catalog = Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('custom/playbooks'))
      agendamento = shipped_catalog['agendamento']
      expect(agendamento).to be_present

      # Empty satisfaction: withheld
      ctx_empty = Custom::ScoutV2::RoutingSnapshot.new(satisfied_capabilities: [])
      turn_scope.setup_initial_tools!(
        decision: Custom::ScoutV2::Router::Decision.new(playbook: agendamento, confidence: 1.0),
        ctx: ctx_empty,
        scout: scout,
        conversation: conversation,
        openable: []
      )
      empty_actions = turn_scope.actions_for(agendamento, scout: scout, conversation: conversation).map(&:name)
      expect(empty_actions).not_to include('exit_agendado', 'exit_sem_horario')

      # Satisfied capabilities: offered
      turn_scope_satisfied = described_class.new(
        chat: chat,
        catalog: shipped_catalog,
        baseline_instructions: 'Baseline',
        tool_wrapper: tool_wrapper
      )
      ctx_satisfied = Custom::ScoutV2::RoutingSnapshot.new(
        satisfied_capabilities: %w[scheduling customer_registry],
        satisfied_business_facts: []
      )
      turn_scope_satisfied.setup_initial_tools!(
        decision: Custom::ScoutV2::Router::Decision.new(playbook: agendamento, confidence: 1.0),
        ctx: ctx_satisfied,
        scout: scout,
        conversation: conversation,
        openable: []
      )
      satisfied_actions = turn_scope_satisfied.actions_for(agendamento, scout: scout, conversation: conversation).map(&:name)
      expect(satisfied_actions).to include('exit_agendado', 'exit_sem_horario')
    end

    it 'registers capability OperationTools when all requires are satisfied and omits them when unsatisfied (FR-018, FR-026)' do
      setup_younus_hook

      ctx_satisfied = Custom::ScoutV2::RoutingSnapshot.new(
        conversation: conversation,
        satisfied_capabilities: %w[scheduling customer_registry]
      )
      turn_scope.setup_initial_tools!(
        decision: Custom::ScoutV2::Router::Decision.new(playbook: playbook_with_reqs, confidence: 1.0),
        ctx: ctx_satisfied,
        scout: scout,
        conversation: conversation,
        openable: []
      )

      actions = turn_scope.actions_for(playbook_with_reqs, scout: scout, conversation: conversation)
      action_names = actions.map(&:name)
      expect(action_names).to include('scheduling_list_slots', 'scheduling_book')
      expect(action_names).not_to include('call_custom_api')

      ctx_unsatisfied = Custom::ScoutV2::RoutingSnapshot.new(
        conversation: conversation,
        satisfied_capabilities: []
      )
      turn_scope_unsatisfied = described_class.new(
        chat: chat,
        catalog: catalog,
        baseline_instructions: 'Baseline',
        tool_wrapper: tool_wrapper
      )
      turn_scope_unsatisfied.setup_initial_tools!(
        decision: Custom::ScoutV2::Router::Decision.new(playbook: playbook_with_reqs, confidence: 1.0),
        ctx: ctx_unsatisfied,
        scout: scout,
        conversation: conversation,
        openable: []
      )
      unsatisfied_actions = turn_scope_unsatisfied.actions_for(playbook_with_reqs, scout: scout, conversation: conversation).map(&:name)
      expect(unsatisfied_actions).not_to include('scheduling_list_slots', 'scheduling_book')
    end

    it 'does NOT register capability OperationTools or exit_agendado during an interruption takeover while agendamento is pinned (FR-018)' do
      setup_younus_hook
      shipped_catalog = Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('custom/playbooks'))
      agendamento = shipped_catalog['agendamento']
      openable = Custom::ScoutV2::Playbook::Catalog.new([shipped_catalog['pausa']])

      ScoutConversationState.create!(account: account, conversation: conversation, active_playbook: 'agendamento', activation_reason: 'state')
      ctx = Custom::ScoutV2::RoutingSnapshot.new(
        conversation: conversation,
        satisfied_capabilities: %w[scheduling customer_registry],
        satisfied_business_facts: []
      )

      turn_scope_pinned = build_pinned_turn_scope(shipped_catalog, agendamento, openable, ctx)
      open_tool = Custom::ScoutV2::Tools::OpenPlaybook.new(scout, conversation, openable: openable, scope: turn_scope_pinned)

      expect(chat.tools.keys).to include(
        :scheduling_list_slots, :scheduling_book, :customer_registry_find_by_phone, :customer_registry_create, :exit_agendado
      )

      open_tool.execute(name: 'pausa')

      expect(chat.tools.keys).to include(:search_knowledge_base, :open_playbook, :exit_handoff)
      expect(chat.tools.keys).not_to include(
        :scheduling_list_slots, :scheduling_book, :customer_registry_find_by_phone, :customer_registry_create, :exit_agendado, :exit_sem_horario
      )
    end

    def setup_younus_hook
      account.enable_features!('erp_integration')
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: {
               'token' => 'secret-token-123',
               'id_empresa' => '648',
               'id_usuario' => '172793',
               'id_convenio' => '1',
               'nr_convenio' => 'CARD-123',
               'id_origem_pessoa' => '11',
               'id_agenda' => '3',
               'id_servico' => '1'
             })
    end

    def build_pinned_turn_scope(shipped_catalog, agendamento, openable, ctx)
      scope = described_class.new(
        chat: chat,
        catalog: shipped_catalog,
        baseline_instructions: 'Baseline',
        tool_wrapper: tool_wrapper
      )
      scope.setup_initial_tools!(
        decision: Custom::ScoutV2::Router::Decision.new(playbook: agendamento, confidence: 1.0),
        ctx: ctx,
        scout: scout,
        conversation: conversation,
        openable: openable
      )
      scope
    end
  end
end
