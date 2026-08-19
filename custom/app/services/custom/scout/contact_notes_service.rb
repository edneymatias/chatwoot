# frozen_string_literal: true

class Custom::Scout::ContactNotesService
  def initialize(scout, conversation)
    @scout = scout
    @conversation = conversation
    @contact = conversation.contact
    @account = conversation.account
  end

  def generate_and_update_notes
    return [] if @contact.blank? || @conversation.blank?

    notes = generate_notes
    notes.each do |note|
      @contact.notes.create!(content: note) if note.present?
    end
    notes
  end

  private

  def generate_notes
    content = "#Contact\n\n#{@contact.to_llm_text}\n\n#Conversation\n\n#{@conversation.to_llm_text}"
    chat = @scout.llm_chat
    chat = chat.with_params(response_format: { type: 'json_object' }) if chat.respond_to?(:with_params)
    chat.with_instructions(system_prompt)

    response = chat.ask(content)
    parse_notes(response.respond_to?(:content) ? response.content : response.to_s)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "[Scout ContactNotesService] Error: #{e.message}"
    []
  end

  def system_prompt
    language = @account.locale_english_name || 'English'
    <<~PROMPT
      You are an AI assistant helping a sales and support team.
      Analyze the provided contact details and conversation history.
      Generate concise, actionable summary notes capturing key facts learned about this contact (e.g., specific requirements, budget, timeline, objections, business size, preferences).
      Respond in #{language}.
      Return your response ONLY as a valid JSON object with a 'notes' array of strings:
      {"notes": ["First summary note", "Second summary note"]}
    PROMPT
  end

  def parse_notes(raw_response)
    return [] if raw_response.blank?

    cleaned = raw_response.to_s.strip.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '')
    parsed = JSON.parse(cleaned)
    parsed.fetch('notes', [])
  rescue JSON::ParserError => e
    Rails.logger.error "[Scout ContactNotesService] JSON parse error: #{e.message}"
    []
  end
end
