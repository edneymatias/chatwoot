# Phase 07 — Edge Cases, Trunk Capacity & Production Hardening

**Master doc**: `docs/kanban/backlog/sip-ari/spec48.md` §3.4, §7.5, §7.6, "Open items carried
forward"

## Goal

Close out the infra-level open items and document/operationalize the constraints that can't be
solved in code, before this channel is considered production-ready. This is the final phase — a
review/hardening pass across everything Phases 01–06 built, not new call-handling logic.

## Scope

- **Trunk capacity validation**: live-test two distinct simultaneous callers against the real
  Algar trunk once a second phone line is available. Use `asterisk -rvvv` + `pjsip set logger on`
  to confirm a second INVITE from Algar arrives during a second simultaneous call, plus
  `pjsip show channels` / `core show channels` to confirm two independent channels exist. If the
  trunk plan caps concurrency at one channel, this is resolved by a carrier plan upgrade, not code
  — document the finding either way.
- **Trunk capacity exceeded at the carrier level** (§7.5): if the carrier rejects a call before it
  reaches Asterisk, no Stasis event is ever generated — Chatwoot never sees the call. Confirm
  there's nothing to catch here; document as an accepted infra limitation, not a code path to
  build.
- **Agent availability / shared-extension production posture** (§7.6): SIP/PJSIP ring-fork happens
  at the phone layer (Asterisk forks the INVITE to every registered contact), not the app layer.
  This works cleanly for the browser's own `sip.js` client (same `shouldRingInbound`-equivalent
  app-layer gating applies), but does **not** extend to any separate physical/softphone (e.g.
  MicroSIP, Linphone) registered under the shared extension — those ring regardless of the agent's
  Chatwoot availability status. Ship this as documented operational guidance (agents use the
  browser's built-in SIP client as their primary/only registered device), not as a code fix —
  there's no way for Chatwoot to reach into a third-party SIP client's ringing behavior.
- Full regression pass across Phases 01–06 together: create inbox → inbound call → concurrent
  inbound calls → outbound call → recording playback → agent-unavailable inbound suppression →
  tab-close mid-call → ARI disconnect/reconnect reconciliation, all in one continuous manual test
  session against the real FreePBX.

## Acceptance criteria

- Trunk concurrency behavior is confirmed and documented (not left as an open question).
- Written operational guidance exists (README/runbook, not just this spec) telling agents/admins
  to use the browser SIP client as the authoritative registered device.
- End-to-end regression pass across all six prior phases completes with no unresolved defects.
