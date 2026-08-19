# Data Model: Scout External REST/Webhook Tool

**Branch**: `045-scout-external-webhook-tool` | **Date**: 2026-08-19 | **Spec**: [spec.md](spec.md)

This feature introduces no new tables and no changes to existing table schemas. It adds one
execution-path entity (in-memory only, never persisted) that operates against an entity already
delivered in prior phases.

## 1. ScoutTool (existing, unchanged)

Table: `ichatr_scout_tools`. Defined in `custom/app/models/scout_tool.rb` (prior phase). Reused
as-is by this feature; no migration is part of this plan.

| Field | Type | Notes (as consumed by this feature) |
|-------|------|--------------------------------------|
| `id` | bigint | Resolved from the LLM-supplied `tool_id` argument |
| `account_id` | bigint | Used to scope resolution (`account.scout_tools`) — never trusted from the LLM directly |
| `name` | string | Surfaced (new, this feature) in `CallCustomApi`'s per-call catalog — see [research.md](research.md) §6 |
| `description` | string | Surfaced (new, this feature) in `CallCustomApi`'s per-call catalog — see [research.md](research.md) §6 |
| `endpoint_url` | string | Used to build the outbound `SafeFetch` request |
| `http_method` | string | Used to select the `SafeFetch` request method (default `POST`) |
| `auth_headers` | jsonb, encrypted (`encrypts`) | Decrypted at call time, merged into outbound request headers, always passed as `sensitive_headers` to `SafeFetch` for log redaction |
| `parameters_schema` | jsonb | Used as the `JSONSchemer` schema to validate the LLM-supplied payload before any network call |
| `enabled` | boolean, default `true` | Gates both tool-catalog visibility (FR-008) and call execution (FR-009) |

No new validations, indexes, or associations are added to this model by this feature.

## 2. Tool Call Result (new, in-memory only)

Represents the outcome of one `call_custom_api` invocation, returned directly to the LLM as the
tool's return value. Not a persisted ActiveRecord entity — it exists only for the duration of one
tool call within `RubyLLM`'s tool-calling loop, matching the return-value contract already used by
every other `Custom::Scout::Tools::*` class (a plain string/hash, not an object).

| Case | Shape returned to LLM | Triggering condition (spec reference) |
|------|------------------------|----------------------------------------|
| Success | External response body (parsed JSON if valid JSON, raw text otherwise) | External call completes within timeout, within size cap, HTTP status considered a success (FR-007) |
| Validation failure | Structured failure string naming the invalid/missing payload fields | Payload fails `parameters_schema` validation (FR-004, FR-005) |
| Timeout / network failure | Structured failure string, generic (no internal detail leaked) | Connect/read timeout exceeded, DNS/connection error (FR-006) |
| Oversized response | Structured failure string, generic | Response body exceeds 1 MB cap (FR-006a) |
| Non-success HTTP status | Structured failure string with error status and reason (`Error: External system returned error status: <status>`) | Endpoint responds within timeout with 4xx/5xx (Edge Cases, research.md §5) |
| Tool not found / not enabled | Structured failure string, generic ("tool unavailable") — deliberately does not distinguish "wrong account" from "disabled" from "never existed" to avoid leaking configuration existence across accounts | `tool_id` doesn't resolve within the calling account's `enabled` `ScoutTool`s (FR-002, FR-008, FR-009) |

No state transitions apply — every invocation is a single independent request/response cycle
(Edge Cases: "each call is independent").

## 3. Relationships

```text
Account 1───* ScoutTool (existing, unchanged)
Scout ──(conversation context)── CallCustomApi tool ──(reads)── Account.scout_tools ──(resolves)── ScoutTool
```

`CallCustomApi` never holds a direct association to `ScoutTool`; it resolves one per invocation
through `account.scout_tools`, scoped by the calling conversation's account (via
`BaseTool#account`), exactly as described in [research.md](research.md) §4. The same scoped query
(`account.scout_tools.where(enabled: true)`) also drives the catalog rendered in `CallCustomApi`'s
overridden `description` (§6), so the "resolvable at call time" set and the "discoverable by the
LLM" set are always identical by construction.
