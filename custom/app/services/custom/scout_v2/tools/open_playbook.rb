# frozen_string_literal: true

class Custom::ScoutV2::Tools::OpenPlaybook < Custom::Scout::Tools::BaseTool
  PROCEDURE_IN_EFFECT_ERROR = 'Já existe um procedimento em andamento neste turno: %<name>s. ' \
                              'Siga esse procedimento; a troca de procedimento só acontece por um exit de transição.'

  description 'Open a playbook by name from the playbook index to activate its procedure and tools'

  param :name, type: :string, desc: 'Exact playbook name as it appears in the Playbook Index block', required: true

  def initialize(scout, conversation, openable:, scope:)
    super(scout, conversation)
    @openable = openable
    @scope = scope
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
  end

  private

  def takeover!(playbook)
    interruption_tools = Custom::ScoutV2::Tools::Registry.build(
      playbook.tools,
      scout: scout,
      conversation: conversation
    )
    @scope.replace_with_baseline!(interruption_tools)
    { body: @scope.content_for(playbook) }
  end

  def activate_procedure!(playbook)
    return { error: format(PROCEDURE_IN_EFFECT_ERROR, name: @scope.active_procedure_name) } if @scope.procedure_in_turn?

    @scope.active_procedure_name = playbook.name
    actions = @scope.actions_for(playbook, scout: scout, conversation: conversation)
    @scope.register(actions)

    ScoutConversationState.for_conversation(conversation).record_trigger_activation!(playbook.name)
    { body: @scope.content_for(playbook) }
  end
end
