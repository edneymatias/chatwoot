# Contracts: Scout Agent Tool Surface

The Scout agent's "interface" is the set of `RubyLLM::Tool` definitions (name, params, return
string contract) it can call. This feature changes two of them and adds no new tool. It also
changes the text the agent receives at conversation start (the system prompt), which is the
agent's read-only "input contract" for funnel knowledge.

## `move_opportunity_stage`

**Before** (current production contract):

| Param | Type | Required | Notes |
|---|---|---|---|
| `stage_id` | integer | yes | Target pipeline stage ID |
| `lost_reason` | string | no | Reason for loss or disqualification — **setting this immediately closes the opportunity as `lost`** |

**After** (this feature):

| Param | Type | Required | Notes |
|---|---|---|---|
| `stage_id` | integer | yes | Target pipeline stage ID |

- `lost_reason` is removed entirely (FR-011). The tool description no longer mentions "records a
  reason if lost or disqualified."
- Return value contract (unchanged shape, new failure cases):
  - Success: `"Opportunity moved to stage <name> successfully."` (unchanged string shape)
  - No opportunity for conversation: `"No opportunity found for this conversation."` (unchanged)
  - Invalid stage: `"Pipeline stage not found."` (unchanged)
  - **New**: Missing global qualification requirements (target = qualified stage):
    descriptive string naming missing attribute display names, no exception (FR-006)
  - **New**: Missing per-stage required fields (any forward move): descriptive string naming
    missing attribute display names, no exception (FR-007) — previously this case raised
    `ActiveRecord::RecordInvalid` uncaught, crashing to `AgentRunner`'s generic fail-safe handoff.

## `manage_opportunity`

**Contract is unchanged at the parameter level** — `stage_id` was already optional. What changes is
behavior when `stage_id` is present on an `update`:

- **Before**: `opp.pipeline_stage_id = stage_id; ...; opp.save!` — an unmet per-stage requirement
  raises, uncaught, crashing to the generic fail-safe handoff (same bug as above). No qualification
  check existed at all.
- **After**: when `stage_id` is present, the stage assignment + save is delegated to
  `OpportunityStageTransitionService#call(stage_id:)` (still a single atomic save covering
  `title`/`value`/`custom_attributes` assigned earlier in the same call) — same success/failure
  message contract as `move_opportunity_stage` above. When `stage_id` is absent, behavior is
  unchanged (`opp.save!` directly, per FR-013 for `create_opportunity` and the no-`stage_id` path of
  `update_opportunity`).

## `handover_to_human`

**Contract unchanged.** Same params (`assignee_id`, `team_id`, `reason`), same return strings. Only
the internal implementation delegates to the new `HandoffService` (Research decision #2) —
behavior visible to the agent/operator is identical.

## System prompt (`Custom::Scout::SystemPromptsService#build`)

**New `funnel_section`**, added to the `sections` array (returns `nil`/omitted per FR-014 when
nothing is configured). Not a machine-parsed contract, but the following content guarantees hold
whenever the corresponding config exists:

- Every account funnel stage: name + semantic role (`default`/`qualified`/`unqualified`) when
  applicable, plus the stage's `description` when the operator has configured one (omitted, not
  blank-rendered, otherwise).
- Per stage with configured required fields: `attribute_display_name`, `attribute_display_type`,
  `attribute_values` (when `list`), and `attribute_description` when configured (omitted otherwise).
- Scout's global qualification requirements: same attribute fields (including
  `attribute_description` when configured), explicitly labeled as additional-and-required for the
  qualified stage (distinct from any single stage's own list).
- Operational guidance text: qualifying triggers automatic handoff (don't call
  `handover_to_human` for that case); disqualifying is a human-review queue, not a closure (record
  reasoning via `create_private_note`, not a "lost reason").
