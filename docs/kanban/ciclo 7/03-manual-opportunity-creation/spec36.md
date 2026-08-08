# Phase 36: Manual Opportunity Creation

**Status**: placeholder — pending brainstorm session

**Depends on**: Phase 8 (List View), whose view bar reserves a disabled "add opportunity" button
meant to be wired up by this phase.

## Quick Preview

A general-purpose entry point for creating an opportunity that isn't tied to a specific Kanban
column (unlike today's per-column "+" button, which opens `OpportunityCreateModal.vue` with a
preset stage). Needs design for: whether this reuses `OpportunityCreateModal.vue` as-is with an
explicit stage picker, or is a different flow entirely; what happens for opportunities created
without an origin conversation (today's cards without `origin_conversation_id` render as
non-clickable/grayed-out — is that still the right treatment for manually created ones); which
fields are required at creation time versus filled in later; and how this entry point relates to
the view bar's "add opportunity" button versus the existing per-column add buttons (do both stay,
or does one replace the other).
