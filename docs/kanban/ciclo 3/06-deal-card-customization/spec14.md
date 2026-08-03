# Phase 14: Deal Card Customization

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 6 (card info and ordering), Phase 7 (stage transition
rules / required custom attributes)

## Quick Preview

`KanbanCard.vue` today shows a fixed set of info (contact, status badge,
unmet-requirements state driven by `pipeline_stages/stageById` and each
stage's `required_custom_attribute_definitions`). This phase is about
letting the card's content itself be customized — which fields/custom
attributes show up on the card face, and possibly in what order or
layout — rather than the fixed set that's hardcoded today.

Open questions for the brainstorm: is customization per-account, per-pipeline,
or per-pipeline-stage? Does it reuse the same `CustomAttributeDefinition`
reuse pattern from Phase 7 (custom attributes already tied to
`PipelineStage` via `required_custom_attribute_definitions`), or is this a
separate configuration surface? Where does the configuration UI live —
inside pipeline stage settings, or a new dedicated settings screen?
