# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Capabilities::Operation do
  describe 'value object structure' do
    it 'defines Input and Output data structures' do
      expect(described_class::Input.members).to include(:name, :type, :required, :description)
      input = described_class::Input.new(name: 'date', type: 'date', required: true, description: 'data')
      expect(input.name).to eq('date')
      expect(input.type).to eq('date')
      expect(input.required).to be true
      expect(input.description).to eq('data')

      output = described_class::Output.new(required: %w[slot_id starts_at], shape: :list)
      expect(output.required).to eq(%w[slot_id starts_at])
      expect(output.shape).to eq(:list)
    end
  end

  describe '#problems_for' do
    let(:inputs) do
      [
        described_class::Input.new(name: 'date', type: 'date', required: true),
        described_class::Input.new(name: 'service', type: 'string', required: false)
      ]
    end
    let(:output) { described_class::Output.new(required: %w[slot_id starts_at], shape: :list) }
    let(:operation) { described_class.new(name: 'list_slots', inputs: inputs, output: output) }

    it 'returns empty array when inputs are valid' do
      expect(operation.problems_for({ 'date' => '2026-10-15', 'service' => 'consulta' })).to eq([])
    end

    it 'allows valid past dates because it checks types and format, not business rules' do
      expect(operation.problems_for({ 'date' => '2020-01-01' })).to eq([])
    end

    it 'permits omitting optional inputs' do
      expect(operation.problems_for({ 'date' => '2026-10-15' })).to eq([])
    end

    it 'flags missing required input' do
      problems = operation.problems_for({})
      expect(problems).to include("campo 'date' ausente")
    end

    it 'flags nil required input as missing' do
      problems = operation.problems_for({ 'date' => nil })
      expect(problems).to include("campo 'date' ausente")
    end

    it 'flags invalid date format or calendar date' do
      problems = operation.problems_for({ 'date' => 'not-a-date' })
      expect(problems).to include("campo 'date' deve ser uma data no formato YYYY-MM-DD")

      invalid_day = operation.problems_for({ 'date' => '2026-02-31' })
      expect(invalid_day).to include("campo 'date' deve ser uma data no formato YYYY-MM-DD")
    end

    it 'flags empty string for string input' do
      problems = operation.problems_for({ 'date' => '2026-10-15', 'service' => '' })
      expect(problems).to include("campo 'service' deve ser texto não vazio")
    end

    it 'flags undeclared inputs' do
      problems = operation.problems_for({ 'date' => '2026-10-15', 'idEmpresa' => 1041 })
      expect(problems).to include("campo 'idEmpresa' não declarado")
    end
  end

  describe '#deviations_for' do
    context 'when output shape is :record' do
      let(:output) { described_class::Output.new(required: %w[appointment_id starts_at], shape: :record) }
      let(:operation) { described_class.new(name: 'book', inputs: [], output: output) }

      it 'returns empty array when all required fields are present' do
        data = { 'appointment_id' => '123', 'starts_at' => '2026-10-15T14:30:00-03:00' }
        expect(operation.deviations_for(data)).to eq([])
      end

      it 'returns deviations when a required field is missing or nil' do
        data = { 'starts_at' => '2026-10-15T14:30:00-03:00' }
        expect(operation.deviations_for(data)).to include("campo de saída 'appointment_id' ausente")
      end
    end

    context 'when output shape is :list' do
      let(:output) { described_class::Output.new(required: %w[slot_id starts_at], shape: :list) }
      let(:operation) { described_class.new(name: 'list_slots', inputs: [], output: output) }

      it 'returns empty array when empty list or all items have required fields' do
        expect(operation.deviations_for({ 'slots' => [] })).to eq([])
        expect(operation.deviations_for([])).to eq([])

        data = [{ 'slot_id' => '1', 'starts_at' => '2026-10-15T09:00:00-03:00' }]
        expect(operation.deviations_for(data)).to eq([])
      end

      it 'returns deviations when any element in the list is missing a declared required field' do
        data = [
          { 'slot_id' => '1', 'starts_at' => '2026-10-15T09:00:00-03:00' },
          { 'slot_id' => '2' }
        ]
        expect(operation.deviations_for(data)).to include("campo de saída 'starts_at' ausente no item 1")
      end
    end
  end

  describe '#params_schema' do
    it 'returns nil when inputs are empty' do
      operation = described_class.new(name: 'no_inputs', inputs: [], output: described_class::Output.new(required: [], shape: :record))
      expect(operation.params_schema).to be_nil
    end

    it 'builds json schema with properties and required array' do
      inputs = [
        described_class::Input.new(name: 'date', type: 'date', required: true),
        described_class::Input.new(name: 'notes', type: 'string', required: false)
      ]
      operation = described_class.new(name: 'test_op', inputs: inputs, output: described_class::Output.new(required: [], shape: :record))

      schema = operation.params_schema
      expect(schema['type']).to eq('object')
      expect(schema['required']).to eq(['date'])
      expect(schema.dig('properties', 'date', 'type')).to eq('string')
      expect(schema.dig('properties', 'notes', 'type')).to eq('string')
    end

    it 'includes input descriptions in properties when present' do
      inputs = [
        described_class::Input.new(name: 'date', type: 'date', required: true, description: 'data no formato YYYY-MM-DD'),
        described_class::Input.new(name: 'service', type: 'string', required: false, description: 'nome do serviço desejado, apenas informativo'),
        described_class::Input.new(name: 'notes', type: 'string', required: false)
      ]
      operation = described_class.new(name: 'test_op', inputs: inputs, output: described_class::Output.new(required: [], shape: :record))

      schema = operation.params_schema
      expect(schema.dig('properties', 'date', 'description')).to eq('data no formato YYYY-MM-DD')
      expect(schema.dig('properties', 'service', 'description')).to eq('nome do serviço desejado, apenas informativo')
      expect(schema.dig('properties', 'notes')).not_to have_key('description')
    end
  end
end
