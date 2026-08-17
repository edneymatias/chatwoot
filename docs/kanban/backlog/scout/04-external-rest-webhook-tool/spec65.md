# Phase 04 — External REST/Webhook Tool

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §9.3, §10
**Depends on**: Phase 01 (`ScoutTool` model), Phase 02 (`Scout::AgentRunner`/tool-calling loop),
Phase 03 (encryption must be resolved before `auth_headers` is populated in production).

## Goal

Let a Scout call arbitrary externally-configured REST APIs/webhooks (ERP stock lookups, custom
integrations) as an LLM tool, without any code change per integration.

## Scope

- `call_custom_api(tool_id, payload)` native tool: resolves a `ScoutTool` by id, builds the HTTP
  request (`endpoint_url`, `http_method`, decrypted `auth_headers`), validates `payload` against
  `parameters_schema`, executes the call, and returns the response to the LLM as tool output.
- Timeout and error handling: a failing/timing-out external call must return a structured error to
  the LLM (so it can inform the user or retry-once), not raise and crash the turn.
- `enabled` flag on `ScoutTool` respected — disabled tools are excluded from the tool list passed
  to `ruby_llm`.

## Out of scope

- No UI for creating/editing `ScoutTool` records — Phase 05.
- No retry queues, circuit breakers, or webhook signature verification beyond what
  `parameters_schema` validation covers — YAGNI unless a concrete integration needs it.

## Acceptance criteria

- A configured `ScoutTool` can be invoked by the LLM mid-conversation and its response fed back
  into the conversation.
- A malformed payload (fails `parameters_schema`) or a timing-out endpoint produces a tool-error
  result the LLM can react to, without crashing `Scout::AgentRunner`.
- A disabled `ScoutTool` is never offered to the LLM.
