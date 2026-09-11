# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScoutKnowledgeEmbedding, type: :model do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end
  let(:knowledge_source) do
    ScoutKnowledgeSource.create!(
      account: account,
      scout: scout,
      kind: :faq,
      question: 'Initial Q?',
      answer: 'Initial A'
    )
  end

  describe 'associations' do
    it 'belongs to account, scout, and scout_knowledge_source' do
      embedding = described_class.new(
        scout_knowledge_source: knowledge_source,
        question: 'What is this?',
        answer: 'This is a test.'
      )
      embedding.valid?

      expect(embedding.account).to eq(account)
      expect(embedding.scout).to eq(scout)
      expect(embedding.scout_knowledge_source).to eq(knowledge_source)
    end
  end

  describe 'validations' do
    it 'validates presence of question and answer' do
      embedding = described_class.new(scout_knowledge_source: knowledge_source)
      expect(embedding).not_to be_valid
      expect(embedding.errors[:question]).to be_present
      expect(embedding.errors[:answer]).to be_present
    end

    it 'is valid with question and answer' do
      embedding = described_class.new(
        scout_knowledge_source: knowledge_source,
        question: 'How does it work?',
        answer: 'It works via semantic vectors.'
      )
      expect(embedding).to be_valid
    end
  end

  describe 'callbacks' do
    it 'enqueues EmbedEntryJob after creation' do
      expect do
        described_class.create!(
          scout_knowledge_source: knowledge_source,
          question: 'How to buy?',
          answer: 'Visit the store.'
        )
      end.to have_enqueued_job(Custom::Scout::KnowledgeSources::EmbedEntryJob)
    end
  end
end
