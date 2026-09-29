# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Playground First Cut Catalog (US1)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lead_stage) { PipelineStage.create!(account: account, name: 'Lead', position: 0) }
  let(:qualified_stage) { PipelineStage.create!(account: account, name: 'Qualificado', position: 1) }
  let(:unqualified_stage) { PipelineStage.create!(account: account, name: 'Desqualificado', position: 2) }

  let(:scout) do
    Scout.create!(
      account: account,
      name: 'V2 Shipped Scout',
      enabled: true,
      default_pipeline_stage: lead_stage,
      qualified_stage: qualified_stage,
      unqualified_stage: unqualified_stage
    )
  end
  let(:sandbox_conversation) { Custom::ScoutV2::PlaygroundConversation.for(scout) }
  let(:contact) { sandbox_conversation.contact }
  let(:provider_requests) { [] }

  let(:cad_orcamento) do
    CustomAttributeDefinition.create!(
      account: account,
      attribute_display_name: 'Orçamento',
      attribute_key: 'orcamento',
      attribute_model: :opportunity_attribute,
      attribute_display_type: :text
    )
  end

  let(:gemini_step) do
    lambda do |parts|
      {
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: { candidates: [{ content: { role: 'model', parts: parts } }] }.to_json
      }
    end
  end

  before do
    account.enable_features!('scout', 'scout_v2', 'opportunities')
    ScoutAccountConfig.create!(account_id: account.id, api_key: 'test-key', model_name: 'gemini-2.0-flash')
    scout.sync_required_attribute_ids!([cad_orcamento.id])
  end

  def post_message(text, history: [])
    provider_requests.clear
    post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
         params: { message: text, message_history: history },
         headers: agent.create_new_auth_token
  end

  def system_text
    provider_requests.first.dig('systemInstruction', 'parts', 0, 'text') ||
      provider_requests.first.dig('contents', 0, 'parts', 0, 'text')
  end

  describe 'US1-AS1 and US1-AS13: state pinning by contact identity' do
    it 'pins identificacao by state when name is placeholder' do
      contact.update!(name: 'lindo-peixe-123', phone_number: '+5511999999999')
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá, qual seu nome?' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('identificacao')
      expect(state.activation_reason).to eq('state')
    end

    it 'pins identificacao by state when phone is blank' do
      contact.update!(name: 'Carlos Silva', phone_number: nil)
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá Carlos, qual seu telefone?' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('identificacao')
      expect(state.activation_reason).to eq('state')
    end

    it 'pins qualificacao directly when contact identity is complete' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá Carlos, como posso ajudar?' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('qualificacao')
      expect(state.activation_reason).to eq('state')
    end
  end

  describe 'US1-AS2 and US1-AS8: offered actions in identificacao vs qualificacao' do
    it 'offers update_contact and exit_identificado, not manage_opportunity in identificacao' do
      contact.update!(name: 'lindo-peixe-123', phone_number: nil)
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Como prefere ser chamado?' }]))

      post_message('Olá')
      expect(response).to have_http_status(:ok)

      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).to include('update_contact', 'exit_identificado', 'exit_handoff')
      expect(tools).not_to include('manage_opportunity')
    end

    it 'offers manage_opportunity and exit_desqualificado, not update_contact in qualificacao' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Qual o seu orçamento?' }]))

      post_message('Olá')
      expect(response).to have_http_status(:ok)

      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).to include('manage_opportunity', 'exit_desqualificado', 'exit_handoff')
      expect(tools).not_to include('update_contact', 'exit_identificado')
    end
  end

  describe 'US1-AS3: system text of identificacao turn' do
    it 'contains all asserted key phrases, none of must not, and the contact gaps block', :aggregate_failures do
      contact.update!(name: 'lindo-peixe-123', phone_number: nil)
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Como se chama?' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      expect(system_text).to include('não use o nome registrado')
      expect(system_text).to include('uma única vez')
      expect(system_text).to include('primeiro o nome')
      expect(system_text).to include('nunca os dois na mesma mensagem')
      expect(system_text).to include('update_contact')
      expect(system_text).to include('sem esperar a resposta')
      expect(system_text).to include('exit_identificado')
      expect(system_text).not_to include('manage_opportunity')

      expect(system_text).to include('Dados de contato faltando:')
      expect(system_text).to include('- nome (o nome registrado é um identificador gerado pelo sistema — não o use para se dirigir ao cliente)')
      expect(system_text).to include('- telefone')
    end
  end

  describe 'US1-AS4 and US1-AS6: update_contact then exit_identificado transition and subsequent turns' do
    it 'records answers, transitions with qualificacao body, records completion, and does not re-pin', :aggregate_failures do
      contact.update!(name: 'lindo-peixe-123', phone_number: nil)

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([
                             { functionCall: { name: 'update_contact', args: { name: 'Carlos Silva' } } },
                             { functionCall: { name: 'exit_identificado', args: {} } }
                           ]),
          gemini_step.call([{ text: 'Obrigado Carlos! Qual o seu orçamento?' }])
        )

      post_message('Meu nome é Carlos Silva')
      expect(response).to have_http_status(:ok)
      expect(contact.reload.name).to eq('Carlos Silva')

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('qualificacao')
      expect(state.activation_reason).to eq('transition')
      expect(state.completed_playbooks).to eq(['identificacao'])

      # Check exit_identificado result
      tool_calls = response.parsed_body['tool_calls']
      exit_call = tool_calls.find { |c| c['tool_name'] == 'exit_identificado' }
      expect(exit_call['result']).to be_a(String)
      expect(exit_call['result']).to include('Campos pendentes para esta oportunidade:')
      expect(exit_call['result']).to include('- Orçamento (chave: orcamento)')

      # Next turn: phone still blank, but identificacao was completed -> keeps qualificacao pinned
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Entendido.' }]))

      post_message('Mais uma mensagem')
      expect(response).to have_http_status(:ok)
      state.reload
      expect(state.active_playbook).to eq('qualificacao')
      expect(state.completed_playbooks).to eq(['identificacao'])
    end
  end

  describe 'US1-AS5: exit_identificado with phone still blank succeeds' do
    it 'transitions to qualificacao without error when phone is not provided' do
      contact.update!(name: 'lindo-peixe-123', phone_number: nil)

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_identificado', args: {} } }]),
          gemini_step.call([{ text: 'Certo, vamos continuar.' }])
        )

      post_message('Não quero informar')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('qualificacao')
      expect(state.activation_reason).to eq('transition')
    end
  end

  describe 'US1-AS11: exit_desqualificado' do
    it 'moves opportunity to unqualified stage, records terminal exit and completed_playbooks' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      opp = Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: lead_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal',
        status: :open
      )

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_desqualificado', args: { motivo: 'Sem orçamento' } } }]),
          gemini_step.call([{ text: 'Compreendo, ficamos à disposição.' }])
        )

      post_message('Não tenho orçamento')
      expect(response).to have_http_status(:ok)

      expect(opp.reload.pipeline_stage_id).to eq(unqualified_stage.id)
      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to be_nil
      expect(state.last_exit).to eq('desqualificado')
      expect(state.completed_playbooks).to include('qualificacao')
    end
  end

  describe 'US1-AS15, AS16, AS17: qualificacao without opportunity' do
    before do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
    end

    it 'matches qualificacao by state, shows scout requirements, and contains asserted phrases', :aggregate_failures do
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá Carlos, como posso ajudar?' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('qualificacao')
      expect(state.activation_reason).to eq('state')

      expect(system_text).to include('Campos pendentes para esta oportunidade:')
      expect(system_text).to include('- Orçamento (chave: orcamento)')

      expect(system_text).to include('interesse comercial')
      expect(system_text).to include('pergunte apenas pelos campos pendentes')
      expect(system_text).to include('uma pergunta por mensagem')
      expect(system_text).to include('não invente perguntas')
      expect(system_text).to include('registre cada resposta imediatamente')
      expect(system_text).to include('não pergunte de novo')
      expect(system_text).to include('reconheça brevemente')
      expect(system_text).to include('fila de revisão humana')
      expect(system_text).to include('nunca retorne uma oportunidade que já atingiu o estágio qualificado')
      expect(system_text).to include('exit_desqualificado')
      expect(system_text).to include('exit_handoff')

      expect(system_text).not_to include('update_contact')
      expect(system_text).not_to include('move_opportunity_stage')
      expect(system_text).not_to include('handover_to_human')
      expect(system_text).not_to include('aguarde a próxima mensagem')
    end

    it 'creates opportunity when manage_opportunity action is create' do
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'manage_opportunity', args: { action: 'create', title: 'Novo Negócio' } } }]),
          gemini_step.call([{ text: 'Oportunidade criada!' }])
        )

      post_message('Quero contratar o serviço')
      expect(response).to have_http_status(:ok)

      expect(sandbox_conversation.reload.active_opportunity).to be_present
      expect(sandbox_conversation.active_opportunity.title).to eq('Novo Negócio')
    end

    it 'leaves conversation with no opportunity when manage_opportunity is not called' do
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá!' }]))

      post_message('Olá!')
      expect(response).to have_http_status(:ok)

      expect(sandbox_conversation.reload.active_opportunity).to be_nil
    end
  end

  describe 'US1-AS18: turn after exit_desqualificado' do
    it 'pins nothing by state on the next turn' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: unqualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal',
        status: :open
      )
      ScoutConversationState.for_conversation(sandbox_conversation).update!(
        active_playbook: nil,
        last_exit: 'desqualificado',
        completed_playbooks: ['qualificacao']
      )

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá de novo.' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to be_nil
    end
  end

  describe 'FR-028c: re-opening completed procedure via open_playbook' do
    it 'returns rendered body plus pending-fields block and pins with reason trigger' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: lead_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal',
        status: :open
      )
      ScoutConversationState.for_conversation(sandbox_conversation).update!(
        active_playbook: nil,
        completed_playbooks: ['qualificacao']
      )

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'qualificacao' } } }]),
          gemini_step.call([{ text: 'Reabrindo qualificação.' }])
        )

      post_message('Gostaria de atualizar meus dados de qualificação')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('qualificacao')
      expect(state.activation_reason).to eq('trigger')

      tool_calls = response.parsed_body['tool_calls']
      open_pb_call = tool_calls.find { |c| c['tool_name'] == 'open_playbook' }
      expect(open_pb_call['result']['body']).to include('Campos pendentes para esta oportunidade:')
      expect(open_pb_call['result']['body']).to include('- Orçamento (chave: orcamento)')
    end
  end

  describe 'Preemption edge case' do
    it 'pins identificacao by state when phone is removed post-qualificacao and leaves completed_playbooks unchanged' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.record_state_activation!('qualificacao')

      # Now phone is removed
      contact.update!(phone_number: nil)

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Qual seu telefone?' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      state.reload
      expect(state.active_playbook).to eq('identificacao')
      expect(state.activation_reason).to eq('state')
      expect(state.completed_playbooks).to eq([])
    end
  end

  describe 'Complete opportunity edge case' do
    it 'has nothing pinned by state when all fields filled, index contains ainda não confirmados, and scripted opening pins trigger' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: lead_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal',
        status: :open,
        custom_attributes: { 'orcamento' => '50000' }
      )

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'qualificacao' } } }]),
          gemini_step.call([{ text: 'Qualificação aberta.' }])
        )

      post_message('Quero revisar a qualificação')
      expect(response).to have_http_status(:ok)

      expect(system_text).to include('ainda não confirmados')

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('qualificacao')
      expect(state.activation_reason).to eq('trigger')
    end
  end

  describe 'US2: Three situational playbooks (duvida_comercial, pausa, fora_de_prospeccao)' do
    it 'verifies US2-AS2/AS4: duvida_comercial opening result, leaves completed_playbooks, next turn routes back', :aggregate_failures do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.record_state_activation!('qualificacao')

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'duvida_comercial' } } }]),
          gemini_step.call([{ text: 'Consultei a base: atendemos de segunda a sexta.' }])
        )

      post_message('Qual o horário de atendimento?')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      open_call = tool_calls.find { |tc| tc['tool_name'] == 'open_playbook' }
      expect(open_call).to be_present
      body = (open_call.dig('result', 'body') || open_call.dig('result', :body)).to_s
      expect(body).to include('search_knowledge_base')
      expect(body).to include('apenas com o que a base de conhecimento retornar')
      expect(body).to include('não invente')
      expect(body).to include('diga que não tem essa informação')
      expect(body).to include('exit_handoff')
      expect(body).not_to include('update_contact')
      expect(body).not_to include('manage_opportunity')

      expect(state.reload.completed_playbooks).to eq([])
      expect(state.active_playbook).to eq('qualificacao')

      # Next turn: routes to qualificacao with state activation reason and pending fields
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Voltando à qualificação.' }]))

      post_message('Entendi, obrigado')
      expect(response).to have_http_status(:ok)

      expect(state.reload.active_playbook).to eq('qualificacao')
      expect(state.activation_reason).to eq('state')
      expect(system_text).to include('Campos pendentes para esta oportunidade:')
    end

    it 'verifies US2-AS3/AS5: pausa opening result, leaves completed_playbooks, next turn routes back', :aggregate_failures do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.record_state_activation!('qualificacao')

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]),
          gemini_step.call([{ text: 'Fique à vontade! Estaremos por aqui quando quiser.' }])
        )

      post_message('Vou pensar um pouco e depois volto')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      open_call = tool_calls.find { |tc| tc['tool_name'] == 'open_playbook' }
      expect(open_call).to be_present
      body = (open_call.dig('result', 'body') || open_call.dig('result', :body)).to_s
      expect(body).to include('responda com cordialidade')
      expect(body).to include('deixe a porta aberta')
      expect(body).to include('não retome perguntas de qualificação')
      expect(body).not_to include('update_contact')
      expect(body).not_to include('manage_opportunity')

      expect(state.reload.completed_playbooks).to eq([])

      # Next turn: routes back to qualificacao
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Continuando...' }]))

      post_message('Olá novamente')
      expect(response).to have_http_status(:ok)

      expect(state.reload.active_playbook).to eq('qualificacao')
      expect(state.activation_reason).to eq('state')
      expect(system_text).to include('Campos pendentes para esta oportunidade:')
    end

    it 'leaves active_playbook as nil when pausa is opened with nothing pinned' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: lead_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal',
        status: :open,
        custom_attributes: { 'orcamento' => '50000' }
      )

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]),
          gemini_step.call([{ text: 'Tudo bem! Até logo.' }])
        )

      post_message('Vou pensar e volto depois')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to be_nil
    end

    it 'verifies US2-AS7: IndexBuilder lines for duvida_comercial and fora_de_prospeccao each name the other as excluded' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Como posso ajudar?' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      expect(system_text).to include('duvida_comercial')
      expect(system_text).to include('fora_de_prospeccao')
      expect(system_text).to include('isso é fora_de_prospeccao')
      expect(system_text).to include('isso é duvida_comercial')
    end

    it 'verifies US2-AS4 (partial): duvida_comercial and pausa opened with identificacao pinned resume it unchanged', :aggregate_failures do
      contact.update!(name: 'lindo-peixe-123', phone_number: nil)
      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.record_state_activation!('identificacao')

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'duvida_comercial' } } }]),
          gemini_step.call([{ text: 'Consultei a base: atendemos de segunda a sexta.' }])
        )

      post_message('Qual o horário de atendimento?')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      open_call = tool_calls.find { |tc| tc['tool_name'] == 'open_playbook' }
      expect(open_call).to be_present
      body = (open_call.dig('result', 'body') || open_call.dig('result', :body)).to_s
      expect(body).to include('search_knowledge_base')
      expect(body).not_to include('update_contact')

      expect(state.reload.completed_playbooks).to eq([])
      expect(state.active_playbook).to eq('identificacao')

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]),
          gemini_step.call([{ text: 'Tudo bem, aguardamos.' }])
        )

      post_message('Deixa eu pensar')
      expect(response).to have_http_status(:ok)

      pausa_tool_calls = response.parsed_body['tool_calls']
      pausa_open_call = pausa_tool_calls.find { |tc| tc['tool_name'] == 'open_playbook' }
      expect(pausa_open_call).to be_present
      pausa_body = (pausa_open_call.dig('result', 'body') || pausa_open_call.dig('result', :body)).to_s
      expect(pausa_body).to include('não retome perguntas de qualificação')
      expect(state.reload.completed_playbooks).to eq([])
      expect(state.active_playbook).to eq('identificacao')

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Podemos continuar?' }]))

      post_message('Voltei')
      expect(response).to have_http_status(:ok)

      expect(state.reload.active_playbook).to eq('identificacao')
      expect(state.activation_reason).to eq('state')
      expect(system_text).to include('Dados de contato faltando')
    end
  end

  describe 'US3: Scheduling degrades visibly (agendamento)' do
    it 'verifies US3-AS1/SC-005: agendamento system text has asserted phrases, 5 pending lines, no must-nots', :aggregate_failures do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open,
        custom_attributes: {}
      )

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Vamos agendar seu horário.' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.active_playbook).to eq('agendamento')
      expect(state.activation_reason).to eq('state')

      expect(system_text).to include('dia de preferência')
      expect(system_text).to include('no máximo três horários')
      expect(system_text).to include('exit_agendado')
      expect(system_text).to include('exit_sem_horario')
      expect(system_text).to include('falar com uma pessoa')
      expect(system_text).to include('urgência clínica')
      expect(system_text).to include('duas tentativas')
      expect(system_text).to include('exit_handoff')
      expect(system_text).to include('chame exit_handoff neste mesmo turno')

      expect(system_text).not_to include('update_contact')
      expect(system_text).not_to include('manage_opportunity')

      expect(system_text.scan(/\(PENDENTE — indisponível: customer_registry\)/).count).to eq(1)
      expect(system_text.scan(/\(PENDENTE — indisponível: scheduling\)/).count).to eq(3)
      expect(system_text.scan(/\(PENDENTE — indisponível: politica_reagendamento\)/).count).to eq(1)
      expect(system_text.scan(/\(PENDENTE — indisponível:.*?\)/).count).to eq(5)
    end

    it 'verifies US3-AS3: agendamento is not pinned by state without a phone on record', :aggregate_failures do
      contact.update!(name: 'Carlos Silva', phone_number: nil)
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal sem telefone',
        status: :open,
        custom_attributes: {}
      )
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá, poderia informar seu telefone?' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)
      expect(ScoutConversationState.for_conversation(sandbox_conversation).active_playbook).not_to eq('agendamento')
    end

    it 'verifies US3-AS3: agendamento is not pinned by state outside the qualified stage', :aggregate_failures do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: lead_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal fora do estágio qualificado',
        status: :open,
        custom_attributes: { 'orcamento' => '50000' }
      )
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá!' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)
      expect(ScoutConversationState.for_conversation(sandbox_conversation).active_playbook).not_to eq('agendamento')
    end

    it 'verifies US3-AS5: agendamento offers exit_handoff but withholds exit_agendado and exit_sem_horario', :aggregate_failures do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open,
        custom_attributes: {}
      )
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Vamos agendar seu horário.' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      tool_names = provider_requests.first.dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
      expect(tool_names).to include('exit_handoff')
      expect(tool_names).not_to include('exit_agendado', 'exit_sem_horario')
    end

    it 'verifies US1/US3 transition: qualificacao offers exit_qualificado, moves to agendamento with 5 pending lines', :aggregate_failures do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: lead_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal',
        status: :open,
        custom_attributes: { 'orcamento' => '50000' }
      )

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.record_state_activation!('qualificacao')

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_qualificado', args: {} } }]),
          gemini_step.call([{ text: 'Qualificado com sucesso!' }])
        )

      post_message('Tudo confirmado')
      expect(response).to have_http_status(:ok)

      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).to include('exit_qualificado')

      expect(system_text).to include('exit_qualificado')
      expect(system_text).to include('siga no mesmo turno')

      tool_calls = response.parsed_body['tool_calls']
      qual_call = tool_calls.find { |tc| tc['tool_name'] == 'exit_qualificado' }
      expect(qual_call).to be_present
      result_body = qual_call['result'].to_s
      expect(result_body.scan(/\(PENDENTE — indisponível:.*?\)/).count).to eq(5)

      state.reload
      expect(state.active_playbook).to eq('agendamento')
      expect(state.activation_reason).to eq('transition')
      expect(state.completed_playbooks).to include('qualificacao')
      expect(sandbox_conversation.active_opportunity.pipeline_stage).to eq(qualified_stage)
    end

    it 'verifies US3-AS3, AS4, AS5: transfers with exit_handoff under human request, clinical urgency, and failed registry attempts' do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open,
        custom_attributes: {}
      )

      # Human request transfer
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Cliente pediu para falar com uma pessoa' } } }]),
          gemini_step.call([{ text: 'Transferindo para um atendente.' }])
        )

      post_message('Quero falar com uma pessoa')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.last_exit).to eq('handoff')
      expect(state.completed_playbooks).to include('agendamento')
    end

    context 'with trace metadata (OTel / Langfuse) (T066)' do
      let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }

      around do |example|
        InstallationConfig.where(name: %w[OTEL_PROVIDER LANGFUSE_BASE_URL LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY]).destroy_all
        InstallationConfig.create!(name: 'OTEL_PROVIDER', value: 'langfuse')
        InstallationConfig.create!(name: 'LANGFUSE_BASE_URL', value: 'https://cloud.langfuse.com')
        InstallationConfig.create!(name: 'LANGFUSE_PUBLIC_KEY', value: 'pk-lf-test')
        InstallationConfig.create!(name: 'LANGFUSE_SECRET_KEY', value: 'sk-lf-test')
        stub_request(:post, %r{https://cloud.langfuse.com/api/public/otel/v1/traces}).to_return(status: 200)

        OpentelemetryConfig.reset!
        OpentelemetryConfig.initialize!
        processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
        OpenTelemetry.tracer_provider.add_span_processor(processor)

        example.run

        begin
          OpenTelemetry.tracer_provider.shutdown
        rescue StandardError
          nil
        end
        OpentelemetryConfig.reset!
        InstallationConfig.where(name: %w[OTEL_PROVIDER LANGFUSE_BASE_URL LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY]).destroy_all
      end

      it 'records unsatisfied_flags on the parent agent-session span and omits it from the child LLM span', :aggregate_failures do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: qualified_stage,
          origin_conversation: sandbox_conversation,
          active_conversation: sandbox_conversation,
          title: 'Deal Qualificado',
          status: :open,
          custom_attributes: { 'orcamento' => '50000' }
        )

        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(gemini_step.call([{ text: 'Vamos agendar seu horário.' }]))

        post_message('Oi')
        expect(response).to have_http_status(:ok)

        turn_spans = exporter.finished_spans.select { |s| s.name == 'llm.scout_v2.turn_runner' }
        expect(turn_spans.size).to eq(2)

        parent_span = turn_spans.find { |s| s.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID }
        child_span = turn_spans.find { |s| s.parent_span_id == parent_span.span_id }

        expect(parent_span).to be_present
        expect(child_span).to be_present

        raw_metadata = parent_span.attributes['langfuse.trace.metadata.unsatisfied_flags']
        expect(raw_metadata).to be_present
        parsed = JSON.parse(raw_metadata)
        expect(parsed['procedure']).to eq('agendamento')
        expect(parsed['pending_fields']).to eq([])
        expect(parsed['unmet_requires']).to eq(%w[scheduling customer_registry])
        expect(parsed['unmet_needs']).to eq(%w[politica_reagendamento])

        expect(child_span.attributes).not_to have_key('langfuse.trace.metadata.unsatisfied_flags')
      end

      it 'verifies T081: chained exits (exit_qualificado → exit_handoff) with state-pinned qualificacao', :aggregate_failures do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: lead_stage,
          origin_conversation: sandbox_conversation,
          active_conversation: sandbox_conversation,
          title: 'Deal',
          status: :open,
          custom_attributes: { 'orcamento' => '50000' }
        )

        state = ScoutConversationState.for_conversation(sandbox_conversation)
        state.record_state_activation!('qualificacao')

        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(
            gemini_step.call([{ functionCall: { name: 'exit_qualificado', args: {} } }]),
            gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Cliente transferido para atendimento' } } }]),
            gemini_step.call([{ text: 'Transferindo para um atendente.' }])
          )

        post_message('Tudo certo')

        # Verify state after chained exits
        state.reload
        expect(state.completed_playbooks).to include('qualificacao')
        expect(state.completed_playbooks).to include('agendamento')
        expect(state.last_exit).to eq('handoff')

        # Verify unsatisfied_flags recorded to agendamento
        unsatisfied = state.unsatisfied_flags || {}
        expect(unsatisfied['procedure']).to eq('agendamento')
        expect(unsatisfied['unmet_requires']).to match_array(%w[scheduling customer_registry])
        expect(unsatisfied['unmet_needs']).to include('politica_reagendamento')

        # Verify trace metadata captures qualificacao pinning
        turn_spans = exporter.finished_spans.select { |s| s.name == 'llm.scout_v2.turn_runner' }
        expect(turn_spans).not_to be_empty

        parent_span = turn_spans.find { |s| s.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID }
        expect(parent_span).to be_present

        # Check metadata shows qualificacao was the activated playbook
        raw_metadata = parent_span.attributes['langfuse.trace.metadata']
        expect(raw_metadata).to be_present
        metadata = JSON.parse(raw_metadata)
        expect(metadata['playbook']).to eq('qualificacao')
        expect(metadata['activation_reason']).to eq('state')

        # Check unsatisfied_flags in trace metadata names agendamento as the deficient playbook
        unsatisfied_flags_attr = parent_span.attributes['langfuse.trace.metadata.unsatisfied_flags']
        expect(unsatisfied_flags_attr).to be_present
        unsatisfied_parsed = JSON.parse(unsatisfied_flags_attr)
        expect(unsatisfied_parsed['procedure']).to eq('agendamento')
      end
    end
  end
end
