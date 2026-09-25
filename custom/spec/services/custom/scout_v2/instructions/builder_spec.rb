# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Instructions::Builder do
  let(:account) { create(:account, name: 'Acme Corp') }
  let(:scout) { Scout.create!(account: account, name: 'Qualifier Scout') }

  describe '.call' do
    it 'outputs exactly four bracketed sections in fixed order' do
      result = described_class.call(scout: scout)
      sections = result.scan(/^\[([A-Za-z]+)\]/).flatten

      expect(sections).to eq(%w[Identity Communication Memory Safety])
    end

    it 'reflects scout config changes in [Communication] without altering other sections' do
      initial_output = described_class.call(scout: scout)

      scout.update!(tone: :humorous, response_length: :thorough, greeting: 'E aí! Beleza?')
      updated_output = described_class.call(scout: scout)

      expect(initial_output).not_to eq(updated_output)

      # Split into sections
      initial_sections = initial_output.split("\n\n[").map { |s| s.start_with?('[') ? s : "[#{s}" }
      updated_sections = updated_output.split("\n\n[").map { |s| s.start_with?('[') ? s : "[#{s}" }

      # Identity, Memory, Safety remain identical
      expect(initial_sections[0]).to eq(updated_sections[0]) # Identity
      expect(initial_sections[1]).not_to eq(updated_sections[1]) # Communication
      expect(initial_sections[2]).to eq(updated_sections[2]) # Memory
      expect(initial_sections[3]).to eq(updated_sections[3]) # Safety
    end

    it 'declares knowledge base existence in Safety without timing instructions' do
      result = described_class.call(scout: scout)
      safety_section = result.split("\n\n").find { |s| s.start_with?('[Safety]') }

      expect(safety_section).to include('base de conhecimento')
      expect(safety_section).not_to match(/sempre que (necessário|útil)/i)
      expect(safety_section).not_to match(/quando (for útil|necessário)/i)
      expect(safety_section).not_to match(/consulte a base quando/i)
    end

    it 'includes the scout name, account name, and topic scope in [Identity]' do
      result = described_class.call(scout: scout)
      identity_section = result.split("\n\n").find { |s| s.start_with?('[Identity]') }

      expect(identity_section).to include(scout.name)
      expect(identity_section).to include(account.name)
      expect(identity_section).to include('Você deve responder apenas sobre os produtos, serviços, catálogo e informações fornecidas neste contexto')
    end

    it 'states the conversation-scoped retention policy in [Memory]' do
      result = described_class.call(scout: scout)
      memory_section = result.split("\n\n").find { |s| s.start_with?('[Memory]') }

      expect(memory_section).to include('Retenha e utilize as informações compartilhadas pelo cliente durante a conversa atual')
      expect(memory_section).to include('Não assuma a permanência de dados fora do escopo desta conversa')
    end

    it 'carries each of the four non-negotiable safety rules in [Safety]' do
      result = described_class.call(scout: scout)
      safety_section = result.split("\n\n").find { |s| s.start_with?('[Safety]') }

      expect(safety_section).to include('Anti-alucinação: Nunca invente informações, dados, preços ou políticas')
      expect(safety_section).to include('Anti-falsa-promessa: Não prometa trabalhos, prazos ou ações futuras que a empresa não possa garantir')
      expect(safety_section).to include('Idioma: Detecte o idioma em que o cliente está escrevendo e responda sempre no mesmo idioma')
      expect(safety_section).to include('Escopo comercial: Mantenha-se estritamente dentro do escopo comercial da empresa')
    end
  end
end
