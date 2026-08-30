# frozen_string_literal: true

module Custom::Scout::Tools::CallRecorder
  def recorded_tool_calls
    @recorded_tool_calls ||= []
  end

  def wrap_tool(tool, simulated: false)
    original_execute = tool.method(:execute)
    runner = self

    tool.define_singleton_method(:execute) do |**args|
      runner.send(:execute_and_record, tool.name, original_execute, args, simulated: simulated)
    end

    tool
  end

  private

  def execute_and_record(tool_name, original_execute, args, simulated: false)
    call_record = { tool_name: tool_name, arguments: args, simulated: simulated }
    begin
      result = original_execute.call(**args)
      call_record[:result] = result
      result
    rescue StandardError => e
      call_record[:error] = e.message
      raise e
    ensure
      recorded_tool_calls << call_record
    end
  end
end
