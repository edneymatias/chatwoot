# Phase 88: Lead Scoring (Quente/Frio)

**Status**: placeholder — pending brainstorm session
**Depends on**: `custom/app/services/reports/stage_reach_calculator.rb` (existing
stage-progression signal, used today by the funnel report); Phase 85 (Opportunity Tasks &
Follow-ups, `docs/kanban/backlog/16-opportunity-tasks-and-followups/spec85.md`) — a natural
consumer of a "cold" signal.

## Quick Preview

Identified during a market-landscape brainstorm (2026-09-04): a hot/cold classification for
opportunities/leads, to help a small SDR team prioritize who to follow up with first. Flagged by
the operator as interesting but explicitly not the current top priority — Phase 85 (tasks) comes
first.

Open questions for the brainstorm:
- Signal set: what should actually define hot vs. cold for a dental/health-clinic SDR flow —
  time since last contact, stage dwell time, explicit value/stage thresholds, or a simpler
  manual-tag-only first cut?
- Automatic (computed) vs. manual (SDR sets it) vs. hybrid?
- Where surfaced — card badge/color, a filter, a sort key, or several of these?
- Relationship to Phase 85: does a lead going "cold" become the trigger for an automatic
  follow-up task, or are the two features independent?
