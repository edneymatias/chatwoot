# frozen_string_literal: true

class ScoutKnowledgeEmbedding < ApplicationRecord
  self.table_name = 'ichatr_scout_knowledge_embeddings'

  belongs_to :account
  belongs_to :scout
  belongs_to :scout_knowledge_source

  has_neighbors :embedding, normalize: true

  validates :question, :answer, presence: true

  before_validation :set_account_and_scout_from_source
  after_commit :enqueue_embed_job, on: :create, if: -> { embedding.blank? }

  private

  def set_account_and_scout_from_source
    return unless scout_knowledge_source

    self.account_id ||= scout_knowledge_source.account_id
    self.scout_id ||= scout_knowledge_source.scout_id
  end

  def enqueue_embed_job
    Custom::Scout::KnowledgeSources::EmbedEntryJob.perform_later(id)
  end
end
