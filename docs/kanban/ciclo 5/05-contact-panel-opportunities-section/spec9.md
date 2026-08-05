# Phase 9 (candidate): Opportunities Section in Native Contact Panel

**Status**: placeholder — idea parked, not yet brainstormed

## Quick Preview

Add an "Opportunities" accordion section to Chatwoot's native `ContactPanel.vue`
sidebar (the one shown while viewing a normal conversation), listing the
contact's opportunities with attachable quick actions (e.g. change stage,
mark won/lost), so agents can see/manage opportunities without leaving the
conversation view.

## Known complication (from initial research)

`ContactPanel.vue`'s sidebar sections are a closed `v-if`/`v-else-if` chain
keyed on `element.name`, and the available section names come from a frozen
default array (`DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` in
`useUISettings.js`). There is no generic plugin/extension point — adding a
new "opportunities" section requires touching both of these upstream files
directly (new array entry + new `v-else-if` branch).

This is the same class of problem already solved in Phase 4 (menu/route
wiring) via the anchor-based `bin/sync-custom-module-hooks` script. The
likely path here is extending that script's manifest to cover these two
additional files, rather than an ad hoc untracked edit.

## Relationship to the conversation drawer (Phase 5)

This is a complementary or possibly overlapping idea to Phase 5 — needs to
be resolved when we get to this spec: does this section replace the need for
the drawer (since the agent already sees opportunities from the normal
conversation view), or do both coexist for different workflows (kanban →
conversation vs. conversation → kanban context)?

Queued last, after Phases 6-8, pending its own brainstorm session.
