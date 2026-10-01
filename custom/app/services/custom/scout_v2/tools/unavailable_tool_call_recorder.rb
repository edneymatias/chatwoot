# frozen_string_literal: true

# Records a `recorded_tool_calls` entry for a model tool call naming a tool RubyLLM no longer has
# registered — e.g. `Exits::Transition#activate_target` replaced the tool set via
# `TurnScope#replace_with_baseline!` earlier in the same step. `RubyLLM::Chat#execute_tool` returns
# its "unavailable tool" error directly without ever invoking the tool's wrapped `execute`
# (`Custom::Scout::Tools::CallRecorder#wrap_tool`), so that path never records it. `before_tool_call`
# fires for every call RubyLLM is about to make, including one it is about to refuse, so it is the
# only hook that sees the call before RubyLLM silently drops it.
class Custom::ScoutV2::Tools::UnavailableToolCallRecorder
  def self.install!(chat:, recorder:)
    chat.before_tool_call do |tool_call|
      next if chat.tools.key?(tool_call.name.to_sym)

      recorder.recorded_tool_calls << {
        tool_name: tool_call.name,
        arguments: tool_call.arguments,
        simulated: false,
        result: { error: unavailable_tool_error(chat, tool_call.name) }
      }
    end
    chat
  end

  def self.unavailable_tool_error(chat, tool_name)
    "Model tried to call unavailable tool '#{tool_name}'. Available tools: #{chat.tools.keys.to_json}."
  end
end
