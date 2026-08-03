# Phase 18 (candidate): Multi-Stage Required Fields

**Status**: placeholder — idea parked, not yet brainstormed
**Depends on**: Phase 7 (stage transition rules — current
`PipelineStageRequiredField` mechanism)

## Quick Preview

Revisit the constraint from Phase 7 where a custom attribute definition
can only be required in a single `PipelineStage` per account
(`custom_attribute_definition_id` unique scoped to `account_id` on
`PipelineStageRequiredField`). Idea raised while designing the
win/loss closing-required-fields spec (Phase 19): allow the same
attribute to be marked required in more than one stage, not just one.

Working rule proposed during that conversation (needs its own brainstorm
to confirm): once an attribute has been required and filled in an earlier
stage, it stays optional going forward even if the opportunity moves
through later stages that don't themselves require it — the "was
required, now filled, don't ask again unless the current stage also
requires it" behavior stays as-is. What changes is only that a stage no
longer has to be the *only* stage in the account allowed to require that
attribute.

This is independent from Phase 19 (closing required fields) — different
table (`PipelineStageRequiredField` vs. the new global won/lost table),
different validation trigger (forward stage-position move vs. status
change). No shared code between the two beyond both feeding
`OpportunityRequiredFieldsForm.vue`.

Open questions for the brainstorm: does lifting the uniqueness constraint
have any other behavioral implications for `validate_forward_stage_move_requirements`
(e.g. does moving backward then forward through the same required-attribute
stage twice re-trigger the check)? Is there a real use case driving this,
or is it a "why not" simplification — worth confirming before investing
in it.

## Note for that brainstorm: possible table unification

By the time this phase is picked up, Phase 19 (closing required fields)
will have introduced a second, structurally similar table
(`matias_pipeline_closing_required_fields`: account, custom attribute
definition, and a discriminator — `outcome` there vs. this phase's
`pipeline_stage_id`). Worth studying at that point whether to unify both
into one generic "required field trigger" table (e.g. a polymorphic or
tagged trigger: `stage:<id>` vs `outcome:won`/`outcome:lost`) instead of
maintaining two parallel tables/models with near-identical shapes. Not
decided now — explicitly deferred to that brainstorm, since forcing a
premature unification here would couple this phase's design to Phase 19's
implementation details before either is built.
