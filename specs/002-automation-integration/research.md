# Phase 0 Research: Automation Integration — Create Opportunity Action

## Decision: Extension seam for `AutomationRules::ActionService`

**Decision**: Add exactly one line, `AutomationRules::ActionService.prepend_mod_with('AutomationRules::ActionService')`,
at the bottom of `app/services/automation_rules/action_service.rb`, and implement
`create_opportunity(params)` inside a new `module Custom::AutomationRules::ActionService` at
`custom/app/services/custom/automation_rules/action_service.rb`.

**Rationale**: Confirmed by reading the current file
(`app/services/automation_rules/action_service.rb`) — it has no `prepend_mod_with`/
`include_mod_with` call today, unlike `AutomationRule` (`app/models/automation_rule.rb`, ends with
`prepend_mod_with('AutomationRule')`) and `Contact` (extended via `include_mod_with('Concerns::Contact')`
already wired in Phase 1). `ChatwootApp.extensions` already returns `%w[enterprise custom]` when
`custom/` exists (`lib/chatwoot_app.rb`), so `prepend_mod_with` will correctly resolve
`Custom::AutomationRules::ActionService` with no further core wiring needed. This is the single
core-file edit called out by the source doc (FR-002) — confirmed necessary, not avoidable, since
no existing seam exists on this class today.

**Alternatives considered**: Monkey-patching via `class_eval` from within `custom/` — rejected, it
would not follow the project's established `prepend_mod_with` idiom and would be inconsistent with
every other extension point in the codebase (Principle III).

## Decision: Registering the action name

**Decision**: `module Custom::AutomationRule` at `custom/app/models/custom/automation_rule.rb`
overrides `actions_attributes` to call `super + %w[create_opportunity]`.

**Rationale**: `AutomationRule#actions_attributes` (`app/models/automation_rule.rb`) is a plain
instance method returning a frozen string array, already consumed by `json_actions_format`
validation and dispatched by `AutomationRules::ActionService#perform`. Since `AutomationRule`
already ends with `AutomationRule.prepend_mod_with('AutomationRule')`, no edit to that file is
needed — matching FR-001 exactly.

**Alternatives considered**: Redefining the constant/array directly on the core class from
`custom/` via monkey patch — rejected for the same convention reason as above.

## Decision: Idempotency enforcement mechanism

**Decision**: Add a partial unique index on `matias_opportunities.origin_conversation_id`
(`WHERE origin_conversation_id IS NOT NULL`), and have `create_opportunity` rely on
`find_or_create_by`-style creation guarded by that constraint (rescuing the resulting
`ActiveRecord::RecordNotUnique`/relying on a pre-check plus the constraint as the backstop against
races) rather than a bare `Opportunity.exists?` check alone.

