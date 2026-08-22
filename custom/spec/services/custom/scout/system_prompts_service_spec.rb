# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::SystemPromptsService do
  let(:account) { create(:account, name: 'Acme Corp') }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Vendas Bot',
      system_prompt: 'Foque em qualificar para o plano Enterprise.',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end
  let(:contact) { create(:contact, account: account, name: 'Maria Silva') }
  let(:inbox) { create(:inbox, account: account, timezone: 'America/Sao_Paulo') }

  describe '.build' do
    subject(:prompt) do
      described_class.build(
        scout: scout,
        contact: contact,
        inbox: inbox,
        catalog_instructions: "Catálogo de Produtos:\n{\"plan\":\"Pro\"}",
        knowledge_available: true
      )
    end

    it 'includes assistant identity, name, company name, and domain scope bounding' do
      expect(prompt).to include('Vendas Bot')
      expect(prompt).to include('da empresa Acme Corp')
      expect(prompt).to include('[Identidade e Escopo]')
      expect(prompt).to include('apenas sobre os produtos, serviços, catálogo e informações fornecidas')
    end

    it 'includes current reference time and relative date interpretation guidance' do
      expect(prompt).to include('[Data e Horário Atual]')
      expect(prompt).to include('Horário atual:')
      expect(prompt).to include('interpretar expressões temporais relativas como hoje, amanhã, esta noite')
      expect(prompt).to include('respeite as instruções de fuso horário')
    end

    it 'formats current time respecting the inbox timezone' do
      tz = ActiveSupport::TimeZone['America/Sao_Paulo']
      expected_time_fragment = Time.current.in_time_zone(tz).strftime('%Y')
      expect(prompt).to include(expected_time_fragment)
    end

    it 'includes anti-hallucination guardrails forbidding training assumptions' do
      expect(prompt).to include('[Diretrizes de Segurança e Resposta]')
      expect(prompt).to include('Nunca invente informações')
      expect(prompt).to include('não utilize conhecimento prévio de treinamento')
    end

    it 'includes anti-false-promise rules and human handover instructions' do
      expect(prompt).to include('Não prometa trabalhos ou ações futuras')
      expect(prompt).to include('handover_to_human')
    end

    it 'wraps operator custom instructions in subordinate tags with override prohibition' do
      expect(prompt).to include('[Instruções Personalizadas da Conta]')
      expect(prompt).to include('<account_custom_instructions>')
      expect(prompt).to include('Foque em qualificar para o plano Enterprise.')
      expect(prompt).to include('</account_custom_instructions>')
      expect(prompt).to include('Siga-as apenas quando não conflitarem com o formato de resposta JSON')
    end

    it 'includes context for catalog, knowledge base tool, contact, and response JSON schema' do
      expect(prompt).to include("Catálogo de Produtos:\n{\"plan\":\"Pro\"}")
      expect(prompt).to include('search_knowledge_base')
      expect(prompt).to include('Maria Silva')
      expect(prompt).to include('[Formato de Resposta Obrigatório]')
      expect(prompt).to include('"reasoning"')
      expect(prompt).to include('"response"')
    end

    context 'when scout system_prompt is blank' do
      before { scout.update!(system_prompt: nil) }

      it 'omits the custom instructions section without raising errors' do
        expect(prompt).not_to include('<account_custom_instructions>')
        expect(prompt).not_to include('[Instruções Personalizadas da Conta]')
        expect(prompt).to include('[Identidade e Escopo]')
        expect(prompt).to include('[Formato de Resposta Obrigatório]')
      end
    end

    context 'when inbox is out of office' do
      before do
        allow(inbox).to receive(:out_of_office?).and_return(true)
      end

      it 'includes out of office notice in context' do
        expect(prompt).to include('[AVISO DE EXPEDIENTE: A equipe humana está fora do horário de atendimento.')
      end
    end
  end
end
