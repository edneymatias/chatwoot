# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::KnowledgeSources::GenerateFaqsJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Faq Scout',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end
  let(:source) do
    ScoutKnowledgeSource.create!(
      account: account,
      scout: scout,
      kind: :url,
      url: 'https://example.com/terms',
      status: :pending,
      content: 'Refunds are provided within 7 days.'
    )
  end

  describe '#perform' do
    it 'calls FaqGeneratorService, creates ScoutKnowledgeEmbedding records, and marks source ready' do
      fake_faqs = [
        { question: 'What is the refund policy?', answer: 'Refunds within 7 days.' }
      ]
      fake_service = instance_double(Custom::Scout::KnowledgeSources::FaqGeneratorService, generate: fake_faqs)
      allow(Custom::Scout::KnowledgeSources::FaqGeneratorService).to receive(:new).with(source).and_return(fake_service)

      expect do
        described_class.new.perform(source.id)
      end.to change(source.scout_knowledge_embeddings, :count).by(1)

      expect(source.reload.status).to eq('ready')
      embedding = source.scout_knowledge_embeddings.last
      expect(embedding.question).to eq('What is the refund policy?')
      expect(embedding.answer).to eq('Refunds within 7 days.')
      expect(embedding.account_id).to eq(account.id)
      expect(embedding.scout_id).to eq(scout.id)
    end

    it 'does nothing if source is not found' do
      expect do
        described_class.new.perform(999_999)
      end.not_to change(ScoutKnowledgeEmbedding, :count)
    end
  end
end
