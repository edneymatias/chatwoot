# Phase 0 Research: Scout Audience Targeting

No `NEEDS CLARIFICATION` markers remain in the Technical Context — this feature extends an
already-mature fork module (`custom/` Scout) with well-established patterns, so research here
consolidates verification against the current codebase rather than exploring open technology
choices.

## Validation pass (2026-09-10)

After the decisions below were first drafted, they were independently stress-tested via three
parallel investigations: (1) a full re-audit of every claim against the live codebase (not
memory/docs), (2) a documentation check via context7 for the Rails/`jsonb`, `Module#prepend`, and
Vue 3 `provide`/`inject` assumptions, and (3) a GitHub search for the actual, current upstream
`Captain::AudienceMatcher`/`Enterprise::Conversation`/`Enterprise::Message` implementation this
design was modeled on. That pass found several inaccuracies in the original decisions, corrected
in place below (each affected decision notes what changed and why). Net effect: the audience-gate
placement and the flat-condition-format choice both held up; the "N/A for Enterprise" framing, the
frontend-reuse citation, the controller `permit` sketch, and the top-level fail-open error handling
did not, and are corrected here plus in spec.md/plan.md/data-model.md/contracts/.

## Decision: Condition format — flat list, not nested tree

**Decision**: Represent a Scout's target audience as a flat, ordered array of condition objects
(`{attribute_key, filter_operator, values, query_operator}`), matching the format already used by
`AutomationRules::ConditionsFilterService` (`app/services/automation_rules/conditions_filter_service.rb`)
and by the Kanban/Contacts filter UI (`ConditionRow.vue`).

**Rationale**: Covers every real-world targeting case identified (a list of phone numbers and/or a
label) without building a new nested AND/OR group UI and evaluator. Chatwoot's own Enterprise
Captain feature (`enterprise/app/services/captain/audience_matcher.rb`) uses a nested tree, but
that is read-only prior art under a separate license boundary — not something this fork reuses or
needs to match structurally.

**Alternatives considered**:
- Nested condition tree (groups of AND within OR, depth ≤ 3, mirroring Captain) — rejected: no
  identified use case in this fork needs grouping beyond flat AND/OR sequencing, and it would
  require a new frontend condition-group builder with no existing component to reuse.

## Decision: New isolated `Custom::Scout::AudienceMatcherService`, not a shared module with `AutomationRules::ConditionsFilterService`

**Decision**: Implement matching logic as its own service under `custom/app/services/custom/scout/`,
independent of `AutomationRules::ConditionsFilterService`.

**Rationale**: The operator-matching logic (~40 lines: equality/text/numeric operators) is small
enough that duplicating it is cheaper and safer than extracting a shared module out of
`AutomationRules::ConditionsFilterService`, which is a core OSS file already carrying production
traffic for automation rules. Touching it to extract a shared concern risks an upstream-merge
conflict and a regression in an unrelated, already-stable code path for a small amount of
de-duplication.

**Alternatives considered**:
- Extract shared `ConditionMatching` concern used by both services — rejected per the above
  risk/benefit tradeoff (see Constitution Principle I: prefer isolated, additive fork code over
  edits to shared core files).
- Reuse `AutomationRules::ConditionsFilterService` directly by adapting Scout's condition format to
  its `FilterService`/`ActiveRecord::Base#where` SQL-building approach — rejected: that service is
  built to filter over a DB relation (returns `records.any?`) rather than to evaluate a single
  already-loaded `Contact`/`Conversation` pair in memory, which is what the gate hooks need
  (`determine_conversation_status`/`reopen_resolved_conversation` run on an unpersisted or
  in-memory record during a callback, not a queryable relation).

## Decision: Gate at both `Conversation#determine_conversation_status` and `Message#reopen_resolved_conversation`

**Decision**: Override both hooks via the fork's `custom/` convention, matching the two-gate
pattern already used by Enterprise's Captain assistant
(`Enterprise::Conversation#determine_conversation_status`,
`Enterprise::Message#reopen_resolved_conversation`).

