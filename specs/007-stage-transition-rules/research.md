# Research: Stage Transition Rules

No `NEEDS CLARIFICATION` markers remain in the Technical Context — the stack, storage, and
testing tooling are all fixed by the existing `custom/` tree conventions established in
`specs/001-kanban-backend-core`. The items below record the design research needed to turn the
spec's functional requirements into a concrete plan.

## 1. Where opportunity-level custom fields live

**Decision**: Add `opportunity_attribute: 3` to the existing `CustomAttributeDefinition#attribute_model`
enum (`app/models/custom_attribute_definition.rb`) and `{ id: 3, key: 'OPPORTUNITY' }` to the
frontend `ATTRIBUTE_MODELS` constant, rather than building a parallel `custom/`-owned
custom-field-definition system.

**Rationale**: `CustomAttributeDefinition` already provides account-scoped uniqueness validation
(`attribute_key` uniqueness scoped to `[:account_id, :attribute_model]`), display-type typing
(`text`/`number`/`currency`/`percent`/`link`/`date`/`list`/`checkbox`), and a settings screen for
CRUD. `attribute_model` is a plain integer enum with three existing values
(`conversation_attribute: 0`, `contact_attribute: 1`, `company_attribute: 2`); appending a fourth
value is additive and touches no existing enum member. Attribute values themselves are *not*
stored on `CustomAttributeDefinition` — they're stored per-owning-record (Opportunity, in this
case), so no core `attribute_values` storage code path needs to change at all.

**Alternatives considered**:
- *Fully isolated `custom/`-owned field-definition model*: rejected — would require reimplementing
  uniqueness rules, display-type handling, and a second settings CRUD screen from scratch, a much
  larger and more error-prone surface than one enum value, and would fragment "manage custom
  fields" into two disconnected screens for the end user.
- *Store opportunity custom fields as a flat jsonb with no definition model at all (schema-less)*:
  rejected — the spec explicitly requires typed, named, admin-configured fields with per-lane
  requirement assignment (FR-003/FR-004), which needs a definition row to reference by id.

