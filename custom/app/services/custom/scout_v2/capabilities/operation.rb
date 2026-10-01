# frozen_string_literal: true

module Custom::ScoutV2::Capabilities
  OPERATION_DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

  Operation = Data.define(:name, :inputs, :output) do
    def problems_for(inputs)
      inputs = inputs.transform_keys(&:to_s)
      problems = undeclared_input_problems(inputs)

      self.inputs.each do |input|
        prob = input_validation_problem(input, inputs)
        problems << prob if prob
      end

      problems
    end

    def deviations_for(data)
      case output.shape
      when :record
        record_deviations(data)
      when :list
        list_deviations(data)
      else
        []
      end
    end

    def params_schema
      return nil if inputs.empty?

      properties = {}
      required = []

      inputs.each do |input|
        key = input.name.to_s
        type = input.type == 'date' ? 'string' : input.type
        prop = { 'type' => type }
        prop['description'] = input.description if input.description.present?
        properties[key] = prop
        required << key if input.required
      end

      schema = { 'type' => 'object', 'properties' => properties }
      schema['required'] = required if required.present?
      schema
    end

    private

    def undeclared_input_problems(inputs)
      declared_names = self.inputs.map { |i| i.name.to_s }
      (inputs.keys - declared_names).map do |undeclared|
        "campo '#{undeclared}' não declarado"
      end
    end

    def input_validation_problem(input, inputs)
      key = input.name.to_s
      return "campo '#{key}' ausente" if input.required && (!inputs.key?(key) || inputs[key].nil?)
      return nil unless inputs.key?(key) && !inputs[key].nil?

      validate_input_type(key, input.type, inputs[key])
    end

    def validate_input_type(key, type, val)
      case type
      when 'date'
        "campo '#{key}' deve ser uma data no formato YYYY-MM-DD" unless valid_date?(val)
      when 'string'
        "campo '#{key}' deve ser texto não vazio" unless val.is_a?(String) && val.strip.present?
      end
    end

    def record_deviations(data)
      record = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}
      output.required.filter_map do |req|
        "campo de saída '#{req}' ausente" if record[req.to_s].nil?
      end
    end

    def list_deviations(data)
      items = extract_list_items(data)
      items.each_with_index.flat_map do |item, idx|
        row = item.is_a?(Hash) ? item.transform_keys(&:to_s) : {}
        output.required.filter_map do |req|
          "campo de saída '#{req}' ausente no item #{idx}" if row[req.to_s].nil?
        end
      end
    end

    def extract_list_items(data)
      if data.is_a?(Array)
        data
      elsif data.is_a?(Hash)
        data['slots'] || data[:slots] || []
      else
        []
      end
    end

    def valid_date?(val)
      return false unless val.is_a?(String) && val.match?(OPERATION_DATE_FORMAT)

      Date.iso8601(val)
      true
    rescue ArgumentError
      false
    end
  end

  Operation::Input = Data.define(:name, :type, :required, :description) do
    def initialize(name:, type:, required:, description: nil)
      super(name: name, type: type, required: required, description: description)
    end
  end
  Operation::Output = Data.define(:required, :shape)
end