**Rationale**: Verified in the current codebase that `Custom::ScoutListener`
(`custom/app/listeners/...`) only gates *message processing* — after a conversation already exists
and is `pending`. Gating only there, without touching status-determination, would let a
non-matching contact's conversation exist as `pending` while the Scout listener silently declines
to enqueue processing — an abandoned `pending` conversation nobody is working, which the spec's
edge cases and Success Criterion SC-002 explicitly forbid. Verified that neither hook currently has
a Scout-aware override: `custom/app/models/custom/message.rb` only overrides
`mark_pending_conversation_as_open_for_human_response` today; `reopen_resolved_conversation` is
untouched; and there is no `custom/app/models/custom/conversation.rb` file yet (confirmed via
`ls custom/app/models/custom/`).

**Alternatives considered**:
- Gate only inside `Custom::ScoutListener` — rejected: reproduces the exact "abandoned pending
  conversation" bug the feature exists to avoid (see spec Edge Cases and FR-005/FR-006).

**Correction from validation pass — Enterprise coexistence is real, not moot**: the architecture
audit found `ChatwootApp.extensions` (`lib/chatwoot_app.rb`) returns `%w[enterprise custom]`
**unconditionally** whenever `custom?` is true, and `config/application.rb` eager-loads
`enterprise/app/**` regardless of licensing tier. So `Enterprise::Conversation` and
`Enterprise::Message` are real, active, prepended modules on the exact two classes this feature
also extends — this is not a "read-only prior art, not a shared dependency" situation as an
earlier plan.md draft claimed (corrected there too). Two concrete, verified consequences:

