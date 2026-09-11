# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::SearchKnowledgeBase do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Search Scout',
      enabled: true
    )
  end
  let(:tool) { described_class.new(scout, conversation) }

  describe '#execute' do
    it 'returns warning when query is blank' do
      expect(tool.execute(query: '')).to eq('Nenhum termo de busca fornecido.')
    end

    it 'returns no info message when embedding is unsupported/empty' do
      fake_config = instance_double(Custom::Scout::EmbeddingConfig, embed: [])
      allow(Custom::Scout::EmbeddingConfig).to receive(:for).with(account).and_return(fake_config)

      result = tool.execute(query: 'What is your warranty?')
      expect(result).to eq('Nenhuma informação relevante encontrada na base de conhecimento.')
    end

    it 'embeds query, runs nearest_neighbors, and formats matching Q&A pairs' do
      fake_vector = Array.new(768, 0.05)
      fake_config = instance_double(Custom::Scout::EmbeddingConfig, embed: fake_vector)
      allow(Custom::Scout::EmbeddingConfig).to receive(:for).with(account).and_return(fake_config)

      source = ScoutKnowledgeSource.create!(account: account, scout: scout, kind: :faq, question: 'Warranty?', answer: '1 year.')
      embedding = ScoutKnowledgeEmbedding.create!(
        account: account,
        scout: scout,
        scout_knowledge_source: source,
        question: 'What is the warranty policy?',
        answer: '12 months full warranty.'
      )

      allow(scout.scout_knowledge_embeddings).to receive(:nearest_neighbors).with(:embedding, fake_vector, distance: 'cosine').and_return(
        ScoutKnowledgeEmbedding.where(id: embedding.id)
      )

      result = tool.execute(query: 'warranty')
      expect(result).to include('Pergunta: What is the warranty policy?')
      expect(result).to include('Resposta: 12 months full warranty.')
    end

    it 'returns no relevant matches message when nearest_neighbors is empty' do
      fake_vector = Array.new(768, 0.05)
      fake_config = instance_double(Custom::Scout::EmbeddingConfig, embed: fake_vector)
      allow(Custom::Scout::EmbeddingConfig).to receive(:for).with(account).and_return(fake_config)

      allow(scout.scout_knowledge_embeddings).to receive(:nearest_neighbors).and_return(ScoutKnowledgeEmbedding.none)

      result = tool.execute(query: 'refund policy')
      expect(result).to include('Nenhuma informação relevante encontrada na base de conhecimento para: refund policy')
    end

    it 'returns error message when unexpected exception is raised' do
      fake_vector = Array.new(768, 0.05)
      fake_config = instance_double(Custom::Scout::EmbeddingConfig, embed: fake_vector)
      allow(Custom::Scout::EmbeddingConfig).to receive(:for).with(account).and_return(fake_config)

      allow(scout.scout_knowledge_embeddings).to receive(:nearest_neighbors).and_raise(StandardError.new('DB timeout'))

      result = tool.execute(query: 'help')
      expect(result).to include('Erro ao consultar base de conhecimento: DB timeout')
    end
  end
end
