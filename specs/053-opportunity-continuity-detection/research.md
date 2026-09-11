# Phase 0 Research: Opportunity Continuity Detection

No `[NEEDS CLARIFICATION]` markers remained in the spec after `/speckit-clarify` (one question was
resolved there, covering the automation-rule decision rule). This document instead records the
codebase-grounding research done during planning — the concrete precedents and existing call sites
the design builds on.

## Decision: One shared resolver service, not two independent implementations

**Decision**: Introduce `Custom::Opportunities::ContinuityResolverService`, called identically by
both `Custom::Scout::Tools::ManageOpportunity#execute` and
`Custom::AutomationRules::ActionService#create_opportunity`.

**Rationale**: Spec FR-008 requires the automation-rule path to apply "the identical continuity
decision rule... not a rule-specific shortcut." The only way to guarantee two call sites stay
identical over time (through future edits, bug fixes, refactors) is to have them call one piece of
code rather than hand-syncing two copies. This also matches Constitution Principle II (smallest
production-ready change / no duplicated logic) and the precedent already named in the source design
doc (`spec75.md`): `Crm::Leadsquared::LeadFinderService` (`app/services/crm/leadsquared/lead_finder_service.rb`)
is an existing example in this codebase of a scoped, single-purpose finder service consumed by
calling code rather than reimplemented at each call site.

**Alternatives considered**:
- *Duplicate the funnel logic in both `ManageOpportunity` and `ActionService`*: rejected — directly
  risks the two paths silently diverging (e.g., one gets a bug fix, the other doesn't), which is
  exactly the "no rule-specific shortcut" failure mode FR-008 exists to prevent.
- *Put the funnel logic directly on the `Opportunity` model as a class method*: rejected — the
  model is a plain ActiveRecord class today (`custom/app/models/opportunity.rb`) with no service-like
  methods; the codebase's established convention for this kind of decision/orchestration logic is a
  dedicated service object under `custom/app/services/custom/...` (see
  `Custom::Scout::OpportunityStageTransitionService` for the closest existing analog — a service
  that wraps a specific `Opportunity` mutation decision).

## Decision: Shared service takes an optional `declared_opportunity_id`, not two code paths

**Decision**: The resolver's public interface accepts `declared_opportunity_id: nil` as an optional
argument. The Scout tool path passes the LLM's declared value (which may be present or absent); the
automation-rule path always omits it (passes nothing / `nil`).

**Rationale**: This is what makes the `/speckit-clarify` resolution (automation path permanently
sits in the "no declared match" branch) fall out naturally from the *same* funnel rather than
requiring a second code path or a boolean flag like `from_automation_rule: true`. Zero candidates →
create in both cases; a validated declared match → reuse (only reachable when the caller supplies
one); anything else with open candidates present → ambiguous. The automation-rule path simply never
exercises the "reuse" branch because it never has a declared id to offer — no special-casing
required in the resolver itself.

**Alternatives considered**:
- *Separate `resolve_for_conversation` / `resolve_for_rule` methods*: rejected — would reintroduce
  exactly the "two implementations that might drift" problem the shared service exists to avoid.

## Decision: Ambiguous outcome is recorded via the existing private-note pattern

**Decision**: The ambiguous branch creates a private message via `Messages::MessageBuilder`, the
same mechanism already used by `Custom::Scout::AgentRunner#perform_fail_safe_handoff`
(`custom/app/services/custom/scout/agent_runner.rb:44-56`, prefixing alerts with `⚠️`) and by
`Custom::Scout::Tools::CreatePrivateNote`.

**Rationale**: Spec75 explicitly calls out this precedent ("mesmo padrão de nota amarela de alerta
já usado no fail-safe"). Both existing call sites already have a `conversation` in scope at the
point the ambiguity is detected: the Scout tool via `BaseTool#conversation`, and
`Custom::AutomationRules::ActionService` via its `@conversation` ivar (populated by the core
`AutomationRules::ActionService` this module is prepended into —
`app/services/automation_rules/action_service.rb`, confirmed via `prepend_mod_with` at that file's
bottom). No new notification/flagging mechanism needs to be built.

**Alternatives considered**:
- *New dedicated `OpportunityAmbiguity` record/table*: rejected — spec's Out of Scope explicitly
  rules out new fields/tables for this; the existing note-based alert channel is already the
  established, humans-already-look-here mechanism (Kanban board + conversation notes), per the
  spec's Assumptions section.

## Decision: Candidate lookup is `Opportunity.where(account_id:, contact_id:, status: :open)`

**Decision**: The resolver scopes strictly by `account_id` and `contact_id`, matching on
`status: :open` (the model's existing `enum status: { open: 0, won: 1, lost: 2 }` in
`custom/app/models/opportunity.rb`). No new scope/column needed.

**Rationale**: Matches the spec's Key Entities definition of "open" and FR-009 (closed deals never
reused). Scoping by `account_id` in addition to `contact_id` follows the "never busca sem escopo"
principle spec75 calls out, and is a defense-in-depth match to how `contact_id` foreign keys are
already scoped per-account elsewhere in this schema.

## Decision: Structured "open deals" context follows the existing funnel-stage pattern

**Decision**: Add a new section to `Custom::Scout::SystemPromptsService#build` (alongside, not
replacing, the existing `context_section`'s `contact.to_llm_text` narrative), listing the contact's
open-deal candidates as `id`, `title`, `pipeline_stage` — structured enough for the assistant to
declare a specific `opportunity_id` back.

**Rationale**: This directly mirrors the existing `funnel_section` (`custom/app/services/custom/scout/system_prompts_service.rb:104-142`),
which already injects structured, ID-bearing pipeline-stage data into the same prompt for the exact
same reason (giving the assistant real IDs to reference in tool calls, e.g. `stage_id`). Reusing
this established pattern is both the smallest change and the most consistent with how the rest of
the system prompt is built.

**Alternatives considered**:
- *Enrich `contact.notes` / `ContactNotesService` output with opportunity pointers*: explicitly
  ruled out by spec's Out of Scope ("Mudança no mecanismo de geração de notas... não é necessário
  enriquecer as notas com ponteiros de Oportunidade").
