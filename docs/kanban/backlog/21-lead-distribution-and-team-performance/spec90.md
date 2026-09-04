# Phase 90: Lead Distribution & Team Performance

**Status**: placeholder — deferred, not yet pending brainstorm
**Depends on**: `custom/app/models/custom/automation_rule.rb` (`update_opportunity_assignee`
action, candidate extension point).

## Quick Preview

Identified during a market-landscape brainstorm (2026-09-04): round-robin/balanced auto-assignment
of opportunities across SDRs, plus a leaderboard-style report (meta vs. realizado por
vendedor/time). Explicitly deferred by the operator — the product today has a single SDR, so
distribution and leaderboard semantics "perdem o sentido" for now. Kept here only so the thread
isn't lost; the operator's own words: "crescendo, aumentando equipe, isso pode ser demanda."

**Do not brainstorm this in depth until team headcount actually grows past a single SDR.**

Open questions for whenever that brainstorm happens:
- Trigger point: extend the existing `update_opportunity_assignee` automation action with a
  round-robin mode, or a separate distribution mechanism?
- Team/goals data model — no per-user or per-team target/quota concept exists today; where would
  it live?
- Leaderboard report: likely a natural extension of the existing reports module
  (`custom/app/services/reports/`) once goals data exists.
