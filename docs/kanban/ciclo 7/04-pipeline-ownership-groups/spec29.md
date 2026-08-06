# Phase 29: Pipeline/Stage Ownership Groups

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 24 (Opportunity Assignment Rules — ships manual and
automation-configured assignment against the full account agent/admin
list, with no filtering)

## Quick Preview

Phase 24's assignee dropdowns (automation config, create/edit modals) list
every agent and administrator on the account — there is currently no
concept of a pipeline- or stage-scoped team/group in the data model
(`PipelineStage` has no membership/ownership relation). This phase would
explore whether pipelines or stages should have an associated group of
agents, and if so, how that constrains or assists assignment (e.g.
filtering the assignee dropdown to a pipeline's team, or an
auto-assignment/round-robin rule scoped to that group).

Open questions for the brainstorm:
- Is this a hard filter (only a pipeline's group members are assignable)
  or a soft default (group members surfaced first, anyone still
  selectable)?
- New data model: a join table between `PipelineStage`/a future
  `Pipeline` concept (see Phase 17) and `User`/`Team`? Or reuse Chatwoot's
  existing `Team` model directly as the "pipeline group"?
- Does this depend on Phase 17 (multiple pipelines) landing first, since
  "pipeline group" implies a `Pipeline`-level concept that doesn't fully
  exist yet (today it's implicitly one pipeline per account via ordered
  `PipelineStage`s)?
- Round-robin/auto-assignment within the group — in scope here, or a
  separate future phase on top of this one?
