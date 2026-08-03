# Phase 17: Multiple Pipelines and Cross-Pipeline Automations

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 1 (backend core), Phase 12/Phase 2 (automation
integration — `create_opportunity` action and, if pursued,
opportunity-triggered automations)

## Quick Preview

Today `PipelineStage` belongs directly to `account` with a single
implicit pipeline per account (`default_scope { order(:position) }`,
`seed_defaults_for!` creates two stages with no pipeline grouping). This
phase covers two related capabilities:

1. **Multiple pipelines**: introduce a `Pipeline` concept that
   `PipelineStage` belongs to (an account can have more than one board —
   e.g. separate pipelines for different product lines or teams), which
   is a real data-model change (new table, `PipelineStage` gets a
   `pipeline_id`, board/settings UI needs a pipeline selector).
2. **Cross-pipeline automations**: automations triggered by an
   opportunity event in one pipeline that act across pipeline boundaries
   — e.g. moving/creating an opportunity in a different pipeline when a
   stage is reached in another. Depends on opportunity-triggered
   automations (Phase 12) existing first, or being designed together.

Open questions for the brainstorm: is multi-pipeline required before
cross-pipeline automations make sense at all (seems like yes — no
"cross" without multiple), so does this split into two sub-phases with #1
as a hard prerequisite? How does existing single-pipeline data migrate
(implicit default `Pipeline` created per account)? What defines the
cross-pipeline automation trigger/action set — reuse Phase 12's
event/action design, or does crossing pipelines need its own action type
(e.g. "create linked opportunity in pipeline X")?

## Cross-reference: scope review needed for Phase 14

Phase 14 (Deal Card Customization, `ciclo 3/06-deal-card-customization/spec14.md`)
introduces an account-scoped `PipelineCardFieldConfig` (which up-to-3 badge
fields show on kanban cards), explicitly named/shaped for an account_id →
pipeline_id migration once a real `Pipeline` model exists. When this phase
introduces that model, revisit Phase 14's scope: should card-field config
become per-pipeline instead of account-wide?
