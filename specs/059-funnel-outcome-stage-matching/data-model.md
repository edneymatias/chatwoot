# Phase 1 Data Model: Funnel Outcome-Stage Matching for Scout

No schema change, no new persisted entity, no new Ruby class. This feature only changes prompt text
built from data that already exists, plus one static UI string. The table below maps each conceptual
entity from spec.md's Key Entities section to the existing model/column it already corresponds to, to
confirm there is nothing new to design.

| Spec Entity | Existing Implementation | Notes |
|---|---|---|
| **Pipeline Stage Description** | `PipelineStage#description` (`ichatr_pipeline_stages.description`, existing column) | Already read by `Custom::Scout::SystemPromptsService#format_stage`; this feature adds no field, only new instructions on how the AI must *use* the already-surfaced text. The UI hint (spec FR-009) is static copy near the existing form field for this same column — no new column, no validation added (spec explicitly rules out enforcing an "actionable" format). |
| **Conversation Turn Outcome** | Not a stored entity — the LLM's own interpretation of the latest turn, formed at inference time from the conversation's message history already passed into `chat` in `AgentRunner`/`PlaygroundRunner`. | No new field or log captures "the outcome" as a discrete value; it is transient model reasoning, consistent with spec's Assumptions ("no new qualification or pipeline data fields are introduced"). |
| **Opportunity Stage Transition** | `Opportunity#pipeline_stage_id` update via the existing `manage_opportunity`/`move_opportunity_stage` tools (`custom/app/services/custom/scout/tools/`), which already record `OpportunityStageChange` rows and already trigger the qualified-stage automatic handoff (Phase 09) this feature relies on. | No new side effect is added. FR-001a's forward-only guard is enforced purely by prompt instruction (the model choosing not to call the move tool backward), not by new code-level validation — consistent with this feature's text-only scope; the underlying `move_opportunity_stage` tool remains capable of any stage transition, as it must be for legitimate manual/operator-driven corrections. |
| **Qualification Data** | Existing `CustomAttributeDefinition`/opportunity custom-attribute values, already accepted as `custom_attributes` params by `manage_opportunity`/`move_opportunity_stage` (Phase 09/Phase 057 tool schemas). | No new attribute type or field; FR-004 only changes the prompt's framing of these already-accepted parameters (including existing date/time-typed attributes) as sufficient, never citing a missing external tool. |

## State Transitions

No new state machine. `Opportunity#status` (`open`/`won`/`lost`) and `PipelineStage` role assignment
(`Scout#default_pipeline_stage_id`/`qualified_stage_id`/`unqualified_stage_id`) are unchanged from
Phase 09. This feature only changes *when* the model chooses to call the existing
`move_opportunity_stage` tool, per the two clarified rules now encoded in the prompt:

1. On a clear single-stage match → move now (existing tool call, existing side effects).
2. On a clear multi-stage match → move to the closest/most-specific match (same tool call; the model
   picks which `stage_id` to pass — no new parameter).
3. Once an opportunity has reached the qualified stage → no further automatic `move_opportunity_stage`
   call moves it back to an earlier or the disqualified stage (the model simply does not call the tool
   in that direction; nothing new blocks it at the tool layer).

## Validation Rules

None added. Spec FR-009 explicitly keeps the pipeline stage description field free-form (no format
enforcement); spec FR-011 keeps all matching logic in general natural-language prompt guidance, with
no new hardcoded keyword/condition validated anywhere in code.
