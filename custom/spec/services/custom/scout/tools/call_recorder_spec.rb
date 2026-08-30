# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::CallRecorder do
  let(:dummy_class) do
    Class.new do
      include Custom::Scout::Tools::CallRecorder
    end
  end
  let(:instance) { dummy_class.new }

  let(:sample_tool_class) do
    Class.new do
      attr_reader :name

      def initialize(name = 'sample_tool')
        @name = name
      end

      def execute(query:, flag: false)
        raise StandardError, 'Execution exploded' if query == 'fail'

        "Result: #{query}, flag: #{flag}"
      end
    end
  end

  let(:tool) { sample_tool_class.new }

  describe '#wrap_tool' do
    it 'records successful tool execution with tool_name, arguments, simulated, and result' do
      wrapped = instance.wrap_tool(tool, simulated: true)
      result = wrapped.execute(query: 'test', flag: true)

      expect(result).to eq('Result: test, flag: true')
      expect(instance.recorded_tool_calls).to eq(
        [
          {
            tool_name: 'sample_tool',
            arguments: { query: 'test', flag: true },
            simulated: true,
            result: 'Result: test, flag: true'
          }
        ]
      )
    end

    it 'records failed tool execution with error, omits result key, and propagates the exception' do
      wrapped = instance.wrap_tool(tool, simulated: false)

      expect do
        wrapped.execute(query: 'fail', flag: false)
      end.to raise_error(StandardError, 'Execution exploded')

      expect(instance.recorded_tool_calls).to eq(
        [
          {
            tool_name: 'sample_tool',
            arguments: { query: 'fail', flag: false },
            simulated: false,
            error: 'Execution exploded'
          }
        ]
      )
      expect(instance.recorded_tool_calls.first).not_to have_key(:result)
    end

    it 'uses the simulated flag supplied by the caller' do
      wrapped_simulated = instance.wrap_tool(sample_tool_class.new('tool_a'), simulated: true)
      wrapped_real = instance.wrap_tool(sample_tool_class.new('tool_b'), simulated: false)

      wrapped_simulated.execute(query: 'ok')
      wrapped_real.execute(query: 'ok')

      expect(instance.recorded_tool_calls.map { |c| c[:simulated] }).to eq([true, false])
    end
  end
end
