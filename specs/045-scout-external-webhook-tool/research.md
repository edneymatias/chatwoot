# Research: Scout External REST/Webhook Tool

**Branch**: `045-scout-external-webhook-tool` | **Date**: 2026-08-19 | **Spec**: [spec.md](spec.md)

All items below were `NEEDS CLARIFICATION` candidates in the Technical Context; each is resolved
by an existing, in-repo precedent rather than a new choice, consistent with Constitution
Principle II (Smallest Production-Ready Change).

## 1. HTTP execution mechanism

- **Decision**: Use `SafeFetch.fetch` (`lib/safe_fetch.rb`) to perform the outbound call, exactly
  as `Captain::Tools::HttpTool` (`enterprise/lib/captain/tools/http_tool.rb`) already does for the
  Enterprise Copilot equivalent.
- **Rationale**: `SafeFetch` is the app's centralized outbound-HTTP utility. It already enforces
  the 2s connect / 20s read timeouts and provides a `max_bytes` cap, SSRF protection
  (`ssrf_filter`), and sensitive-header redaction in logs — all of which this feature's
  requirements (FR-006, FR-006a) need. Building a bespoke `Net::HTTP`/`Faraday` call would
  duplicate this and lose the SSRF protection.
- **Alternatives considered**: A hand-rolled `Net::HTTP` call — rejected, it would re-implement
  timeout/size/SSRF handling that `SafeFetch` already solves, and would diverge from the
  established pattern in `Captain::Tools::HttpTool`, violating Constitution Principle III
  (Adhere to Established Conventions).
- **Usage shape** (mirrors `Captain::Tools::HttpTool#execute_http_request`):
  ```ruby
  SafeFetch.fetch(
    scout_tool.endpoint_url,
    method: scout_tool.http_method.downcase.to_sym,
    body: payload.to_json,
    headers: request_headers,
    sensitive_headers: scout_tool.auth_headers.keys,
    max_bytes: 1.megabyte,
    validate_content_type: false
  ) { |result| response_body = result.tempfile.read }
  ```
  `SafeFetch::DEFAULT_OPEN_TIMEOUT` (2) and `SafeFetch::DEFAULT_READ_TIMEOUT` (20) apply
  automatically since `RequestOptions` defaults to them; no explicit override needed.

## 2. Payload schema validation

- **Decision**: Use `JSONSchemer` (already a project dependency, wired via
  `app/models/concerns/json_schema_validator.rb`) to validate the LLM-supplied payload against
  `scout_tool.parameters_schema` before any network call.
- **Rationale**: `JSONSchemer` is already loaded and used elsewhere in the app for exactly this
  purpose (JSON Schema validation of a stored schema against a runtime hash). Reusing it avoids
  adding a new gem dependency for a single feature.
- **Alternatives considered**: Adding a new gem (e.g. `json-schema`) — rejected, redundant with an
  existing dependency. Manual ad hoc key/type checks — rejected, `parameters_schema` is stored as
  an arbitrary JSON Schema document (per `ScoutTool` in prior phases) and deserves proper schema
  semantics (required fields, types, nested objects) rather than a partial reimplementation.
- **Usage shape**:
  ```ruby
  schemer = JSONSchemer.schema(scout_tool.parameters_schema)
  errors = schemer.validate(payload).to_a
  return failure_result(errors) if errors.any?
  ```

## 3. Tool class shape and registration

- **Decision**: `Custom::Scout::Tools::CallCustomApi < Custom::Scout::Tools::BaseTool`, added as a
  sibling file to the five existing native tools, and registered in
  `Custom::Scout::AgentRunner#build_tools` alongside them.
- **Rationale**: Every other native Scout tool (`ManageOpportunity`, `MoveOpportunityStage`,
  `UpdateContact`, `CreatePrivateNote`, `HandoverToHuman`) already follows this exact shape:
  subclass `BaseTool`, get `scout`/`conversation`/`account`/`contact` for free, and are
  instantiated once per `build_tools` call. There is no reason for this tool to differ.
