# Phase 10: Sync Script Update for Ciclo 2 Core-File Touches

**Status**: placeholder — pending brainstorm session
**Depends on**: Phases 5-9 (all of ciclo 2)

## Quick Preview

`bin/sync-custom-module-hooks` (built in Phase 4) currently covers the 5
anchor points needed for ciclo 1 (`actionCable.js`, `Sidebar.vue`,
`dashboard.routes.js`, `settings.routes.js`, `store/index.js`). Ciclo 2
introduces several new necessary core-file touches that were not
anticipated when that script was scoped:

- Phase 5: new nested route entry in `dashboard.routes.js` (drawer route)
  — likely just extends an existing anchor, not a new one.
- Phase 7 (if the Custom Attributes reuse approach is chosen): new enum
  value in `CustomAttributeDefinition.attribute_model`
  (`app/models/custom_attribute_definition.rb`) and a new entry in
  `ATTRIBUTE_MODELS`
  (`app/javascript/dashboard/routes/dashboard/settings/attributes/constants.js`).
- Phase 9 (if pursued — parked, not yet committed to this cycle): new
  entry in `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER`
  (`app/javascript/dashboard/composables/useUISettings.js`) and a new
  `v-else-if` branch in `ContactPanel.vue`.

This phase's job: audit all core-file touches actually introduced across
ciclo 2 (only the phases actually implemented, not necessarily all of
5-9), and extend the sync script's manifest so every one of them is
covered by the same anchor-based, idempotent, fail-fast mechanism —
instead of being untracked ad hoc edits.

Needs its own brainstorm once ciclo 2's other phases are implemented (or
at least designed), since the exact set of touches depends on which
approaches get chosen (e.g. whether Phase 7 goes with the Custom
Attributes reuse approach, whether Phase 9 is pursued at all).
