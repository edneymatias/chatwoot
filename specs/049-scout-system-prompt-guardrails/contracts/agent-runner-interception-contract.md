# Contract: AgentRunner Interception & Structured Parsing

**Feature**: Scout System Prompt Guardrails Architecture (`049-scout-system-prompt-guardrails`)  
**Service**: `Custom::Scout::AgentRunner`  
**Location**: `custom/app/services/custom/scout/agent_runner.rb`

---

## 1. Pipeline Interception Contract

All LLM response processing in `AgentRunner` flows strictly through `process_response`:

```ruby
def process_response(response, handover_tool)
  return if handover_tool.handoff_executed
  return unless conversation_pending?

  parsed = parse_structured_response(response&.content)
  if parsed.blank?
    perform_fail_safe_handoff('Falha ao interpretar resposta estruturada do modelo.')
    return
  end

  dispatch_outgoing_reply(parsed[:response])
end
```

---

## 2. Structured Response Parsing Specification

```ruby
def parse_structured_response(content)
  return if content.blank?

  sanitized = content.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  json = JSON.parse(sanitized)
  return if json['response'].blank?

  Rails.logger.info "[Scout AgentRunner] reasoning: #{json['reasoning']}"
  { response: json['response'] }
rescue JSON::ParserError
  nil
end
```

### Parsing Rules

1. **Markdown Fence Sanitization**: Any leading ````json` or ```` and trailing ```` markdown fences must be cleanly removed before parsing.
2. **Missing Key Validation**: If `json['response']` is absent or whitespace-only, the method returns `nil`.
3. **Observability**: `json['reasoning']` is logged at `info` level (`[Scout AgentRunner] reasoning: ...`).
4. **Exception Handling**: Rescues `JSON::ParserError` and returns `nil`.

---

## 3. Dispatch & Handoff Signatures

```ruby
# Dispatches outgoing customer-facing message
def dispatch_outgoing_reply(reply_content)
  params = { content: reply_content, message_type: 'outgoing', private: false }
  Messages::MessageBuilder.new(nil, @conversation, params).perform

  @scout.with_lock do
    @scout.update!(responses_consumed: @scout.responses_consumed + 1)
  end
end
```

- If `parse_structured_response` returns `nil`:
  - `perform_fail_safe_handoff('Falha ao interpretar resposta estruturada do modelo.')` is called.
  - Conversation status is set to `open` (human queue).
  - Private note is created alerting that AI was paused.
  - No outgoing message is sent to the customer.