1. **Prepend order**: `ChatwootApp.extensions` iterates `['enterprise', 'custom']`, and each
   `prepend` call inserts closer to the front of the ancestor chain than the previous one
   (confirmed via Ruby's `Module.ancestors` documentation — "each subsequent prepend inserts
   closer to the front"). Resulting MRO: `[Custom::Message, Enterprise::Message, Message]` —
   `Custom::Message`/`Custom::Conversation` run **first**, ahead of the Enterprise modules.
2. **`determine_conversation_status` composes safely, `reopen_resolved_conversation` as originally
   sketched does not.** `Enterprise::Conversation#determine_conversation_status` calls `super`
   unconditionally at the top before applying its own logic — the same "always call super, then
   layer your own condition" pattern already proven at `Custom::Inbox#active_bot?`/
   `Enterprise::Inbox#active_bot?` (`super || scout_active?` / `super || captain_active?`). Our
   `Custom::Conversation#determine_conversation_status` override follows this same pattern, so it
   composes correctly with `Enterprise::Conversation` regardless of prepend order. But
   `Enterprise::Message#reopen_resolved_conversation` short-circuits without calling `super` when
   its assistant doesn't engage (`return conversation.open! unless assistant.engages?(...)`), and
   the original sketch for `Custom::Message#reopen_resolved_conversation` copied that exact
   non-cooperative shape. Since `Custom::Message` now runs first in the chain, on any Scout-enabled
   inbox where the contact doesn't match, that short-circuit means `Enterprise::Message`'s own
   check never runs at all *and* core's base-class branch for API-channel inboxes
   (`Current.executed_by = sender if reopened_by_contact?`, `app/models/message.rb:437`) is
   skipped — a real attribution loss, since this fork's own `custom/app/models/opportunity_conversation.rb`
   and `custom/app/models/opportunity.rb` read `Current.executed_by` for Kanban/Opportunity
   activity-log entries. **Fix applied to plan.md**: `Custom::Message#reopen_resolved_conversation`
   must set `Current.executed_by = sender if conversation.inbox.api? && reopened_by_contact?`
   itself before calling `conversation.open!` on the short-circuit branch, preserving the
   attribution the base class would otherwise have set.

## Decision: Narrow, per-condition fail-safe on evaluation errors (not a blanket top-level rescue)

**Original decision (superseded by validation pass)**: `AudienceMatcherService#matches?` wraps the
entire evaluation in `rescue StandardError => e; true` (fail open on any error whatsoever).

**Why this was corrected**: Two independent validation checks flagged this as unsound:
- The GitHub prior-art search retrieved the actual, current
  `enterprise/app/services/captain/audience_matcher.rb` this design was modeled on. It does
  **not** use a blanket top-level rescue. It has narrow, local rescues only around type coercion
  at the leaf level (`rescue ArgumentError, TypeError` around numeric/date comparisons, returning
  `false`/no-match for that one leaf) — and it pairs this with save-time shape validation
  (`Captain::AudienceValidator`, an `ActiveModel::Validator` checking group operators, recursion
  depth, and per-attribute-type allowed operators) so a structurally broken config is rejected
  before it ever reaches the matcher. `engages?` itself has no rescue at all — a genuine bug
  propagates and fails loudly.
- This directly contradicts CLAUDE.md's own "General Guidelines": *"When an impossible or
  misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently
  skipping behavior."* A blanket `rescue StandardError => e; true` does the opposite: a real defect
  in the matcher (a `NoMethodError`, a typo, any programmer error) would be silently and
  *permanently* converted into "this Scout's audience gate is disabled," for as long as the bug
  exists, with only a log line as a trace — a worse failure mode than the one it's meant to guard
  against, and confirmed against real prior art (Grafana's and Twitter/X's documented "fail open"
  patterns both explicitly scope fail-open to transient/external failures, not programmer errors:
  Twitter's `FailOpenPolicy` states *"Always fail open... except for `MisconfiguredFeatureMapFailure`s
  because it's a programmer error and should always fail loudly."*).

**Corrected decision**: No top-level rescue around the whole audience evaluation. Instead:
- An unrecognized `attribute_key`/`filter_operator` simply falls through to "no match" for that
  condition (a `nil`/`false` return, not a raise) — already the design's behavior, unchanged.
- A *recognized* operator whose value can't be meaningfully compared (e.g. `greater_than` against
  a non-numeric string) is caught with a narrow, local rescue at that comparison only, and treated
  as "no match" for that one condition — evaluation of the rest of the audience continues. This is
  FR-007 as corrected in spec.md.
- A genuinely unexpected error (a real bug) is allowed to raise and surface normally, rather than
  being swallowed into "engage everyone."

**Alternatives considered**:
- Blanket top-level fail-open (original decision) — rejected per the above.
- Fail closed on any error (treat as no-match → route to human queue) — still rejected for the same
  reason as before: silently and permanently reduces Scout coverage with no operator signal.
- Add full save-time shape validation matching `Captain::AudienceValidator` — considered but not
  adopted for this phase; the UI is the sole writer of `audience` and always emits well-formed
  conditions, so the value of duplicating Captain's validator here is lower than the cost of
  building and maintaining it. Flagged in data-model.md as a residual, accepted gap (a
  hand-crafted malformed `audience` via direct API access degrades to per-condition non-matches
  rather than being rejected up front) rather than silently ignored.

## Decision: Controller `permit` syntax — follow `automation_rules_controller.rb`, not the source doc's sketch

**Decision**: Permit `audience` as `[:attribute_key, :filter_operator, :query_operator, { values:
[] }]`, matching `app/controllers/api/v1/accounts/automation_rules_controller.rb`'s `conditions:
[:attribute_key, :filter_operator, :query_operator, { values: [] }]`.

**Correction from validation pass**: the source design doc's sketch — `audience: [%i[attribute_key
filter_operator query_operator] + [values: []]]` — was checked against the codebase's own
controller-permit precedents. `scouts_controller.rb` itself only permits flat scalar arrays today
(`follow_up_delays_hours: []`, `required_custom_attribute_definition_ids: []`) — it has no existing
array-of-hashes precedent to follow, contrary to what the source doc assumed (it also incorrectly
assumed `enabled_tools`/`product_catalog` were permitted via `permit` in this controller; the
latter is actually written through a separate nested controller via direct `update!`, bypassing
strong params). The real, working precedent for an array-of-hashes-with-a-nested-array-value in
this codebase is `automation_rules_controller.rb`'s `conditions` permit. The source doc's sketch,
evaluated literally, produces `[[:attribute_key, :filter_operator, :query_operator, {values:
[]}]]` — an array containing one array — which does not permit the intended flat-hash-per-element
shape. Corrected in `contracts/scouts-api.md`.

## Decision: Audience changes apply forward-only (no retroactive re-evaluation)

**Decision**: Per the resolved Clarifications entry in spec.md, an edited target audience only
affects conversations created or reopened after the save; already-pending Scout conversations are
left alone.

**Rationale**: This falls directly out of the two-gate design above — both gates evaluate audience
membership only at the two lifecycle points (`determine_conversation_status` on creation,
`reopen_resolved_conversation` on reopening a resolved conversation). No third gate is introduced
that would re-scan already-pending conversations, which keeps the change additive and avoids the
significantly larger scope of a background re-evaluation job.

## Decision: Frontend reuses `ConditionRow.vue` + `useContactFilterContext()` as-is, scoped to contact attributes only

**Decision**: `ScoutAudienceTab.vue` is a new persistent-config container around the existing
`ConditionRow.vue` component and `useContactFilterContext()` composable
(`app/javascript/dashboard/components-next/filter/contactProvider.js`).

**Correction from validation pass — wrong reuse citation**: the original decision (and the source
design doc it came from) cited `OpportunitiesFilter.vue` as the existing consumer of
`useContactFilterContext()`. The architecture audit found this is factually wrong:
`OpportunitiesFilter.vue` imports a *different* composable, `useOpportunityFilterContext()` from
`./opportunityProvider.js`, exposing deal-specific attributes (status, assignee, pipeline stage,
campaign fields) — not contact attributes. `ConditionRow.vue` itself is provider-agnostic (takes a
`filterTypes` array as a prop; both providers just supply arrays of the same shape), so the reuse
mechanism still works, but the real production precedent for `useContactFilterContext()` is
`ContactsFilter.vue`, confirmed via `grep -rl useContactFilterContext`. Corrected in plan.md.

**Correction from validation pass — `browser_language` is unreachable from this UI**: the audit
also found `useContactFilterContext()` exposes **only** contact attributes — no conversation
attributes at all, and no `browser_language`. The original data-model listed `browser_language`
(a Conversation attribute) as backend-supported, which would have shipped a backend capability
with no way for an admin to actually configure it through the reused UI. Corrected: conversation
attributes (including `browser_language`) are deferred to a future extension that also adds
frontend plumbing for them (see data-model.md, spec.md Assumptions/FR-001). This phase's audience
targeting is contact-attributes-only.

**Rationale**: Verified `ContactsFilter.vue` + `contactProvider.js` already expose every
contact attribute named in the spec (name, email, phone, identifier, country, city, company,
labels, custom attributes, `blocked`). No new attribute or provider code is needed — only a new
container that persists to the Scout via the existing `ScoutAPI` update endpoint instead of
behaving as a transient filter popover. Verified `ScoutDetail.vue` already renders sibling tabs
(`ScoutInboxesTab`, `ScoutProductsTab`, `ScoutKnowledgeTab`, `ScoutFunnelTab`) via the same
`currentTab === '<key>'` pattern this new tab will follow, each with a matching entry in
`scout.routes.js` and four touch points in `ScoutDetail.vue` (`tabIndexMap`, `currentTab`, `tabs`,
`handleTabChanged`'s `routeMap`) — corrected into plan.md's Project Structure, which had
undercounted this as a single-line "register new tab" edit.

**Alternatives considered**: None for the reuse itself — the source design explicitly calls for
reusing these building blocks, and (once the citation was corrected) verification confirmed they
fit without modification, aside from the contact-only scoping above.

**Confirmed via Vue 3 documentation**: `inject()` only resolves through the ancestor chain of the
component tree that called a matching `provide()` — it does not search unrelated trees (per
official Vue 3 docs on Composition API `provide`/`inject`). This is not a problem for our reuse:
like `ContactsFilter.vue`, `ScoutAudienceTab.vue` will call `useContactFilterContext()` itself as
the root of its own subtree (wrapping `ConditionRow.vue` as a child), independent of whatever tree
`ContactsFilter.vue` happens to live in — each consumer sets up its own local provide/inject
scope, so no cross-component-tree sharing is required or assumed.

**Confirmed via Rails documentation**: the planned migration (`add_column :ichatr_scouts,
:audience, :jsonb, null: false, default: []`) produces a genuine per-row PostgreSQL default, not a
shared mutable Ruby object. Separately, Rails' `jsonb`/`json` column type
(`ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb` → `Type::Json`) overrides
`changed_in_place?` to deserialize-and-diff rather than relying on the generic `Mutable` module —
so in-place mutation (`scout.audience << condition; scout.save`) is correctly dirty-tracked and
persists without needing a manual `attribute_will_change!` call, unlike the common Ruby-level
mutable-default footgun this might otherwise resemble.
