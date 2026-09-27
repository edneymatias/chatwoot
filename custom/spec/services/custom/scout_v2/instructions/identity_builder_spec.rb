# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Instructions::IdentityBuilder do
  let(:account) { create(:account, name: 'Sorriso Odonto') }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Clara',
      persona: 'MARCADOR-PERSONA-SECRETA'
    )
  end

  describe '.call' do
    context 'when both role and scope are empty (default identity)' do
      it 'renders the default intro, purpose, and scope statements byte-identically' do
        expected = <<~SECTION.strip
          [Identity]
          Você é Clara, um assistente inteligente de qualificação comercial e vendas da empresa Sorriso Odonto.
          Seu objetivo é qualificar leads, tirar dúvidas sobre produtos e serviços e auxiliar no processo comercial.
          Você deve responder apenas sobre os produtos, serviços, catálogo e informações fornecidas neste contexto ou acessíveis através das ferramentas disponíveis.
        SECTION

        expect(described_class.call(scout: scout)).to eq(expected)
      end
    end

    context 'when role is filled and scope is empty' do
      before do
        scout.role = 'SDR da clínica, atende pacientes adultos em São Paulo.'
      end

      it 'replaces intro with neutral intro and purpose with role, keeping default scope' do
        expected = <<~SECTION.strip
          [Identity]
          Você é Clara, assistente da empresa Sorriso Odonto.
          SDR da clínica, atende pacientes adultos em São Paulo.
          Você deve responder apenas sobre os produtos, serviços, catálogo e informações fornecidas neste contexto ou acessíveis através das ferramentas disponíveis.
        SECTION

        expect(described_class.call(scout: scout)).to eq(expected)
      end

      it 'does not contain default purpose or qualification intro phrases' do
        result = described_class.call(scout: scout)
        expect(result).not_to include('assistente inteligente de qualificação comercial e vendas')
        expect(result).not_to include('Seu objetivo é qualificar leads')
      end
    end

    context 'when role is empty and scope is filled' do
      before do
        scout.scope = "- não informa preços de tratamento\n- não agenda urgências"
      end

      it 'keeps default intro and purpose, replacing scope statement with scope verbatim' do
        expected = <<~SECTION.strip
          [Identity]
          Você é Clara, um assistente inteligente de qualificação comercial e vendas da empresa Sorriso Odonto.
          Seu objetivo é qualificar leads, tirar dúvidas sobre produtos e serviços e auxiliar no processo comercial.
          - não informa preços de tratamento
          - não agenda urgências
        SECTION

        expect(described_class.call(scout: scout)).to eq(expected)
      end

      it 'does not contain default scope statement' do
        result = described_class.call(scout: scout)
        expect(result).not_to include('Você deve responder apenas sobre os produtos')
      end
    end

    context 'when both role and scope are filled' do
      before do
        scout.role = "SDR da clínica,\natende pacientes adultos em São Paulo."
        scout.scope = "- não informa preços de tratamento\n- não agenda urgências"
      end

      it 'renders neutral intro, role verbatim, and scope verbatim' do
        expected = <<~SECTION.strip
          [Identity]
          Você é Clara, assistente da empresa Sorriso Odonto.
          SDR da clínica,
          atende pacientes adultos em São Paulo.
          - não informa preços de tratamento
          - não agenda urgências
        SECTION

        expect(described_class.call(scout: scout)).to eq(expected)
      end

      it 'does not contain default intro, default purpose, or default scope' do
        result = described_class.call(scout: scout)
        expect(result).not_to include('assistente inteligente de qualificação comercial e vendas')
        expect(result).not_to include('Seu objetivo é qualificar leads')
        expect(result).not_to include('Você deve responder apenas sobre os produtos')
      end
    end

    describe 'persona isolation' do
      it 'never contains any persona content regardless of role and scope configuration' do
        # Empty
        expect(described_class.call(scout: scout)).not_to include('MARCADOR-PERSONA-SECRETA')

        # Filled
        scout.role = 'Atendente'
        scout.scope = 'Suporte'
        expect(described_class.call(scout: scout)).not_to include('MARCADOR-PERSONA-SECRETA')
      end
    end
  end
end
