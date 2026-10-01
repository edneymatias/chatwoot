# frozen_string_literal: true

class Custom::ScoutV2::Capabilities::OperationTool < Custom::Scout::Tools::BaseTool
  attr_reader :capability_instance, :operation

  AUTHENTICATION_ERROR_MESSAGE = 'O sistema do cliente recusou as credenciais configuradas; nada foi registrado. ' \
                                 'Não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.'

  GENERIC_ERP_ERROR_MESSAGE = 'O sistema do cliente não respondeu ou recusou a operação. Se era um cadastro ou agendamento, ' \
                              'o resultado é desconhecido e pode ter sido concluído: não repita. ' \
                              'Não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.'

  def initialize(scout, conversation, capability_instance:, operation:)
    super(scout, conversation)
    @capability_instance = capability_instance
    @operation = operation
  end

  def name
    "#{@capability_instance.class.capability_name}_#{@operation.name}"
  end

  def description
    case name
    when 'scheduling_list_slots'
      'Lista os horários livres disponíveis para agendamento na data informada.'
    when 'scheduling_book'
      'Realiza o agendamento de uma consulta em um horário livre previamente oferecido.'
    when 'customer_registry_find_by_phone'
      'Busca o cadastro do cliente pelo número de telefone do contato.'
    when 'customer_registry_create'
      'Cadastra um novo cliente com o nome confirmado e o telefone do contato.'
    else
      "Operação #{@operation.name} da capability #{@capability_instance.class.capability_name}."
    end
  end

  def params_schema
    @operation.params_schema
  end

  def execute(*args, **kwargs)
    inputs = args.first.is_a?(Hash) ? args.first.merge(kwargs) : kwargs

    validation_error = validate_inputs(inputs)
    return validation_error if validation_error

    precondition_error = check_capability_precondition(inputs)
    return precondition_error if precondition_error

    injected_info = build_injected_info(inputs)
    result = perform_operation(inputs, injected_info)
    handle_result(result, inputs, injected_info)
  end

  private

  def build_injected_info(_inputs)
    info = extract_settings_identifiers
    inject_context_identifiers(info)
    info.compact
  end

  def validate_inputs(inputs)
    problems = @operation.problems_for(inputs)
    return nil if problems.empty?

    err_msg = "Dados inválidos para #{name}: #{problems.join(', ')}. Corrija e chame a ferramenta novamente."
    record_trace(inputs: inputs, injected: {}, outcome: 'invalid_input', error: err_msg, deviations: [])
    { error: err_msg }
  end

  def check_capability_precondition(inputs)
    precondition_check = "check_preconditions_for_#{@operation.name}"
    return nil unless @capability_instance.respond_to?(precondition_check)

    precondition_error = @capability_instance.public_send(precondition_check, **inputs)
    return nil if precondition_error.blank?

    record_trace(inputs: inputs, injected: {}, outcome: 'precondition_failed', error: precondition_error, deviations: [])
    { error: precondition_error }
  end

  def perform_operation(inputs, injected_info)
    @capability_instance.public_send(@operation.name, **inputs)
  rescue Erp::AuthenticationError
    record_trace(inputs: inputs, injected: injected_info, outcome: 'erp_error', error: AUTHENTICATION_ERROR_MESSAGE, deviations: [])
    { error: AUTHENTICATION_ERROR_MESSAGE }
  rescue Erp::Error
    record_trace(inputs: inputs, injected: injected_info, outcome: 'erp_error', error: GENERIC_ERP_ERROR_MESSAGE, deviations: [])
    { error: GENERIC_ERP_ERROR_MESSAGE }
  end

  def handle_result(result, inputs, injected_info)
    if result.is_a?(Hash) && result[:error].present?
      deviations = result[:deviations] || []
      record_trace(inputs: inputs, injected: injected_info, outcome: 'erp_error', error: result[:error], deviations: deviations)
      return { error: result[:error] }
    end

    deviations = @operation.deviations_for(result)
    record_trace(inputs: inputs, injected: injected_info, outcome: 'ok', error: nil, deviations: deviations)
    result
  end

  def extract_settings_identifiers
    provider = @capability_instance.provider
    keys = provider.operation_identifier_keys(@operation.name)
    settings = provider.settings || {}

    keys.each_with_object({}) do |key, acc|
      val = settings[key]
      next if val.blank?

      acc[key] = cast_identifier(key, val)
    end
  end

  def cast_identifier(key, val)
    return Integer(val.to_s, 10) if key.start_with?('id_')

    val.to_s
  rescue ArgumentError, TypeError
    val
  end

  def inject_context_identifiers(info)
    if @capability_instance.is_a?(Custom::ScoutV2::Capabilities::CustomerRegistry)
      phone = contact&.phone_number
      info['phone'] = @capability_instance.provider.normalize_phone_digits(phone) if phone.present?
    elsif name == 'scheduling_book'
      state = ScoutConversationState.for_conversation(@conversation)
      customer_id = state.capability_state.dig('customer', 'id')
      info['person_id'] = customer_id if customer_id.present?
    end
  end

  def record_trace(inputs:, injected:, outcome:, error:, deviations:)
    call_record = Custom::ScoutV2::Capabilities::CallRecord.new(
      capability: @capability_instance.class.capability_name,
      operation: @operation.name,
      inputs: inputs,
      injected: injected,
      outcome: outcome,
      error: error,
      deviations: deviations
    )

    return unless defined?(OpenTelemetry::Trace)

    span = OpenTelemetry::Trace.current_span
    return unless span&.recording?

    span.set_attribute('langfuse.observation.metadata.capability_call', call_record.to_span_json)
  end
end
