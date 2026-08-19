# Phase 06 — In-Conversation UI

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §4.2, §7
**Depends on**: Phase 02 (Fail-Safe/handoff flow exists to reflect status from), Phase 05 (Scout
config exists to link back to).

## Goal

Give agents visibility and manual control over the Scout directly from the conversation view.

## Scope

- Status badge on the conversation showing whether the Scout is actively engaged, paused (human
  intervention detected — `auto_pause_on_human_message`), or handed off.
- Manual Pause/Resume control per conversation.
- Link from the conversation to the associated Opportunity/Kanban card (if one exists for that
  `origin_conversation_id`).

## Out of scope

- No bulk pause/resume across conversations — single-conversation control only, matching current
  scope.

## Acceptance criteria

- Badge accurately reflects Scout state (active/paused/handed-off) and updates in real time as
  state changes (e.g. via existing ActionCable broadcast patterns).
- Pause/Resume button correctly stops/restarts `Scout::ProcessMessageJob` from acting on that
  conversation.
- Kanban card link navigates to the correct Opportunity when one exists, and is hidden/disabled
  when none does.