- **Alternatives considered**: A dynamically-instantiated tool per `ScoutTool` row (one `RubyLLM`
  tool object per configured integration) — rejected as unnecessary complexity for this phase; a
  single `call_custom_api(tool_id, payload)` tool that takes the target as an argument (as the
  source spec explicitly names it) is simpler, matches the spec's own naming, and avoids having to
  rebuild the tool list mid-conversation if configurations change.

## 4. Account-scoping enforcement

- **Decision**: Resolve `ScoutTool` via `account.scout_tools.find_by(id: tool_id, enabled: true)`
  (or equivalent account-scoped association), never `ScoutTool.find`.
- **Rationale**: `BaseTool#account` already returns `@conversation.account`, which is available
  for free in every subclass. Scoping the lookup through that association is the only way FR-002
  (no cross-account access) can be structurally guaranteed rather than relying on a runtime check
  after an unscoped lookup.
- **Alternatives considered**: `ScoutTool.find(tool_id)` followed by an `account_id ==` check —
  rejected; scoping the query itself is strictly safer (a missing/mismatched row simply returns
  `nil`, collapsing the "not found" and "wrong account" cases into one code path, which also
  simplifies FR-009's "nonexistent or disabled" handling into a single `nil` check).

## 5. Failure result shape returned to the LLM

- **Decision**: On any failure path (validation, timeout, network error, non-2xx status,
  oversized/malformed body, disabled/missing tool), return a short structured string/hash
  describing the failure category, and log the underlying error via `Rails.logger.error` — mirroring
  `Captain::Tools::HttpTool#perform`'s `rescue StandardError => e` block, which logs and returns
  the string `'An error occurred while executing the request'` rather than re-raising.
- **Rationale**: `RubyLLM::Tool` tool calls are expected to return a value the LLM can reason
  about, not raise; an unhandled exception would abort the whole chat turn. Matching the Copilot
  precedent keeps behavior consistent across the codebase's two independent tool-calling stacks
  (per the spec's Clarifications).
- **Alternatives considered**: Returning full exception messages/stack traces to the LLM —
  rejected, this could leak internal error detail or the target system's error payloads into a
  customer-facing reply; a short, categorized failure string is sufficient for the LLM to decide
  whether to apologize, retry, or hand over.

## 6. Tool discovery / catalog exposure to the LLM

- **Decision**: `Custom::Scout::Tools::CallCustomApi` overrides its own instance-level
  `description` method (not the class-level `description '...'` macro every sibling tool uses) to
  render a per-call catalog of the calling account's currently enabled `ScoutTool`s — id, name,
  description, and `parameters_schema` — so the LLM knows which `tool_id`s exist and what payload
  shape each expects before it ever calls the tool.
- **Rationale**: `RubyLLM::Tool#description` (`ruby_llm-1.15.0/lib/ruby_llm/tool.rb`) is a plain
  instance method that only defaults to the class-level DSL value; nothing prevents a subclass from
  overriding it per instance. `CallCustomApi` is instantiated once per `build_tools` call already
  scoped to the current `@conversation`/account (per §3-4), so it can query
  `account.scout_tools.where(enabled: true)` — the same scoping the tool uses at call time — and
  render the result into its own `description` on every build. This directly satisfies FR-008 ("the
  set of tools offered to the LLM" excludes disabled tools) without touching `AgentRunner`'s
  system-instruction assembly or any other sibling tool, keeping the change fully self-contained to
  one file (Constitution Principle II).
- **Alternatives considered**: Injecting the catalog into `AgentRunner#build_system_instructions`
  instead — rejected, it would spread tool-discovery responsibility across two files instead of one
  and couple `AgentRunner` to `ScoutTool`, which it currently has zero knowledge of. Registering one
  generated `RubyLLM` tool per `ScoutTool` row — already rejected in §3 for the same reasons (avoids
  rebuilding the tool list mid-conversation when configurations change).
