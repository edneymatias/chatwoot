# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::KnowledgeSources::EmbedEntryJob, type: :job do
  let(:account) { create(:account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Embed Scout',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end
  let(:source) do
    ScoutKnowledgeSource.create!(
      account: account,
      scout: scout,
      kind: :faq,
      question: 'Question?',
      answer: 'Answer.'
    )
  end
  let(:embedding_entry) do
    ScoutKnowledgeEmbedding.create!(
      account: account,
      scout: scout,
      scout_knowledge_source: source,
      question: 'How to pay?',
      answer: 'We accept credit card.'
    )
  end

  describe '#perform' do
    it 'generates embedding vector and persists to embedding column' do
      fake_vector = Array.new(768, 0.1)
      fake_config = instance_double(Custom::Scout::EmbeddingConfig, embed: fake_vector)
      allow(Custom::Scout::EmbeddingConfig).to receive(:for).with(account).and_return(fake_config)

      described_class.new.perform(embedding_entry.id)

      expect(embedding_entry.reload.embedding).to be_present
    end

    it 'does nothing if vectors are blank' do
      fake_config = instance_double(Custom::Scout::EmbeddingConfig, embed: [])
      allow(Custom::Scout::EmbeddingConfig).to receive(:for).with(account).and_return(fake_config)

      described_class.new.perform(embedding_entry.id)

      expect(embedding_entry.reload.embedding).to be_nil
    end
  end
end