**Validated (2026-08-01) against the current codebase — required follow-ups**:
- `CustomAttributeDefinition` has two callbacks currently guarded only by `unless: :company_attribute?`:
  `after_update :update_widget_pre_chat_custom_fields` and `after_destroy :sync_widget_pre_chat_custom_fields`
  (both sync a definition's `attribute_key` against web-widget pre-chat form fields). These are not inert
  for a new enum member — they must also exclude `opportunity_attribute?`, or editing/deleting an
  opportunity-model attribute whose key happens to collide with a conversation pre-chat field name would
  silently mutate widget config. This is a required code change alongside the enum addition, not a
  no-op.
- `STANDARD_ATTRIBUTES` has no `:opportunity` key, so `attribute_must_not_conflict` will not guard against
  an opportunity-model attribute key colliding with real `Opportunity` columns (e.g. `title`, `status`).
  Accepted as a deferred gap for this phase (mirrors the existing lack of a `:company` entry), not fixed
  here.
- The frontend `ATTRIBUTE_MODELS` constant is only consumed by `AddAttribute.vue`'s "applies to" dropdown;
  the Attributes settings screen (`Index.vue`) has its own, separately hardcoded `attributeModels` array
  and `tabs` computed that do **not** read `ATTRIBUTE_MODELS` (this is also why `company_attribute` has no
  tab today despite existing on the backend enum). Adding `{ id: 3, key: 'OPPORTUNITY' }` to
  `ATTRIBUTE_MODELS` alone makes the option selectable in the create-attribute dropdown but will **not**
  surface an "Opportunity" tab in `Index.vue` — that requires its own additive entry if a generic
  Attributes-settings tab is desired. If opportunity fields are instead meant to be managed from a
  dedicated Kanban-specific settings surface, `Index.vue` need not be touched at all. This choice is
  deferred to `tasks.md`/implementation, not decided here.

## 2. Enforcing single-lane exclusivity for required fields and deal value

**Decision**: `PipelineStageRequiredField` gets a unique DB index on
`(account_id, custom_attribute_definition_id)`; the "reassignment steals it" semantics are
implemented in the controller (`PipelineStageRequiredFieldsController#create` deletes any existing
row for that `custom_attribute_definition_id` before creating the new one, in the same request).
For the deal value flag, `PipelineStage` gets a `before_save` callback that unsets
`requires_deal_value` on every other stage in the account when it's being set to `true` on the
current record.

**Rationale**: This exactly matches FR-002/FR-003 of the spec and the pattern already visible in
the codebase for "exactly one active X per account" invariants — a unique index as the hard
guarantee, plus explicit steal-semantics at the point of assignment so the UI doesn't need a
separate "unassign old, then assign new" round trip (atomic within one request, per FR-011 of the
source design doc).

**Alternatives considered**:
- *Application-level uniqueness validation only (no DB index)*: rejected — race conditions between
  two concurrent assignment requests could leave a field required by two stages simultaneously;
  the constitution's Principle IV (safe, reversible change) and general data-integrity practice
  favor the DB-level guarantee.
- *"Last write wins" without deleting the prior row (leave orphaned/stale required-field rows)*:
  rejected — would violate the unique index anyway, and would require manual cleanup UI to see
  "why can't I assign this field" errors instead of it silently moving.

**Validated (2026-08-01) — the two halves of this decision do not have equal guarantees**:
- The `PipelineStageRequiredField` unique index is a genuine DB-level guarantee, confirmed sound.
- The `requires_deal_value` half is **callback-only, with no DB constraint** — `before_save` doing
  `update_all` on sibling stages has no backing unique/partial-unique index, so two concurrent
  requests setting `requires_deal_value: true` on two different stages of the same account (under
  Postgres's default READ COMMITTED isolation, no row locking) can leave 0 or 2 stages flagged
  `true`. Real-world examples of this "steal the singleton flag" callback pattern (e.g. Spree's
  `Wishlist#ensure_default_exists_and_is_unique`, OpenProject's `Enumeration#unmark_old_default_values`)
  all treat it as best-effort, not race-safe, and none pair it with a DB constraint; this is
  accepted here as the same best-effort tradeoff, not a bug — a single-admin-editing-pipeline-config
  race is low-likelihood and low-blast-radius (worst case: re-open stage settings and re-toggle).
  If stronger guarantees are ever needed, a Postgres partial unique index
  (`add_index :matias_pipeline_stages, :account_id, unique: true, where: "requires_deal_value"`) is
  the documented upgrade path.
- Correction: no existing "one active X per account" precedent was found elsewhere in this
  Chatwoot fork (`app/models`, `enterprise/app/models`) — this is a common *Rails-ecosystem* idiom,
  not an *already-established convention in this codebase*; the decision stands on its own merits,
  not on matching existing code.

## 3. Forward-vs-backward move detection

**Decision**: `Opportunity` gains a validation with `on: :update, if: :pipeline_stage_id_changed?`
that compares `PipelineStage.find(pipeline_stage_id_was).position` against the new stage's
`position`; the validation only runs its required-field check when the new position is strictly
greater. `PipelineStage` already has `default_scope { order(:position) }` and an auto-incrementing
`position` on create (`custom/app/models/pipeline_stage.rb`), so "position" as the forward/backward
signal requires no new column or migration.

**Rationale**: Reuses an existing, already-authoritative ordering column instead of introducing a
second notion of stage order (e.g. array index in an API response), and matches exactly how the
frontend already renders columns (`pipelineStages/stagesSortedByPosition` getter).

**Alternatives considered**:
- *Compare timestamps of when the opportunity last visited each stage*: rejected — no such
  stage-visit-history table exists, and the spec's "forward" concept is expressly positional, not
  temporal (see spec's Context section on the Salesforce Path model).

**Validated (2026-08-01)**: confirmed `default_scope { order(:position) }` and the `before_validation
:set_position, on: :create` auto-increment both exist as described in `custom/app/models/pipeline_stage.rb`.
Confirmed `Opportunity` has no other `before_save`/`before_update` callback that would run ahead of
this new validation, and that `OpportunitiesController#update` calls plain `@opportunity.update(...)`
(no `update!`, no error-swallowing rescue), so dirty-tracking (`pipeline_stage_id_was`/`_changed?`)
reliably sees the pre-update value inside a `validate` block regardless of call path. One edge case
to note explicitly: `PipelineStage.find(pipeline_stage_id_was)` uses the bang `find`, which raises
`ActiveRecord::RecordNotFound` (an unhandled 500, not a clean 422) if that stage no longer exists —
acceptable per this repo's "let misconfigured state fail loudly" convention, since
`has_many :opportunities, dependent: :restrict_with_error` on `PipelineStage` already prevents
deleting a stage that's still referenced, making this effectively unreachable in practice.

## 4. Structured validation error shape for the 422 response

**Decision**: The model validation adds a structured error via `errors.add(:base, ...)` combined
with a dedicated method (e.g. `Opportunity#missing_required_fields`) that the controller reads on
failure to build the `missing_required_fields: { custom_attribute_keys: [...], requires_value: bool }`
body, rather than trying to parse `errors.full_messages` strings.

**Rationale**: `errors.full_messages.join(', ')` is what the existing `OpportunitiesController`
error path already does for the generic case (kept unchanged for non-stage-transition failures);
the spec requires a *machine-readable* structure specifically for this failure mode (FR-008), so a
separate accessor avoids fragile string-parsing on the controller side.

**Alternatives considered**:
- *Encode the missing-fields list inside the error message string itself*: rejected — brittle for
  the frontend to parse reliably, and the spec explicitly calls for structured (not just message)
  errors (FR-006 of source spec).

## 5. Client-side proactive check placement

**Decision**: Extend `dispatchMoveIfComplete` in `KanbanBoard.vue` to look up the destination
stage's required fields — and, per FR-009, every earlier stage's required fields too, since the
modal must present those as editable optional context — (embedded in the `pipelineStages` store's
per-stage payload once the `PipelineStagesController#index`/`#show` additive JSON embed described
in `contracts/pipeline-stage-required-fields-api.md` lands) against the dragged opportunity's
current `custom_attributes`/`value` (in the `opportunities` store's `byId` map, once this same
phase's `value`/`custom_attributes` columns and `as_json` exposure land — see Decision 1 and
`data-model.md`) before calling `store.dispatch('opportunities/moveCard', ...)`. If unsatisfied,
open `StageTransitionRequirementsModal.vue` instead of dispatching immediately.

**Rationale**: This is the existing single point where a completed drag becomes a dispatched move
today (`onCardRemoved`/`onCardAdded` both funnel into it), so gating there needs no new
drag-lifecycle wiring. No additional network fetch is needed since both required-field
configuration and current opportunity field values will already be loaded on board mount by the
time this decision's code runs — via this same phase's own model/controller work (Decision 1's
`custom_attributes`/`value` columns, and the pipeline-stage-required-fields contract's JSON embed),
not pre-existing infra. `custom_attributes`/`value` do not exist on `matias_opportunities` today.

**Alternatives considered**:
- *Validate inside `KanbanColumn.vue`'s drop handler before emitting `card-added`*: rejected — the
  move isn't known to be "complete" (both `fromStageId` and `toStageId`/`toIndex`) until
  `dispatchMoveIfComplete` runs, so validating earlier risks acting on partial drag state.