**Rationale**: The spec's Clarifications session established that duplicate prevention must hold
even under concurrent/near-simultaneous action firing (e.g. two labels added to the same
conversation in quick succession trigger the same rule twice). Phase 1 introduced
`matias_opportunities.origin_conversation_id` as a plain indexed, optional, nullable foreign key
with no uniqueness constraint (`db/migrate/20260730224301_create_matias_opportunities.rb` — regular
`t.references`, no `unique: true`). A pure application-level `Opportunity.where(origin_conversation_id: ...).exists?`
check has a check-then-act race window; only a database constraint closes it, matching how Phase 1
already solved the analogous concurrent-first-request problem for default pipeline stage seeding.
A *partial* index (rather than a plain unique index) is required because
`origin_conversation_id` is nullable and manually-created Opportunities with no origin conversation
must remain unrestricted (Phase 1 edge case: "created without any `origin_conversation_id`... must
be supported").

**Alternatives considered**: Advisory lock or `with_lock` around a check-then-create block only,
no index — rejected, adds complexity without eliminating the race as reliably as a database
constraint, and the user's clarification explicitly asked for the stronger guarantee.
`insert_all`/`upsert_all` with `unique_by:` and `on_duplicate: :skip` — rejected in favor of a plain
`create!` guarded by a pre-check plus rescue, because `insert_all`/`upsert_all` bypass AR
validations and callbacks, which this action relies on for `Opportunity` creation; the rescue-based
approach is also the pattern independently confirmed in wide real-world use (see Validation below).

**Validation**: Cross-checked against real-world code via `gh_grep` (GitHub code search) — GitLab's
`safe_ensure_unique` helper and Mastodon's merge/maintenance code both rescue
`ActiveRecord::RecordNotUnique` around a create guarded by a unique index, confirming this is a
recognized, non-anti-pattern Rails idiom rather than something invented for this feature. The
Rails/PostgreSQL-specific mechanics below could not be independently verified against official docs
in this session because the `context7` MCP tool was unreachable (listed as available but not
resolvable via tool search); the following is stated from training-data knowledge only, **not
context7-verified**, and should be spot-checked in a local console/migration dry-run during
implementation:
- `add_index :matias_opportunities, :origin_conversation_id, unique: true, where: "origin_conversation_id IS NOT NULL"`
  is valid Rails migration syntax on PostgreSQL, dumps faithfully to `schema.rb` (the `:where`
  option is preserved by `ActiveRecord::SchemaDumper`), and is automatically reversible inside a
  `change` method (Rails infers the matching `remove_index` call).
- A `create!`/`save!` that violates this constraint raises `ActiveRecord::RecordNotUnique` (wrapping
  the underlying `PG::UniqueViolation`), not `ActiveRecord::RecordInvalid` — the latter only fires
  from application-level validations, which this feature does not add for this constraint.

## Decision: I18n label location

**Decision**: Add `"CREATE_OPPORTUNITY": "Create Opportunity"` under the `ACTIONS` key in
`app/javascript/dashboard/i18n/locale/en/automation.json`, not `config/locales/en.yml`.

**Rationale**: Verified by inspecting the existing sibling entries — `ADD_LABEL`, `ASSIGN_AGENT`,
etc. all live under `ACTIONS` in `app/javascript/dashboard/i18n/locale/en/automation.json`
(confirmed via direct file read), not in the backend `config/locales/en.yml` (which has no
automation-actions namespace at all — confirmed via search). This corrects the source doc's FR-008,
which referenced `config/locales/en.yml`; the project's actual convention (documented in this
repo's `CLAUDE.md`: "Backend i18n → `en.yml`, Frontend i18n → `en.json`") places
Automation-Rules-dropdown labels in the frontend `en.json` tree, since they are rendered by the Vue
dropdown (Phase 3), matching every existing sibling action label.

**Alternatives considered**: Adding the label to both files for redundancy — rejected as
unnecessary duplication; only one file is ever read for this label (Principle II — smallest
change).

## Decision: No feature-flag gate on the action itself

**Decision**: `create_opportunity` is registered globally (available to any account's Automation
Rules), matching how every other existing action works — it is not additionally gated behind the
`opportunities` feature flag introduced in Phase 1.

**Rationale**: The source doc's functional requirements (FR-001–FR-008) do not request gating the
action's availability by the feature flag, and Phase 1's `opportunities` flag already gates the
underlying `Opportunity`/`PipelineStage` CRUD surface and the `KanbanFeatureGuard` controller
concern. If an account has the feature disabled but somehow still configures a `create_opportunity`
action, the action would attempt to create an `Opportunity` against a `pipeline_stage_id` that,
practically, would not have been reachable to select in the first place (no enabled UI/API to
obtain a valid stage id) — an edge case explicitly out of scope for this backend-only phase per
CLAUDE.md ("Do not add speculative guards... unless the caller can actually hit that case").

**Alternatives considered**: Re-checking `Current.account.feature_enabled?('opportunities')` inside
`create_opportunity` — rejected as a speculative guard not requested by any functional requirement
in this phase; can be revisited in a later phase if a real gap is observed.
