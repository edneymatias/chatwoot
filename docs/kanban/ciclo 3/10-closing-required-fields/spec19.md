# Phase 19: Closing Required Fields (Win/Loss)

**Status**: designed — ready for implementation
**Depends on**: Phase 7 (stage transition rules — `OpportunityRequiredFieldsForm.vue`,
`missing_required_fields` error contract), Phase 16 (drag-to-close status
bar — the UI trigger for status changes)

## Background

Business need raised while designing Phase 16 (drag-to-close): closing an
opportunity as won or lost may require specific custom attributes to be
filled first — e.g. a loss reason, or contact phone/email on a win. These
requirements are **global per account** (one set of attributes required
to mark won, one set required to mark lost), independent of which
pipeline stage the opportunity is in when closed. This is distinct from
the existing Phase 7 mechanism (`PipelineStageRequiredField`), which is
per-stage and triggers on forward stage-position moves, not on status
changes.

## Data model

New table `matias_pipeline_closing_required_fields`:

- `account_id` (bigint, FK)
- `custom_attribute_definition_id` (bigint, FK)
- `outcome` (integer enum: `won: 0`, `lost: 1`)
- timestamps

Unique index on `(account_id, custom_attribute_definition_id, outcome)` —
prevents duplicate entries within the same outcome, but the same
attribute may appear in both `won` and `lost` (no mutual exclusivity;
confirmed during design).

New model `PipelineClosingRequiredField`, independent of
`PipelineStageRequiredField`. Same `definition_must_be_opportunity_attribute`
validation as the existing model (definition must be an
`opportunity_attribute`).

**Cross-reference**: Phase 18 (parked) will introduce a structurally
similar table for a different trigger (per-stage, not outcome-based). At
that point, evaluate whether to unify both into a single generic
"required field trigger" model. Not attempted here — see the note left in
Phase 18's spec.

## Validation

New validation on `Opportunity`, parallel to
`validate_forward_stage_move_requirements` but triggered by
`status_changed?` (not `pipeline_stage_id_changed?`):

```
validate :validate_closing_requirements, on: :update, if: :status_changed?
```

Only runs when the new status is `won` or `lost` (not on reopen to
`open`). Checks `PipelineClosingRequiredField.where(account_id:, outcome: status)`
against `custom_attributes` (and, if applicable, `value` for a
`requires_deal_value`-style flag — out of scope unless a concrete need
shows up, since closing requirements are attribute-based only per the
examples given, not deal-value-based).

On failure, sets `missing_required_fields` and adds a `errors.add(:base, ...)`
error — same shape as the existing forward-move validation, so the
controller's existing `missing_required_fields` JSON response in `update`
needs no changes.

## Frontend

New `ClosingRequirementsModal.vue`, structurally mirroring
`StageTransitionRequirementsModal.vue`:

- Props: `opportunity`, `outcome` (`won`/`lost`), `initialMissingFields`.
- Catches the 422 `missing_required_fields` response the same way.
- Renders `OpportunityRequiredFieldsForm.vue` populated with the
  definitions required for that `outcome` (fetched via a new
  `pipelineClosingRequiredFields` store module or extended
  `pipelineStages` module — implementation detail for the plan).
- On submit, dispatches a new `opportunities/closeOpportunity({ id, status, custom_attributes })`
  action (parallel to `moveCard`, but PATCHes `status` instead of
  `pipeline_stage_id`) and retries.

Triggered when the Phase 16 drag-to-close action fails with
`missing_required_fields`.

## Settings UI

New "Fechamento" tab in the Pipeline Setup screen (same `TabBar.vue` shell
confirmed for Phase 16/Phase 14's settings evolution), alongside the
existing "Estágios" tab. Two lists — "Obrigatório para vitória" /
"Obrigatório para derrota" — each a picker over existing
`opportunity_attribute`-type custom attribute definitions, reusing the
same attribute-selection UI already used in the stage settings screen
today.

## Out of scope

- Deal-value-based closing requirements (only attribute-based, per the
  examples given during design).
- Any change to Phase 7's `PipelineStageRequiredField` uniqueness
  constraint — that's Phase 18, parked separately.
