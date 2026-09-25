# frozen_string_literal: true

class Custom::ScoutV2::Tools::OpenPlaybook < Custom::Scout::Tools::BaseTool
  description 'Open a playbook by name from the playbook index to activate its procedure and tools'

  param :name, type: :string, desc: 'Exact playbook name as it appears in the Playbook Index block', required: true

  def initialize(scout, conversation, chat:, catalog:, tool_wrapper:)
    super(scout, conversation)
    @chat = chat
    @catalog = catalog
    @tool_wrapper = tool_wrapper
  end

  def name
    'open_playbook'
  end

  def execute(name:)
    playbook = @catalog[name]
    if playbook.blank?
      available = @catalog.map(&:name).join(', ')
      return { error: "Playbook desconhecida: #{name}. Disponíveis: #{available}" }
    end

    tools = Custom::ScoutV2::Tools::Registry.build(playbook.tools, scout: scout, conversation: conversation)
    tools.each do |tool|
      @chat.with_tool(@tool_wrapper.call(tool))
    end

    ScoutConversationState.for_conversation(conversation).record_trigger_activation!(playbook.name)

    { body: playbook.body }
  end
end
