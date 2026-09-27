# frozen_string_literal: true

class Custom::ScoutV2::Tools::OpenPlaybook < Custom::Scout::Tools::BaseTool
  TurnSetup = Data.define(:baseline_instructions, :baseline_tools, :tool_wrapper)

  description 'Open a playbook by name from the playbook index to activate its procedure and tools'

  param :name, type: :string, desc: 'Exact playbook name as it appears in the Playbook Index block', required: true

  def initialize(scout, conversation, chat:, openable:, turn_setup:)
    super(scout, conversation)
    @chat = chat
    @openable = openable
    @turn_setup = turn_setup
  end

  def name
    'open_playbook'
  end

  def execute(name:)
    playbook = @openable[name]
    if playbook.blank?
      available = @openable.map(&:name).join(', ')
      return { error: "Playbook desconhecida: #{name}. Disponíveis: #{available}" }
    end

    playbook.when_state.blank? ? takeover!(playbook) : activate_procedure!(playbook)

    { body: playbook.body }
  end

  private

  def takeover!(playbook)
    @chat.with_instructions(@turn_setup.baseline_instructions)
    interruption_tools = Custom::ScoutV2::Tools::Registry.build(
      playbook.tools,
      scout: scout,
      conversation: conversation
    ).map { |tool| @turn_setup.tool_wrapper.call(tool) }
    @chat.with_tools(*@turn_setup.baseline_tools, self, *interruption_tools, replace: true)
  end

  def activate_procedure!(playbook)
    tools = Custom::ScoutV2::Tools::Registry.build(playbook.tools, scout: scout, conversation: conversation)
    tools.each do |tool|
      @chat.with_tool(@turn_setup.tool_wrapper.call(tool))
    end

    ScoutConversationState.for_conversation(conversation).record_trigger_activation!(playbook.name)
  end
end
