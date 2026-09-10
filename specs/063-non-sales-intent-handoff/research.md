# Phase 0 Research: Non-Sales Intent Recognition and Immediate Handoff

No `NEEDS CLARIFICATION` markers remain in the Technical Context — the source phase document
(`docs/kanban/ciclo 10/scout/23-non-sales-intent-immediate-handoff/spec86.md`) already made every
design decision needed to implement this feature, and `/speckit-clarify` found no additional
ambiguity. This document records those decisions in Decision/Rationale/Alternatives form for
traceability.

## Decision 1: Where the guardrail lives

**Decision**: Add one new bullet to `Custom::Scout::SystemPromptsService#guardrails_section`
(`custom/app/services/custom/scout/system_prompts_service.rb`), inserted immediately after the
existing `- Fallback para humano: ...` bullet.

**Rationale**: `guardrails_section` is the single fixed block of safety/behavior rules injected
into every Scout system prompt regardless of account. Placing the new rule right after "Fallback
para humano" keeps semantically related handoff triggers adjacent, matching how the file already
groups related bullets (e.g. contact-identity guardrail referencing the handoff-precedence rule
inline).

**Alternatives considered**:
- A separate new prompt section — rejected: source doc explicitly calls for a guardrail bullet,
  not a new section; an isolated section would fragment handoff logic across two places for no
  benefit.
- A code-level classifier (mirroring `ActionClassifierService`) — rejected: source doc explicitly
  designed this as proactive, judgment-based prompt guidance, distinct from and complementary to
  the existing reactive classifier (Fase 12), which must remain unchanged.

## Decision 2: Handoff trigger is judgment-based, not mechanical

**Decision**: The guardrail instructs Scout to decide based on what the contact says in the
conversation. No code path automatically triggers handoff purely from an external system's
customer-status response.

**Rationale**: Evaluated and explicitly rejected by the operator in the source doc: an ERP
"is this phone already a customer" signal cannot safely gate handoff on its own, because a contact
with a completed treatment may legitimately be returning to purchase again (a valid new
prospecting case). Only the human-judgment-equivalent (the LLM reading the conversation) can
distinguish that from a genuine non-prospecting need.

**Alternatives considered**:
- Mechanical/automatic handoff triggered by ERP status lookup — rejected per source doc Decision
  #1 and explicitly listed as out of scope.

## Decision 3: External status tool is optional reinforcement only

**Decision**: The guardrail text also tells Scout that if an external customer/treatment-status
tool is configured for the account (via the existing generic `Custom::Scout::Tools::CallCustomApi`
/ `ScoutTool` mechanism from Fase 04) and the contact's phone number is available, Scout may
consult it to reinforce a handoff decision already suggested by the conversation — but its absence
or a non-positive result never blocks or delays the handoff.

**Rationale**: `Custom::Scout::Tools::CallCustomApi` already exposes any operator-configured
`ScoutTool` dynamically in the tool description the LLM reads — a status-check tool needs zero new
code, only an operator registering it via the existing "Ferramentas" (Tools) account UI. Making
this reinforcement optional (rather than required) keeps the feature working identically for
accounts that never configure such a tool.

**Alternatives considered**:
- A new native Rails tool purpose-built for customer-status lookups — rejected: redundant with the
  already-generic `CallCustomApi` mechanism; would violate the "no new tool" constraint from the
  source doc and Constitution Principle II (Smallest Production-Ready Change).
- Making the external lookup mandatory before handoff — rejected explicitly per source doc
  Decision #2 and Acceptance Criteria: absence of the tool, or a non-positive result, must never
  block handoff when the contact's own words already signal non-prospecting intent.

## Decision 4: Existing reactive safety net is untouched

**Decision**: `Custom::Scout::ActionClassifierService` (`out_of_scope_commercial_request`,
opt-in via `@scout.feature_response_auditor?`) receives no code change in this feature.

**Rationale**: It is a complementary, reactive (post-generation) safety net that already handles a
narrower slice of the same problem space. The new proactive guardrail is expected to reduce how
often the reactive layer needs to act, but source doc Decision #4 is explicit that it is not
replaced — same two-layer pattern (primary mechanism + audit safety net) already used elsewhere in
Scout.

**Alternatives considered**:
- Removing or narrowing `ActionClassifierService` now that the proactive rule exists — rejected:
  explicitly out of scope per source doc; the two mechanisms serve different points in the
  request/response cycle (before vs. after generation) and neither subsumes the other with
  certainty.

## Decision 5: Verification approach

**Decision**: Verify with (a) one new RSpec example in
`custom/spec/services/custom/scout/system_prompts_service_spec.rb` asserting the new bullet's
presence/key phrase in `guardrails_section`, and (b) a manual behavioral replay via
`Custom::Scout::PlaygroundRunner` for representative non-prospecting conversations (existing
customer, ongoing treatment, "just a quick question" triage answer), confirming the final response
calls `handover_to_human` without attempting to resolve the request.

**Rationale**: Matches the verification pattern already used for every other guardrail addition in
this file (unit assertion on prompt text) plus the same manual-replay pattern the source doc's
Tests section calls for, and that prior Scout phases (e.g. `049-scout-system-prompt-guardrails`)
already establish as the project convention for prompt-only changes that can't be fully verified by
a unit test alone (LLM behavior depends on the live model, not just the prompt string).

**Alternatives considered**:
- Unit test only, no behavioral replay — rejected: a passing string-presence assertion does not
  prove the LLM actually changes behavior; the source doc's own Tests section calls for both.
- New end-to-end automated conversation test — rejected as disproportionate for a prompt-text-only
  change with no new code path; consistent with Constitution Principle II and the "avoid writing
  specs unless explicitly asked" project convention beyond what's already planned.
