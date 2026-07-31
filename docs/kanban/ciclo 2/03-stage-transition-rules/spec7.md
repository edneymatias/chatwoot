# Phase 7: Stage Transition Rules

**Status**: placeholder — pending brainstorm session

## Quick Preview

Admins can configure, per `PipelineStage`, a set of required fields (likely Custom
Attributes on the Opportunity or Contact) that must be filled before a card can move
into that stage. Moving a card that doesn't meet the criteria is blocked — needs
design for where the check happens (frontend pre-drag validation vs. backend rejection
of the `PATCH`), how the user is prompted to fill missing fields (inline modal at drop
time?), and how this is configured in the Pipeline Stages settings screen built in
Phase 3.

Biggest open question: scope of "custom attributes" — Opportunity-level custom
attributes don't exist yet in the current data model (Phase 1 only ships `title`,
`status`, `pipeline_stage_id`, etc.) — likely requires a new migration/association,
not just a UI feature.

## Research note (added during Phase 5 brainstorm)

Investigated reusing Chatwoot's native Custom Attributes infra for
Opportunity-level fields, instead of building a bespoke attribute system.
Feasible, with 2 small core-file touches needed (same class as Phase 4's
anchor pattern):
- Backend: `CustomAttributeDefinition.attribute_model` is a closed enum
  (`conversation_attribute`/`contact_attribute`/`company_attribute` in
  `app/models/custom_attribute_definition.rb`) — would need a new
  `opportunity_attribute` value.
- Frontend: `ATTRIBUTE_MODELS` in
  `app/javascript/dashboard/routes/dashboard/settings/attributes/constants.js`
  is an equally closed array — would need a new `OPPORTUNITY` entry.
- `custom_attributes` storage itself is a plain `jsonb` column per model
  table (not polymorphic) — our own `matias_opportunities` table would need
  its own `custom_attributes` column (our own migration, zero upstream
  touch), and we'd build our own UI to read/write it filtered by the new
  `attribute_model` value (no native "OpportunityInfo" panel exists to
  hook into).

Leading candidate approach for this phase's brainstorm — reuses existing
attribute type/validation infra rather than reinventing it.
