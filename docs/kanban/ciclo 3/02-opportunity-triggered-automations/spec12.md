# Phase 12: Opportunity-Triggered Automations

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 2 (automation integration — `create_opportunity` action),
Phase 7 (stage transition rules, if lane-change events end up in scope)

## Quick Preview

Phase 2 wired automations in one direction: a conversation event can create an
Opportunity (`create_opportunity` action). This phase is the reverse direction:
Opportunity lifecycle events (at minimum `opportunity_created`, `opportunity_won`,
`opportunity_lost`) triggering automation actions — e.g. reply with a message, add a
label, close the conversation.

## Research note (added during Phase 7 brainstorm)

Investigated reusing Chatwoot's existing `AutomationRule`/`AutomationRules::ActionService`
engine rather than building a parallel one. Key finding: every action the engine
supports today (`send_message`, `add_label`, `resolve_conversation`, etc.) is built
around a `@conversation` the `ActionService` is constructed with (message builder
targets it, `resolve_conversation` acts on it directly) — there is no
conversation-agnostic action in the engine today.

Since an Opportunity may have no `origin_conversation` at all, the working assumption
(confirmed, not yet fully brainstormed) is: **if the triggering opportunity has no
origin conversation, none of today's actions have anything to act on, so the
automation is a no-op for that opportunity** — no per-action special-casing needed,
at least until/unless opportunity-native actions (e.g. "move to pipeline stage",
"assign opportunity to agent") are introduced.

`event_name` on `AutomationRule` is a plain string column (no DB enum), and
`actions_attributes`/`conditions_attributes` are plain Ruby methods already extended
by this fork via `Custom::AutomationRule` (see `create_opportunity`'s registration) —
so adding new trigger events is a code-level extension, not a schema/enum change.
`Events::Types` (`lib/events/types.rb`) is a plain constants module; new
`opportunity.*` event names could either be added there (shared registry, extra core
touch) or dispatched as raw string literals from `Opportunity` directly (zero core
touch) — undecided, worth weighing during the brainstorm.

Open questions deferred to the brainstorm session (explicitly not decided yet):

- Exact set of trigger events — at minimum created/won/lost, but possibly also
  pipeline-stage-change events (overlaps with Phase 7's lane config UI).
- Whether opportunity-triggered rules need condition/filtering support (existing
  `conditions_attributes` are conversation-attribute-scoped and don't fit
  opportunity fields like `pipeline_stage_id`/`value`/`status` as-is), or whether v1
  ships with trigger-event-granularity only, no conditions.
- Listener wiring: new `Custom::AutomationRuleListener` module (mirroring the
  `Custom::AutomationRule`/`Custom::AutomationRules::ActionService` prepend pattern
  already used for Phase 2) subscribing to the new dispatched events.
- Settings UI: `AUTOMATION_RULE_EVENTS` in
  `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` is a
  plain exported array in a core file — needs a touch (or an override strategy) to
  surface new event options in the rule-builder dropdown.
