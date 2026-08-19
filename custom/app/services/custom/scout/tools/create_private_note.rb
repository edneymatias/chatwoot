# frozen_string_literal: true

class Custom::Scout::Tools::CreatePrivateNote < Custom::Scout::Tools::BaseTool
  description 'Creates an internal private note on the conversation with summary notes for the human sales team'

  param :content, type: :string, desc: 'Markdown or text content of the private note', required: true

  def name
    'create_private_note'
  end

  def execute(content:)
    Messages::MessageBuilder.new(nil, conversation, { content: content, private: true }).perform
    'Private note created successfully.'
  end
end
