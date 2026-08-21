# frozen_string_literal: true

class Custom::Scout::KnowledgeSources::GenerateFaqsJob < ApplicationJob
  queue_as :default

  def perform(knowledge_source_id)
    source = ScoutKnowledgeSource.find_by(id: knowledge_source_id)
    return unless source&.pending? && (source.url? || source.document?)

    faqs = Custom::Scout::KnowledgeSources::FaqGeneratorService.new(source).generate
    return if faqs.blank?

    embedding_config = Custom::Scout::EmbeddingConfig.for(source.account)

    source.with_lock do
      next unless source.pending?

      persist_faqs(source, faqs, embedding_config)
    end
  rescue StandardError => e
    Rails.logger.error "[Scout GenerateFaqsJob] Error for source #{knowledge_source_id}: #{e.message}\n#{e.backtrace&.join("\n")}"
    source&.update(status: :failed, error_message: e.message)
  end

  private

  def persist_faqs(source, faqs, embedding_config)
    source.scout_knowledge_embeddings.destroy_all
    unique_faqs = faqs.uniq { |f| f[:question].to_s.strip.downcase }
    unique_faqs.each { |faq| create_entry(source, faq, embedding_config) }
    source.update!(status: :ready, error_message: nil)
  end

  def create_entry(source, faq, embedding_config)
    vector = embedding_config.supported? ? embedding_config.embed("#{faq[:question]}: #{faq[:answer]}") : nil
    source.scout_knowledge_embeddings.create!(
      question: faq[:question],
      answer: faq[:answer],
      embedding: vector.presence
    )
  end
end
