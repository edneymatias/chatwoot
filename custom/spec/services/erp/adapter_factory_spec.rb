# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Erp::AdapterFactory do
  describe '.build' do
    it 'raises ArgumentError for unregistered provider' do
      hook = instance_double(Integrations::Hook, app_id: 'unknown_erp')

      expect { described_class.build(hook) }.to raise_error(ArgumentError, 'Unsupported ERP provider: unknown_erp')
    end

    it 'builds Younus adapter conforming to base contract (U7 / A11)' do
      hook = instance_double(Integrations::Hook, app_id: 'younus', settings: { 'token' => 'abc' })

      adapter = described_class.build(hook)
      expect(adapter).to be_a(Erp::Younus::Adapter)
      expect(adapter).to be_a(Erp::BaseAdapter)
    end
  end
end
