# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Capabilities::CallRecord do
  subject(:record) do
    described_class.new(
      capability: 'scheduling',
      operation: 'book',
      inputs: { 'slot_id' => '2026-10-15T14:30:00-03:00', 'notes' => 'prefere manhã' },
      injected: { 'id_empresa' => 1041, 'id_agenda' => 1, 'id_servico' => 1, 'person_id' => '123' },
      outcome: 'ok',
      error: nil,
      deviations: []
    )
  end

  describe '#to_span_json' do
    it 'serializes the call record fields to JSON' do
      json = JSON.parse(record.to_span_json)
      expect(json['capability']).to eq('scheduling')
      expect(json['operation']).to eq('book')
      expect(json['inputs']).to eq({ 'slot_id' => '2026-10-15T14:30:00-03:00', 'notes' => 'prefere manhã' })
      expect(json['injected']).to eq({ 'id_empresa' => 1041, 'id_agenda' => 1, 'id_servico' => 1, 'person_id' => '123' })
      expect(json['outcome']).to eq('ok')
      expect(json['error']).to be_nil
      expect(json['deviations']).to eq([])
    end

    it 'never contains token in #to_span_json' do
      secret_token = 'secret-token-xyz'
      rec = described_class.new(
        capability: 'customer_registry',
        operation: 'find_by_phone',
        inputs: {},
        injected: { 'id_empresa' => 1041, 'phone' => '11999990000' },
        outcome: 'ok',
        error: nil,
        deviations: []
      )
      serialized = rec.to_span_json
      expect(serialized).not_to include(secret_token)
      expect(JSON.parse(serialized)['injected']).not_to have_key('token')
    end
  end
end
