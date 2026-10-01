# frozen_string_literal: true

module Custom::ScoutV2::Capabilities
  ALLOWED_CALL_RECORD_INJECTED_KEYS = %w[
    id_empresa
    id_usuario
    id_convenio
    nr_convenio
    id_origem_pessoa
    id_agenda
    id_servico
    phone
    person_id
  ].freeze

  CallRecord = Data.define(
    :capability,
    :operation,
    :inputs,
    :injected,
    :outcome,
    :error,
    :deviations
  ) do
    def initialize(**attributes)
      raw_injected = attributes[:injected] || {}
      sanitized_injected = raw_injected.select do |k, _|
        ALLOWED_CALL_RECORD_INJECTED_KEYS.include?(k.to_s)
      end.transform_keys(&:to_s)

      super(
        capability: attributes[:capability].to_s,
        operation: attributes[:operation].to_s,
        inputs: attributes[:inputs] || {},
        injected: sanitized_injected,
        outcome: attributes[:outcome].to_s,
        error: attributes[:error],
        deviations: attributes[:deviations] || []
      )
    end

    def to_span_json
      to_h.to_json
    end
  end
end
