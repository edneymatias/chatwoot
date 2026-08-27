# Phase 0 Research: Scout Funnel Stage Qualification Gate

No `NEEDS CLARIFICATION` markers remain in the Technical Context — this feature reuses existing
Rails/RSpec conventions already established in `custom/app/services/custom/scout/`. The decisions
below resolve the design questions the spec intentionally left as "how", not "what" (the "what" was
already settled in `docs/kanban/ciclo 10/scout/09-required-qualification-attributes/spec74.md` and
in the `/speckit-clarify` session recorded in `spec.md`).

## 1. Where the funnel information is injected into the prompt

**Decision**: Add a new private `funnel_section` method to `Custom::Scout::SystemPromptsService`
and include it in the `sections` array inside `#build`, following the same additive,
`compact`-tolerant pattern already used for `identity_section` / `guardrails_section` (Fase 08).
For each stage, include `PipelineStage#description` when present; for each required attribute
(stage-specific or Scout-global), include `CustomAttributeDefinition#attribute_description` when
present — both rendered as an extra line under the stage/attribute rather than a separate section,
and simply skipped (not rendered as an empty line) when blank.

**Rationale**: The service already establishes the convention of one section per concern, each
returning `nil` when its underlying config is absent (see `context_section`'s
`return nil if parts.empty?`) so that `sections.compact.join(...)` naturally omits it. Reusing this
exact shape means FR-014 (omit guidance when unconfigured) falls out for free from the existing
pattern rather than requiring new conditional plumbing in `AgentRunner`. Both description fields
already exist and are already operator-editable (`PipelineStage#description` via the funnel stage
description editor, `CustomAttributeDefinition#attribute_description` via the standard custom
attribute form, the same field already surfaced to the LLM for custom tool parameters per spec
051) — surfacing them here is a natural extension of a pattern the codebase already trusts for
telling an LLM what a field means, not a new concept.

**Alternatives considered**: A standalone service/class dedicated to building the funnel text —
rejected because it would fragment the single-class, single-`build`-method prompt assembly
convention this module has followed since Fase 08 for no added benefit (the funnel section has the
same dependencies — `scout` and `scout.account` — as the rest of the class already has access to).

## 2. Extracting reusable handoff logic

**Decision**: Move the four responsibilities currently private to
`Custom::Scout::Tools::HandoverToHuman` (team/assignee assignment, conditional `bot_handoff!`,
conditional transfer note, conditional contact memory) into a new
`Custom::Scout::HandoffService.new(scout:, conversation:).perform(assignee_id: nil, team_id: nil, reason: nil)`.
`HandoverToHuman#execute` becomes a thin wrapper that calls the service and still sets its own
`@handoff_executed = true` (tool-level flow state consumed by `AgentRunner#process_response`, not
domain state, so it stays on the tool).

**Rationale**: Once `OpportunityStageTransitionService` also needs to trigger a handoff on
qualification, there are two real callers — extraction is justified by actual reuse, not
speculation (Constitution Principle II).

