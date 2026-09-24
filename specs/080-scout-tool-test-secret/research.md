# Phase 0 Research: Scout Tool "Test" Real-Credential Reconciliation

All unknowns from the feature spec were resolved by direct code inspection (no external
technology research needed — this is a bugfix within an existing, fully-implemented module).
The one open question (cross-account/missing tool id on `test`) was already resolved in
`spec.md`'s Clarifications section. This document records the *design* decisions needed to
implement the resolved behavior.

## Decision 1: Where the real secret is looked up from

**Decision**: Reuse `ScoutTool#parsed_auth_headers` (already decrypts `auth_headers` via
`encrypts :auth_headers`) as the source of truth for the saved credential, exactly as
`apply_credentials_update` already does for `update`.

**Rationale**: This is the exact mechanism `PATCH /scout_tools/:id` already uses to reconcile a
masked/blank submitted credential with the real saved one (`custom/app/models/scout_tool.rb:70-78,
114-139`). The bug is that `test` never reaches this code path at all (`ScoutToolsController#test`
builds `HttpRequestExecutor` straight from raw params, never loading a `ScoutTool`). Reusing the
proven mechanism means zero new decryption/merge logic, zero new places a real secret could be
mishandled.

**Alternatives considered**:
- Writing a parallel merge implementation directly in the controller — rejected: the preview
  investigation (`docs/kanban/ciclo 10/scout/36-.../spec-preview.md`) explicitly flags this as the
  wrong move ("não duplicar a lógica de merge, extraí-la para um método reutilizável"); two copies
  of masking-sensitive merge logic is exactly the kind of drift that causes future security bugs.

## Decision 2: How `test` learns which saved tool to reconcile against

**Decision**: Keep the existing `POST /scout_tools/test` collection route unchanged. Add an
optional `id` to the params the controller already reads via `test_params`. The frontend sends
`id: props.tool.id` in the test payload only when editing an existing tool (`isEditing.value` is
already computed in `ScoutToolModal.vue`).

**Rationale**: The route is `on: :collection` specifically because "Test" must work for a
brand-new, unsaved tool that has no id (`config/routes.rb:174-176`). Converting it to a member
route (`/scout_tools/:id/test`) would force two different endpoints/shapes for the saved-vs-draft
case, a larger and riskier surface change for no behavioral benefit — the collection route already
accepts arbitrary body params, so an optional `id` fits the existing contract with a one-line
parameter addition. This satisfies the Constitution's "Smallest Production-Ready Change"
principle.

**Alternatives considered**:
- Route change to `on: :member` with a fallback collection route for drafts — rejected: doubles
  the routing surface and the frontend call sites for a case the current single endpoint already
  handles once `id` is included in the payload.

## Decision 3: How an invalid/foreign `id` behaves (per Clarifications)

**Decision**: Resolve the tool with `Current.account.scout_tools.find_by(id: ...)` (nil-safe),
not `find` (raises). When the lookup returns `nil` — id absent, mistyped, deleted, or belonging to
another account — the controller falls through to the exact same code path as a brand-new,
unsaved tool: the submitted `auth_headers` is used as-is, with no substitution and no distinct
error response.

**Rationale**: Directly implements the resolved clarification ("no substitution, no distinct
error — same as testing a brand-new unsaved tool"). Using `find_by` instead of `find` avoids
introducing a 404 branch that doesn't exist today and would otherwise leak "this id doesn't exist
for you" as a distinguishable response, which the clarification explicitly rules out.
`Current.account.scout_tools` is the same account-scoping relation `set_scout_tool` already uses
for `show`/`update`/`destroy`, so no new cross-account exposure is introduced (FR-005).

**Alternatives considered**:
- `rescue ActiveRecord::RecordNotFound` around a `find` call — rejected: same end behavior as
  `find_by`, but adds a rescue branch for a case that isn't actually exceptional in this flow
  (an absent/foreign id is an expected, common input — every brand-new-tool test omits it).

## Decision 4: Shape of the extracted reconciliation method

**Decision**: Add `ScoutTool#auth_headers_for_test(incoming_credentials)` — a public,
non-persisting method that runs the same `normalize_incoming_hash` +
`merge_preserved_secrets(normalized, parsed_auth_headers)` pipeline `apply_credentials_update`
already runs, but returns the merged hash instead of assigning it to `self.auth_headers` and
never calls `save`/`save!`. `merge_preserved_secrets` and its per-auth-type helpers
(`merge_bearer_secret`, `merge_basic_secrets`, `merge_api_key_secrets`, `secret_blank_or_masked?`)
are reused unchanged (already private on the class, callable from the new public method).

**Rationale**: Matches the spec's Assumptions section exactly ("the existing masking marker and
rule... are reused as-is... mirrors the rule already in place and proven for Save"). Branches on
`self.auth_type` (the *saved* tool's own auth_type), the same source `apply_credentials_update`
uses — consistent with "no new or different rule" and avoids introducing a second notion of which
auth_type governs the merge.

**Alternatives considered**:
- Calling `apply_credentials_update` directly and reading back `parsed_auth_headers` without
  saving — rejected: mutates the in-memory `auth_headers` attribute of a record instance the
  controller does not otherwise intend to persist, an easy source of future bugs if that instance
  is later saved by accident in the same request. A pure function returning a Hash has no such
  risk.
