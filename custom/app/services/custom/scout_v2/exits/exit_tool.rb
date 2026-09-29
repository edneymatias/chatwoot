# frozen_string_literal: true

class Custom::ScoutV2::Exits::ExitTool < Custom::Scout::Tools::BaseTool
  attr_reader :declaration, :scope

  def initialize(scout, conversation, declaration:, scope:)
    super(scout, conversation)
    @declaration = declaration
    @scope = scope
  end

  def name
    "exit_#{@declaration.name}"
  end

  def description
    case @declaration.kind
    when 'terminal'
      "Registra que o procedimento atual terminou com o desfecho '#{@declaration.name}'.#{stage_description}"
    when 'transition'
      "Encerra o procedimento atual e passa para o procedimento '#{@declaration.target}'.#{stage_description}"
    when 'escalation'
      if @declaration.name == 'handoff'
        'Transfere a conversa para atendimento humano. Informe o motivo da transferência.'
      else
        "Transfere a conversa para atendimento humano (desfecho '#{@declaration.name}').#{stage_description}"
      end
    end
  end

  def params_schema
    return nil if @declaration.fields.empty?

    properties = @declaration.fields.transform_values do |type|
      property_schema_for(type)
    end

    {
      type: 'object',
      properties: properties,
      required: @declaration.fields.keys
    }
  end

  def execute(**payload)
    problems = Custom::ScoutV2::Exits::PayloadValidator.call(@declaration, payload)
    return invalid_payload_error(problems) if problems.any?

    dispatch_exit(payload)
  end

  private

  def invalid_payload_error(problems)
    reason = "Dados inválidos para exit_#{@declaration.name}: #{problems.join('; ')}. Corrija e chame o exit novamente."
    if @declaration.kind == 'escalation'
      prefix = if @declaration.stage
                 'A transferência não aconteceu e o estágio não foi alterado: '
               else
                 'A transferência não aconteceu: '
               end
      return { error: "#{prefix}#{reason}" }
    end

    { error: reason }
  end

  def stage_description
    return '' unless @declaration.stage

    role_text = @declaration.stage == 'qualified' ? 'qualificado' : 'desqualificado'
    " Move a oportunidade para o estágio #{role_text}."
  end

  def property_schema_for(type)
    case type
    when 'datetime'
      { type: 'string', format: 'date-time' }
    else
      { type: type }
    end
  end

  def dispatch_exit(payload)
    case @declaration.kind
    when 'terminal'
      Custom::ScoutV2::Exits::Terminal.call(self)
    when 'transition'
      Custom::ScoutV2::Exits::Transition.call(self)
    when 'escalation'
      Custom::ScoutV2::Exits::Escalation.call(self, payload)
    end
  end
end
