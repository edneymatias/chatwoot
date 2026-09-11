# frozen_string_literal: true

class Custom::Scout::KnowledgeSources::ProcessJob < ApplicationJob
  queue_as :default

  def perform(knowledge_source)
    source = knowledge_source.is_a?(ScoutKnowledgeSource) ? knowledge_source : ScoutKnowledgeSource.find_by(id: knowledge_source)
    return unless source

    case source.kind.to_sym
    when :url
      process_url(source)
    when :document
      process_document(source)
    when :faq
      process_faq(source)
    end
  rescue StandardError => e
    Rails.logger.error "[Scout KnowledgeSource ProcessJob] Error: #{e.message}\n#{e.backtrace&.join("\n")}"
    source&.update(status: :failed, error_message: e.message)
  end

  private

  def process_url(source)
    response = HTTParty.get(source.url, timeout: 15, headers: { 'User-Agent' => 'Chatwoot-Scout-Crawler/1.0' })
    unless response.success?
      source.update!(status: :failed, error_message: "HTTP request failed with status #{response.code}")
      return
    end

    body = response.body.to_s
    text = Html2Text.convert(body)
    cleaned_text = text.gsub(/\s+/, ' ').strip

    source.update!(content: cleaned_text, error_message: nil)
    Custom::Scout::KnowledgeSources::GenerateFaqsJob.perform_later(source.id)
  end

  def process_document(source)
    unless source.document_file.attached?
      source.update!(status: :failed, error_message: 'Document file not attached')
      return
    end

    raw_pdf = source.document_file.download
    extracted_text = extract_text_from_pdf_data(raw_pdf)

    content_to_store = extracted_text.presence || "[Document: #{source.document_file.filename}]"
    source.update!(content: content_to_store, error_message: nil)
    Custom::Scout::KnowledgeSources::GenerateFaqsJob.perform_later(source.id)
  end

  def process_faq(source)
    content = "Q: #{source.question}\nA: #{source.answer}"
    embedding_config = Custom::Scout::EmbeddingConfig.for(source.account)
    vector = embedding_config.supported? ? embedding_config.embed("#{source.question}: #{source.answer}") : nil

    ActiveRecord::Base.transaction do
      entry = source.scout_knowledge_embeddings.find_or_initialize_by(
        question: source.question,
        answer: source.answer
      )
      entry.embedding = vector.presence
      entry.save!
      source.update!(content: content, status: :ready, error_message: nil)
    end
  end

  def extract_text_from_pdf_data(pdf_data)
    reader = PDF::Reader.new(StringIO.new(pdf_data.to_s))
    reader.pages.map(&:text).join("\n\n").gsub(/\s+/, ' ').strip
  rescue StandardError => e
    Rails.logger.error "[Scout ProcessJob] PDF extraction error: #{e.message}"
    nil
  end
end
