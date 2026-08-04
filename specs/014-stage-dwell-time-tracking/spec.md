# Feature Specification: Stage Dwell-Time Tracking

**Feature Branch**: `014-stage-dwell-time-tracking`

**Created**: 2026-08-04

**Status**: Draft

**Input**: User description: "Phase 11: Stage Dwell-Time Tracking — track how long an opportunity has sat in its current kanban pipeline stage, record full stage-transition history for future funnel reporting, let accounts set a per-stage staleness threshold, and surface a dwell-time badge (with alert styling when stale) on the kanban card."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See how long a lead has been stuck in its stage (Priority: P1)

A sales rep looking at the kanban board wants to know, at a glance, how long
each opportunity has been sitting in its current stage — without having to
open the card or compare timestamps manually.

**Why this priority**: This is the direct, visible value of the feature and
requires the underlying transition history to exist. Without it, nothing else
in this phase is user-facing.

**Independent Test**: Move an opportunity into a stage, wait, then view the
kanban board — the card shows a badge like "5 days ago" reflecting time since
the last stage change, not time since the opportunity was created.

**Acceptance Scenarios**:

1. **Given** an opportunity was just created in a stage, **When** its owner
   views the kanban card, **Then** the badge shows a dwell time starting from
   the moment it entered that stage (e.g. "a few hours ago").
2. **Given** an opportunity has been moved between stages multiple times,
   **When** its owner views the kanban card, **Then** the badge reflects time
   since the most recent stage change, not the opportunity's original creation
   date.
3. **Given** an opportunity is edited (e.g. deal value changed) without a
   stage change, **When** its owner views the kanban card, **Then** the badge
   is unaffected by that edit.

---

### User Story 2 - Configure a staleness threshold per stage (Priority: P2)

An account admin knows that different stages have naturally different
expected dwell times (e.g. "waiting for a scheduled appointment" can
legitimately take two weeks, while "attempting first contact" should turn
over within a day or two). They want to set a per-stage number of days after
which a lingering opportunity is flagged as stale, so the team's attention is
drawn to leads that are actually stuck rather than ones simply following a
normal, slower stage.

**Why this priority**: The dwell-time badge from User Story 1 already
delivers standalone value without this; the alert threshold is a refinement
that depends on it and control is a secondary, account-configuration step.

**Independent Test**: In the pipeline stage settings, set a staleness
threshold for one stage and leave another stage's threshold unset. Verify the
setting is saved and that only the configured stage can flag stale
opportunities.

**Acceptance Scenarios**:

1. **Given** an account admin is editing a pipeline stage's settings, **When**
   they enter a number of days for the staleness threshold, **Then** the
   value is saved and applies to that stage only.
2. **Given** an account admin leaves the staleness threshold empty, **When**
   opportunities sit in that stage indefinitely, **Then** no staleness alert
   is ever shown for cards in that stage.
3. **Given** a new pipeline stage is created, **When** the admin has not yet
   configured a staleness threshold, **Then** the stage defaults to no
   alert (never flags as stale) rather than inheriting a generic default.

---

### User Story 3 - Alert styling for stale opportunities (Priority: P3)

