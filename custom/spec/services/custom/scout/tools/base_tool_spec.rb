# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::BaseTool do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      enabled: true
    )
  end

  let(:test_tool_class) do
    Class.new(described_class) do
      description 'Sample test tool'
      param :query, type: :string, desc: 'Query parameter'

      def name
        'sample_test'
      end

      def execute(query:)
        raise StandardError, 'Network connection failed' if query == 'fail'

        "Executed with query: #{query}"
      end
    end
  end

  let(:tool) { test_tool_class.new(scout, conversation) }

  describe '#call' do
    context 'when otel is enabled' do
      before do
        allow(ChatwootApp).to receive(:otel_enabled?).and_return(true)
      end

      it 'wraps call in instrument_tool_call with tool name and arguments on success' do
        expect(tool).to receive(:instrument_tool_call).with('sample_test', { query: 'hello' }).and_call_original

        mock_span = instance_double(OpenTelemetry::Trace::Span)
        allow(mock_span).to receive(:set_attribute)
        mock_tracer = instance_double(OpenTelemetry::Trace::Tracer)
        allow(tool).to receive(:tracer).and_return(mock_tracer)
        allow(mock_tracer).to receive(:in_span).with('tool.sample_test').and_yield(mock_span)

        result = tool.call(query: 'hello')
        expect(result).to eq('Executed with query: hello')
      end

      it 'surfaces tool execution failures through instrument_tool_call when tool raises error' do
        expect(tool).to receive(:instrument_tool_call).with('sample_test', { query: 'fail' }).and_call_original

        expect do
          tool.call(query: 'fail')
        end.to raise_error(StandardError, 'Network connection failed')
      end
    end

    context 'when otel is disabled' do
      before do
        allow(ChatwootApp).to receive(:otel_enabled?).and_return(false)
      end

      it 'returns tool result cleanly without invoking tracing' do
        expect(tool).not_to receive(:tracer)
        result = tool.call(query: 'hello')
        expect(result).to eq('Executed with query: hello')
      end
    end
  end
end
