# Phase 11: Lane Dwell-Time Tracking

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 1 (backend core), Phase 6 (card ordering/fields)

## Quick Preview

Need to be able to calculate how long a lead (Opportunity) has stayed in a
given pipeline stage/lane. Neither `created_at` nor `updated_at` answer
this: `created_at` is total age, not time-in-current-stage; `updated_at` is
bumped on any attribute change, not just a stage move. No stage-transition
tracking exists anywhere in `custom/` today.

Two candidate approaches to explore in the brainstorm:

1. **Single timestamp column**: add `stage_entered_at` to `Opportunity`,
   updated only when `pipeline_stage_id` changes (via a model callback).
   Simple, cheap, but only reflects time in the *current* stage — no
   historical per-stage durations if a lead moves back and forth.
2. **Stage-transition history table**: new table logging
   `opportunity_id`, `from_stage_id`, `to_stage_id`, `changed_at` on every
   `pipeline_stage_id` change. More implementation work (new model,
   migration, callback), but supports full per-stage duration history and
   future reporting/analytics (e.g. average time-in-stage across a
   pipeline).

Open questions for the brainstorm: which approach is actually needed (is
historical per-stage reporting a real near-term goal, or is "time in
current stage" enough for now?); where this surfaces in the UI (card
badge? tooltip? a dedicated report?); whether this belongs in ciclo 3
alongside other analytics/reporting work not yet scoped.