A sales manager scanning the kanban board wants stale opportunities (those
that have exceeded their stage's configured threshold) to visually stand out
from opportunities that are still within a normal dwell time for their stage.

**Why this priority**: This is a presentation refinement on top of User
Stories 1 and 2 — it changes how the badge looks, not whether the underlying
data or threshold configuration exists.

**Independent Test**: With a stage's staleness threshold configured, view an
opportunity that has exceeded that threshold and one that has not — confirm
only the exceeded one displays the alert-styled badge.

**Acceptance Scenarios**:

1. **Given** a stage has a staleness threshold configured, **When** an
   opportunity's dwell time exceeds that threshold, **Then** its badge
   switches from the neutral style to an alert style (amber/red).
2. **Given** a stage has a staleness threshold configured, **When** an
   opportunity's dwell time is within that threshold, **Then** its badge
   keeps the neutral style.
3. **Given** a stage has no staleness threshold configured, **When** viewing
   any opportunity in that stage regardless of how long it has dwelt there,
   **Then** the badge never switches to the alert style.

---

### Edge Cases

- What happens when an opportunity moves to a stage and then immediately back
  to the same stage (no-op move)? A transition is only recorded when the
  stage actually changes; a save that doesn't change the stage does not reset
  the dwell-time clock.
- How does the system handle an opportunity created directly in a non-initial
  stage (e.g. imported already "in progress")? Its first transition record
  has no "from" stage, and dwell time is still measured from that initial
  transition.
- What happens if a staleness threshold is changed while opportunities are
  already sitting in that stage? Newly configured thresholds apply
  immediately on next view — no historical recalculation or backfill is
  needed since dwell time is always computed live from transition history.
- What happens when a stage is deleted or opportunities are moved off it?
  Historical transition records referencing that stage are preserved for
  reporting purposes; this phase does not change stage deletion behavior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST record a complete history of stage transitions for
  every opportunity, capturing which stage it moved from (if any), which
  stage it moved to, and when the move happened.
- **FR-002**: System MUST record an initial transition when an opportunity is
  created, so every opportunity has at least one transition record from the
  moment it exists (no special-cased "opportunity has no history" state).
- **FR-003**: System MUST record a new transition every time an opportunity's
  pipeline stage changes, and MUST NOT record a transition when other
  opportunity fields change without a stage change.
- **FR-004**: System MUST compute "time in current stage" for any opportunity
  as the time elapsed since its most recent recorded transition.
- **FR-005**: Account admins MUST be able to configure an optional staleness
  threshold (number of days) independently for each pipeline stage.
- **FR-006**: A pipeline stage's staleness threshold MUST default to "unset"
  (no alert ever triggered) both when the stage is first created and when no
  value has been explicitly configured — it must never assume a fallback
  numeric default.
- **FR-007**: The kanban card MUST display the current time-in-stage as a
  human-readable relative-time badge (e.g. "5 days ago"), using the same
  relative-time convention already used elsewhere on the card.
- **FR-008**: The kanban card's dwell-time badge MUST switch to an alert
  visual style when the opportunity's time in its current stage exceeds that
  stage's configured staleness threshold, and MUST use the existing neutral
  style otherwise (including whenever no threshold is configured).

### Key Entities *(include if feature involves data)*

- **Stage Transition**: Represents a single move of an opportunity from one
  pipeline stage to another (or into its first stage on creation). Belongs to
  an opportunity and an account; records the origin stage (nullable, for the
  very first transition), the destination stage, and when the move happened.
  Used to derive current dwell time and, in a later phase, historical
  reporting like average time-in-stage and stage-to-stage conversion.
- **Pipeline Stage staleness setting**: An account-configurable, per-stage
  attribute representing the number of days an opportunity may dwell in that
  stage before being flagged as stale. Optional; unset means the stage never
  triggers a staleness alert.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can determine how long any opportunity has been in its
  current stage by glancing at its kanban card, without opening the card or
  cross-referencing other timestamps.
- **SC-002**: Every opportunity in the system has an unbroken, queryable
  history of every stage it has ever moved through, suitable for computing
  time-in-stage and stage-to-stage conversion metrics in a later reporting
  phase.
- **SC-003**: Account admins can set a distinct staleness expectation for
  each stage in under 30 seconds per stage, without affecting other stages.
- **SC-004**: Opportunities that have overstayed their stage's configured
  threshold are visually distinguishable from healthy ones on the kanban
  board at a glance, with zero false positives for stages that have no
  threshold configured.

## Assumptions

- No existing opportunities need historical stage-transition data
  backfilled — the target account currently has zero opportunities recorded,
  so transition tracking can start cleanly from this feature's rollout.
- The dwell-time badge and staleness alert are surfaced only on the kanban
  card; no other alerting channel (notifications, digest emails, reports) is
  in scope for this phase.
- The funnel report that will consume this transition history (average
  time-in-stage, stage-to-stage conversion charts) is a separate, later
  phase — this phase only lays the data foundation and the card-level UI.
- The dwell-time badge and staleness threshold settings UI reuse the
  existing kanban card layout conventions and badge color tokens already
  established for deal card customization and status badges, rather than
  introducing a new visual language.