**Alternatives considered**: Duplicating the four steps inside the new transition service —
rejected; two independently-maintained copies of team/bot_handoff!/note/memory logic would drift
(e.g. one gets a bugfix, the other doesn't) and directly contradicts the "single enforcement point"
goal (FR-008) the same feature is introducing for stage-change checks.

## 3. Single enforcement point for stage changes

**Decision**: Introduce
`Custom::Scout::OpportunityStageTransitionService.new(scout:, conversation:, opportunity:).call(stage_id:)`
as the only path that assigns `opportunity.pipeline_stage_id` and saves it from Scout tool code.
`MoveOpportunityStage#execute` delegates to it entirely; `ManageOpportunity#update_opportunity`
delegates to it only when `stage_id` is present (otherwise keeps its existing `save!`).

**Rationale**: FR-008 requires that no Scout capability can bypass the qualification/required-field
checks enforced by another. A single call site is the simplest way to guarantee that structurally
(there is nowhere else stage_id assignment happens), rather than relying on both tools
independently remembering to run the same two checks.

**Alternatives considered**: A shared private helper module mixed into both tool classes —
rejected; a service object composes more naturally with the tool's existing "resolve dependencies
via constructor, then perform" style already used by `HandoffService`, `ContactNotesService`, etc.
in this codebase, and avoids coupling the check to the `RubyLLM::Tool` base class.

**External validation (2026-08-27)**: A GitHub code search turned up that Chatwoot's own upstream
codebase already establishes this exact "thin `RubyLLM::Tool` + delegate to a service object"
convention in its Captain module — `enterprise/app/services/captain/tools/base_tool.rb` defines
`Captain::Tools::BaseTool < RubyLLM::Tool`, and concrete tools (e.g. a Linear-issue-search tool, a
get-contact tool) declare thin `param`/`description` schemas and delegate the actual work to
service objects inside `execute` (e.g. `Integrations::Linear::ProcessorService.new(...)`). This is
not a convention invented for this feature — it mirrors a pattern the upstream project itself
already relies on for the same category of problem (an LLM tool needing non-trivial domain logic).

## 4. Detecting "actually entered the qualified stage" for one-time handoff (per `/speckit-clarify`)

**Decision**: After a successful `opportunity.save`, check whether the stage actually changed using
Rails' post-save dirty-tracking (`opportunity.saved_change_to_pipeline_stage_id?`) before deciding
whether to invoke `HandoffService`. Only fire the handoff when that returns `true` **and** the new
`pipeline_stage_id` equals `scout.qualified_stage_id`.

**Rationale**: `saved_change_to_<attribute>?` is the idiomatic ActiveRecord way to answer "did this
attribute's value actually change on the save that just happened," already used elsewhere in Rails
apps for this exact class of problem, and requires no extra instance-variable bookkeeping in the
service. It directly implements the clarified behavior: a redundant call that re-targets the
already-current qualified stage will find `saved_change_to_pipeline_stage_id?` false (no attribute
change occurred), so no handoff fires — while resulting in a normal, message-compatible success
return.

**Alternatives considered**: Comparing `opportunity.pipeline_stage_id` before assignment to the
target `stage.id` — functionally equivalent, but requires capturing the "before" value in a local
variable before mutating the record, which is marginally more error-prone than relying on Rails'
built-in dirty-tracking that already exists post-save.

**External validation (2026-08-27)**:
- **Strongest evidence — same class, already in production**: `Opportunity` itself already declares
  `after_update :record_subsequent_stage_change, if: :saved_change_to_pipeline_stage_id?`
  (`custom/app/models/opportunity.rb:30`) to fire a side effect only on an actual stage transition.
  This isn't just an idiomatic Rails pattern in the abstract — it's the pattern this exact model
  already uses for this exact attribute, for the same conceptual reason.
- **Rails docs (via context7, Rails 7.2.2.1 — closest indexed version to this repo's locked
  `7.1.5.2`; the dirty-tracking mechanism, `mutations_before_last_save`/`changes_applied`, is
  unchanged across that range)**: confirms `saved_change_to_attribute?` is populated immediately
  after `save` returns — usable outside an `after_*` callback, not only inside one — and that if
  `save` fails validation, `changes_applied` never runs, so the check correctly evaluates to
  `false` (no handoff fires on a failed save, matching this feature's requirement).
- **GitHub-wide precedent**: the same idiom (`saved_change_to_<attr>?` gating a
  notification/webhook/handoff) appears throughout Chatwoot's own upstream codebase —
  `app/models/conversation.rb#notify_status_change` (gates `CONVERSATION_OPENED`/
  `CONVERSATION_RESOLVED` event dispatch), `enterprise/app/models/enterprise/conversation.rb`
  (SLA completion), `enterprise/app/models/captain/document.rb`, `enterprise/app/models/
  enterprise/message.rb` — plus multiple unrelated Rails projects (e.g. `redmine/redmine`). This is
  a canonical, widely-trusted idiom, not an edge-case technique.

## 5. Language/format of rejection messages returned to the agent

**Decision**: Return plain, hardcoded English strings from `OpportunityStageTransitionService`
(e.g. `"Cannot move to the qualified stage. Missing required fields: Budget, Company Size."`),
resolving `attribute_key` → `attribute_display_name` via `CustomAttributeDefinition`, matching the
existing return-value convention.

**Rationale**: Existing tool return strings already consumed by the LLM
(`"Opportunity moved to stage #{stage.name} successfully."` in the current
`MoveOpportunityStage`, `"Pipeline stage not found."`, etc.) are plain hardcoded English with no
`I18n.t` call — this is text fed into the model's reasoning context, not a Vue-rendered end-user
string, so the project's `en.yml`/`pt_BR.yml` synchronous-translation convention (which governs
user-facing UI strings) does not apply here. There is no existing precedent in this module for
localizing tool-result text.

**Alternatives considered**: Localizing via `I18n.t` keyed off the contact's or account's locale —
rejected; no existing tool in this module does this, and it would require picking an authoritative
locale source with no current basis in the code, for a channel (LLM tool-result text) the prospect
never sees verbatim.

**External validation (2026-08-27)**: A fresh scan of `custom/app/services/custom/scout/tools/`
confirms zero `I18n.t` calls anywhere in that directory — the "no localized tool-result precedent"
claim above is not an assumption, it holds against the current code as of this validation pass.

## 6. Removing an existing tool parameter (`lost_reason`) is safe

**Decision**: Removing `lost_reason` from `move_opportunity_stage`'s `param` declarations (and the
branch that used it) requires no migration/versioning/deprecation step on the `RubyLLM::Tool` side.

