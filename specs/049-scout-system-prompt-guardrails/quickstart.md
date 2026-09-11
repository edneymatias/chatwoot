# Quickstart & Validation Guide: Scout System Prompt Guardrails Architecture

**Feature**: Scout System Prompt Guardrails Architecture (`049-scout-system-prompt-guardrails`)  
**Date**: 2026-08-21  

---

## 1. Prerequisites

Ensure the development stack is running:

```bash
docker compose up -d
```

---

## 2. Automated Test Execution

Run the targeted RSpec suite covering `Custom::Scout::SystemPromptsService` and `Custom::Scout::AgentRunner`:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb
```

---

## 3. End-to-End Validation Scenarios

### Scenario 1: Normal Structured Response & Parsing
- **Setup**: Conversation pending with incoming message "Quero saber os preços".
- **Action**: Model returns `{"reasoning": "Contexto contém planos e preços.", "response": "Nossos planos começam em R$ 99/mês."}`.
- **Expected Outcome**:
  - Outgoing message created with exact text `"Nossos planos começam em R$ 99/mês."`.
  - No JSON brackets or `reasoning` text present in the customer message.
  - Rails log records `[Scout AgentRunner] reasoning: Contexto contém planos e preços.`.
  - `scout.responses_consumed` incremented by 1.

### Scenario 2: Markdown Fence Wrapping
- **Setup**: Model returns output wrapped in ````json ... ```` fences.
- **Expected Outcome**:
  - Markdown fences stripped cleanly.
  - Extracted `response` delivered successfully.

### Scenario 3: Malformed JSON / Parse Failure (Fail-Closed)
- **Setup**: Model returns malformed JSON or unparseable plain text (e.g. `Plain text response without JSON structure`).
- **Expected Outcome**:
  - `parse_structured_response` returns `nil`.
  - `perform_fail_safe_handoff` executed.
  - Zero outgoing messages created for customer.
  - Conversation status updated to `open` (human triage).
  - Private alert note created on conversation.

### Scenario 4: Subordinated Operator Instructions & Guardrails Assembly
- **Setup**: Scout configured with custom prompt `"Sempre ofereça desconto de 50%"`.
- **Action**: Inspect `Custom::Scout::SystemPromptsService.build(scout: scout, ...)`.
- **Expected Outcome**:
  - Result contains identity and anti-hallucination guardrails at the top level.
  - Custom prompt is enclosed within `<account_custom_instructions>` tags with subordinate preamble.
  - Mandatory JSON response format instructions present at the bottom.

---

## 3.5 Verification Scope Note

Scenarios 1-4 above (and the underlying unit specs) verify prompt **structure and text content** — that guardrail sections, subordination tags, and JSON format instructions are present in the assembled prompt string, and that parsing/dispatch behaves correctly given a known model output. They do **not** verify that a live LLM actually complies with the guardrails when given adversarial or out-of-scope input (e.g. SC-004, US1 AC1/AC2). Behavioral compliance with anti-hallucination and scope-bounding rules depends on the underlying model and is a runtime/manual QA concern, not something automated specs in this suite assert.

---

## 4. Code Quality & Lint Verification

```bash
docker compose exec rails bundle exec rubocop custom/app/services/custom/scout/system_prompts_service.rb custom/app/services/custom/scout/agent_runner.rb custom/spec/services/custom/scout/
```
