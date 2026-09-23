# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ActionClassifierService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Auditor Scout',
      enabled: true,
      feature_response_auditor: true
    )
  end
  let(:service) { described_class.new(scout: scout, conversation: conversation) }

  let(:message_history) do
    [
      { role: 'user', content: 'Quero falar com um humano agora por favor.' }
    ]
  end

  let(:fake_chat) { instance_double(RubyLLM::Chat) }
  let(:fake_response) do
    instance_double(
      RubyLLM::Message,
      content: { 'action' => 'handoff', 'action_reason' => 'explicit_human_request' }.to_json
    )
  end

  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)

    allow(scout).to receive(:llm_chat).with(temperature: 0.0).and_return(fake_chat)
    allow(fake_chat).to receive(:with_schema).with(Custom::Scout::ActionClassifierSchema).and_return(fake_chat)
    allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
    allow(fake_chat).to receive(:ask).and_return(fake_response)
  end

  describe '#classify' do
    it 'calls llm_chat with temperature 0.0 and schema, returning normalized action and action_reason' do
      expect(scout).to receive(:llm_chat).with(temperature: 0.0).and_return(fake_chat)
      expect(fake_chat).to receive(:with_schema).with(Custom::Scout::ActionClassifierSchema).and_return(fake_chat)
      expect(fake_chat).to receive(:ask) do |prompt|
        expect(prompt).to include('Quero falar com um humano')
        fake_response
      end

      result = service.classify(message_history: message_history)

      expect(result['action']).to eq('handoff')
      expect(result['action_reason']).to eq('explicit_human_request')
    end

    it 'forwards a custom temperature to llm_chat instead of the 0.0 default' do
      allow(scout).to receive(:llm_chat).with(temperature: 0.7).and_return(fake_chat)
      expect(scout).to receive(:llm_chat).with(temperature: 0.7).and_return(fake_chat)

      service.classify(message_history: message_history, temperature: 0.7)
    end

    it 'normalizes continue response with omitted action_reason correctly' do
      continue_response = instance_double(RubyLLM::Message, content: { 'action' => 'continue' }.to_json)
      allow(fake_chat).to receive(:ask).and_return(continue_response)

      result = service.classify(message_history: [{ role: 'user', content: 'Qual o horário de atendimento?' }])

      expect(result['action']).to eq('continue')
      expect(result['action_reason']).to be_nil
      expect(result['error']).to be_nil
    end

    it 'instruments the LLM call via instrument_llm_call' do
      expect(service).to receive(:instrument_llm_call).and_call_original

      service.classify(message_history: message_history)
    end

    it 'rescues StandardError, captures exception, logs warning, and returns a sentinel hash' do
      allow(fake_chat).to receive(:ask).and_raise(StandardError, 'LLM API error')
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      expect(tracker).to receive(:capture_exception).at_least(:once)
      expect(Rails.logger).to receive(:warn).with(/ActionClassifier/)

      result = service.classify(message_history: message_history)

      expect(result['action']).to be_nil
      expect(result['action_reason']).to be_nil
      expect(result['error']).to eq('LLM API error')
    end

    it 'does not return out_of_scope_commercial_request when customer declines one qualification' \
       'question after already demonstrating commercial intent' do
      # Scenario: customer shows commercial intent, answers questions, then declines one further question
      single_decline_history = [
        { role: 'user', content: 'Preciso de ajuda com o meu negócio online' },
        { role: 'assistant', content: 'Ótimo! Vejo que você tem interesse comercial. Vou fazer algumas perguntas para entender melhor.' },
        { role: 'user', content: 'Sim, quero saber como posso aumentar minhas vendas' },
        { role: 'assistant', content: 'Qual é o seu ramo de negócio?' },
        { role: 'user', content: 'Sou consultor independente' },
        { role: 'assistant', content: 'Entendi. Você já tem algum site ou loja online?' },
        { role: 'user', content: 'Não tenho ainda' },
        { role: 'assistant', content: 'Ótimo, posso ajudar. Há quanto tempo atua nessa área?' },
        { role: 'user', content: 'Já tenho 5 anos de experiência' },
        { role: 'assistant', content: 'Excelente! Você tem interesse em agendar uma chamada com nosso especialista?' },
        { role: 'user', content: 'Ainda não quero agendar agora' }
      ]

      continue_response = instance_double(RubyLLM::Message, content: { 'action' => 'continue' }.to_json)
      allow(fake_chat).to receive(:ask).and_return(continue_response)

      result = service.classify(message_history: single_decline_history)

      expect(result['action']).to eq('continue')
      expect(result['action_reason']).to be_nil
    end

    it 'does not return out_of_scope_commercial_request when customer accepts an option the assistant offered' do
      # Scenario: customer shows commercial intent, answers questions, then accepts an offered
      # appointment slot in a terse reply (production case: conversation display_id 132 — "sexta-feira,
      # de manhã. pode ser." right after being asked to choose a period of day)
      accepted_offer_history = [
        { role: 'user', content: 'Quero fazer uma limpeza dental' },
        { role: 'assistant', content: 'Você prefere ser atendido como particular ou pelo convênio?' },
        { role: 'user', content: 'Particular' },
        { role: 'assistant', content: 'Perfeito. Foi uma manutenção de rotina ou você sentiu algum incômodo?' },
        { role: 'user', content: 'Rotina, faço a cada 6 meses' },
        { role: 'assistant', content: 'Podemos ver um horário de avaliação. Você prefere manhã, tarde ou final de tarde?' },
        { role: 'user', content: 'Sexta-feira, de manhã. Pode ser.' }
      ]

      continue_response = instance_double(RubyLLM::Message, content: { 'action' => 'continue' }.to_json)
      allow(fake_chat).to receive(:ask).and_return(continue_response)

      result = service.classify(message_history: accepted_offer_history)

      expect(result['action']).to eq('continue')
      expect(result['action_reason']).to be_nil
    end

    it 'still correctly returns out_of_scope_commercial_request for genuinely out-of-scope scenarios' do
      # Scenario 1: Existing customer with unrelated ongoing issue (not a new commercial request)
      existing_customer_history = [
        { role: 'user', content: 'Olá, sou cliente há 2 anos e tenho um problema com meu contrato' },
        { role: 'assistant', content: 'Entendi. Qual é o problema específico?' },
        { role: 'user', content: 'Preciso revisar os termos do contrato com um especialista jurídico' }
      ]

      out_of_scope_response = instance_double(
        RubyLLM::Message,
        content: { 'action' => 'handoff', 'action_reason' => 'out_of_scope_commercial_request' }.to_json
      )
      allow(fake_chat).to receive(:ask).and_return(out_of_scope_response)

      result = service.classify(message_history: existing_customer_history)

      expect(result['action']).to eq('handoff')
      expect(result['action_reason']).to eq('out_of_scope_commercial_request')
    end

    it 'returns out_of_scope_commercial_request for customer complaints unrelated to sales' do
      # Scenario 2: Customer filing a complaint (not a sales opportunity)
      complaint_history = [
        { role: 'user', content: 'Vou registrar uma reclamação sobre o atendimento péssimo que recebi' },
        { role: 'assistant', content: 'Peço desculpas pelos problemas. Gostaria de me contar mais?' },
        { role: 'user', content: 'A qualidade do suporte foi muito ruim e quero falar com um supervisor' }
      ]

      out_of_scope_response = instance_double(
        RubyLLM::Message,
        content: { 'action' => 'handoff', 'action_reason' => 'out_of_scope_commercial_request' }.to_json
      )
      allow(fake_chat).to receive(:ask).and_return(out_of_scope_response)

      result = service.classify(message_history: complaint_history)

      expect(result['action']).to eq('handoff')
      expect(result['action_reason']).to eq('out_of_scope_commercial_request')
    end

    it 'returns out_of_scope_commercial_request for purely informational questions without commercial intent' do
      # Scenario 3: Purely informational question with no commercial intent
      informational_history = [
        { role: 'user', content: 'Qual é a diferença entre as suas diferentes soluções?' },
        { role: 'assistant', content: 'Ótimo! Deixe-me explicar as principais diferenças.' },
        { role: 'user', content: 'Estou apenas pesquisando, não pretendo comprar nada. Só queria saber como vocês funcionam' }
      ]

      out_of_scope_response = instance_double(
        RubyLLM::Message,
        content: { 'action' => 'handoff', 'action_reason' => 'out_of_scope_commercial_request' }.to_json
      )
      allow(fake_chat).to receive(:ask).and_return(out_of_scope_response)

      result = service.classify(message_history: informational_history)

      expect(result['action']).to eq('handoff')
      expect(result['action_reason']).to eq('out_of_scope_commercial_request')
    end
  end
end
