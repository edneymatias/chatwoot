# frozen_string_literal: true

class Custom::Scout::KnowledgeSources::EmbedEntryJob < ApplicationJob
  queue_as :default

  def perform(embedding_id)
    entry = ScoutKnowledgeEmbedding.find_by(id: embedding_id)
    return unless entry&.account

    text_to_embed = "#{entry.question}: #{entry.answer}"
    vectors = Custom::Scout::EmbeddingConfig.for(entry.account).embed(text_to_embed)
    return if vectors.blank?

    entry.update!(embedding: vectors)
  rescue StandardError => e
    Rails.logger.error "[Scout EmbedEntryJob] Error embedding entry #{embedding_id}: #{e.message}\n#{e.backtrace&.join("\n")}"
  end
end