**Rationale (validated via context7 against the `crmne/ruby_llm` gem docs)**: a tool's JSON schema
is derived dynamically from its class definition (`param`/`description` declarations, or inferred
from `execute`'s signature) every time it's introspected — the gem has no concept of a
"registered"/versioned tool contract to migrate. `execute` may return either a plain `String` or a
`Hash`/`Array` (auto-serialized to JSON); this feature keeps returning plain strings, matching
every other tool in this module today.

## Summary: validation spike (2026-08-27)

Before proceeding to Phase 1, all decisions above were independently checked by three research
passes: (1) re-reading the actual current code in this repository plus the `develop` branch (the
best locally-available upstream reference, given no `upstream` git remote is configured in this
clone) for conformance and naming collisions; (2) official documentation for `RubyLLM::Tool` and
Rails/ActiveRecord dirty-tracking via `context7`; (3) real-world code search (`gh_grep`) across
GitHub, including the actual `chatwoot/chatwoot` upstream repository. Results, beyond what's cited
inline above:

- No naming collisions: neither `handoff_service.rb` nor `opportunity_stage_transition_service.rb`
  exists yet under `custom/app/services/custom/scout/`.
- The proposed `.new(scout:, conversation:, ...)` keyword-argument constructor style for the two new
  services matches the existing convention in `AgentRunner`, `SystemPromptsService`, and
  `PlaygroundRunner` in the same directory — not a new style being introduced.
- No RuboCop complexity risk identified in the proposed branching (simple, shallow conditionals).
- The `develop` branch (upstream mirror, dated 2026-07-29) has no `PipelineStage`/`Opportunity`/
  pipeline-CRM concept at all; its only "CRM" code (`app/services/crm/`) is an outbound sync
  connector to external CRMs (Leadsquared today, Hubspot planned) gated by an `Integrations::Hook`
  and a `crm_integration` feature flag — an orthogonal concept with no structural overlap or future
  merge-conflict risk with this feature's fork-specific funnel/pipeline domain.

No decision in this document required revision as a result of this spike.
