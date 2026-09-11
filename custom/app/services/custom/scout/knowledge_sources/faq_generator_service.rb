# frozen_string_literal: true

class Custom::Scout::KnowledgeSources::FaqGeneratorService
  MAX_CONTENT_LENGTH = 12_000

  attr_reader :knowledge_source, :scout, :account

  def initialize(knowledge_source)
    @knowledge_source = knowledge_source
    @scout = knowledge_source.scout
    @account = knowledge_source.account
  end

  def generate
    return [] if @knowledge_source.content.blank? || @scout.blank?

    truncated_content = @knowledge_source.content.to_s.slice(0, MAX_CONTENT_LENGTH)
    chat = @scout.llm_chat(temperature: 0.0)
    chat = chat.with_params(response_format: { type: 'json_object' }, temperature: 0.0) if chat.respond_to?(:with_params)
    chat.with_instructions(system_prompt)

    response = chat.ask(truncated_content)
    parse_faqs(response.respond_to?(:content) ? response.content : response.to_s)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception if defined?(ChatwootExceptionTracker)
    Rails.logger.error "[Scout FaqGeneratorService] Error: #{e.message}"
    []
  end

  private

  def system_prompt
    <<~PROMPT
      You are an expert AI assistant that synthesizes clear, atomic Question & Answer (FAQ) pairs from extracted text.
      Analyze the provided content and extract key questions and factual answers that users might ask.
      Preserve exact numbers, prices, dates, and specifications without hallucinating.
      Return your response ONLY as a valid JSON object matching this schema:
      {
        "faqs": [
          { "question": "Specific question?", "answer": "Clear, direct factual answer." }
        ]
      }
    PROMPT
  end

  def parse_faqs(raw_response)
    return [] if raw_response.blank?

    cleaned = raw_response.to_s.strip.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '')
    parsed = JSON.parse(cleaned)
    items = parsed.is_a?(Hash) ? parsed.fetch('faqs', []) : []
    items.filter_map do |item|
      q = item['question'].to_s.strip
      a = item['answer'].to_s.strip
      { question: q, answer: a } if q.present? && a.present?
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[Scout FaqGeneratorService] JSON parse error: #{e.message}"
    []
  end
end
