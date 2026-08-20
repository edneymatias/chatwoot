# frozen_string_literal: true

class Custom::Scout::KnowledgeSources::ProcessJob < ApplicationJob
  queue_as :default

  def perform(knowledge_source)
    return unless knowledge_source.is_a?(ScoutKnowledgeSource)

    case knowledge_source.kind.to_sym
    when :url
      process_url(knowledge_source)
    when :document
      process_document(knowledge_source)
    when :faq
      process_faq(knowledge_source)
    end
  rescue StandardError => e
    Rails.logger.error "[Scout KnowledgeSource ProcessJob] Error: #{e.message}\n#{e.backtrace&.join("\n")}"
    knowledge_source.update(status: :failed, error_message: e.message)
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

    source.update!(content: cleaned_text, status: :ready, error_message: nil)
  end

  def process_document(source)
    unless source.document_file.attached?
      source.update!(status: :failed, error_message: 'Document file not attached')
      return
    end

    raw_pdf = source.document_file.download
    extracted_text = extract_text_from_pdf_data(raw_pdf)

    content_to_store = extracted_text.presence || "[Document: #{source.document_file.filename}]"
    source.update!(content: content_to_store, status: :ready, error_message: nil)
  end

  def process_faq(source)
    content = "Q: #{source.question}\nA: #{source.answer}"
    source.update!(content: content, status: :ready, error_message: nil)
  end

  def extract_text_from_pdf_data(pdf_data)
    texts = []
    pdf_data.to_s.scan(/BT\s*.*?\s*ET/m) do |stream|
      stream.scan(/\((.*?)\)\s*Tj/m) { |m| texts << m.first }
      stream.scan(/\[(.*?)\]\s*TJ/m) do |m|
        m.first.scan(/\((.*?)\)/) { |sub| texts << sub.first }
      end
    end
    texts.join(' ').gsub(/\s+/, ' ').strip
  rescue StandardError
    nil
  end
end
