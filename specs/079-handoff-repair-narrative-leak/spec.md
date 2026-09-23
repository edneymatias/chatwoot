# Feature Specification: Response Auditor Repair Loop Narrative Leak

**Feature Branch**: `079-handoff-repair-narrative-leak`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/35-response-auditor-repair-loop-narrative-leak/spec-preview.md — when the model decides mid-turn to hand a conversation off to a human via the `handover_to_human` tool and already writes a coherent closing message, the response auditor's claim-consistency check still runs on that message, occasionally judges it inconsistent, and triggers the repair loop. The repair loop re-prompts the model with an instruction implying its previous reply falsely claimed an action was completed, which the model — even though its own handoff tool call already succeeded — sometimes answers by apologizing for a nonexistent prior mix-up and calling the handoff tool a second time 'to make sure it goes through.' Both the customer-facing closing message and the internal transfer note then reflect this second, repair-triggered call instead of the model's original, correct one, leaking an internal repair narrative ('sorry for the confusion earlier,' 'correcting the previous turn') that has no basis in the real conversation."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A tool-decided handoff turn is delivered exactly as the model wrote it (Priority: P1)

A customer asks a question that the model decides, within a single turn, requires a human (for
example, a pricing question the assistant isn't allowed to answer). The model calls the
`handover_to_human` tool successfully and writes a coherent closing message in the same reply.
Today, that reply is still sent through the claim-consistency check as if the tool outcome were
unknown; when the check misjudges it as inconsistent, a second, invisible call to the model
rewrites the reply and the handoff reason around a nonexistent "previous turn" that needs
correcting. With this feature, once a turn has already deterministically decided a handoff by
successfully calling the tool, that turn's reply and handoff reason are delivered exactly as the
model wrote them — no second consistency check, no repair call, no risk of the model inventing an
apology for a mix-up that never happened.

**Why this priority**: This is the customer- and team-facing defect itself — a wrong, confusing
message reaches the customer and a confusing internal note reaches the team, for a handoff that was
actually decided correctly on the first try.

**Independent Test**: Can be fully tested by replaying a conversation where the model responds to a
question by calling `handover_to_human` successfully and writing its own closing message in the
same turn, then confirming the customer-facing message and the internal transfer note both match
that original message and reason verbatim, with no mention of a prior turn, confusion, or
correction, and no second call to the consistency-check/repair step.

**Acceptance Scenarios**:

1. **Given** the model calls `handover_to_human` successfully and writes a coherent closing message
   in the same turn, **When** the response auditor processes that reply, **Then** it returns the
   original reply unchanged, without invoking the claim-consistency check or the repair loop.
2. **Given** the same scenario, **When** the turn completes, **Then** the customer-facing message and
   the internal transfer note both reflect exactly the text and reason from that original tool call
   — not from any later re-prompt.
3. **Given** a turn where the model's reply promises or claims a completed action but no tool was
   actually called to back that claim (the case the repair loop exists for), **When** the response
   auditor processes that reply, **Then** the claim-consistency check and repair loop still run and
   behave exactly as they do today — this feature does not weaken that protection.
4. **Given** a turn where the repair loop runs (per Scenario 3) and, during repair, the model decides
   for the first time to call `handover_to_human` — a handoff that had not been decided or flagged
   before repair started, **When** the response auditor processes the repaired reply, **Then** the
   existing behavior for that case is unchanged: the repaired reply and its handoff decision are
   used as they are today.

---

### User Story 2 - The repair loop's own output becomes visible in logs (Priority: P2)

When the claim-consistency check does judge a reply inconsistent and the repair loop runs, today
only the final response text that comes back is used — any reasoning the model produced while
repairing is discarded, and neither the consistency check's verdict nor the repair call's outcome
is logged anywhere. When something goes wrong in this path (as in User Story 1's scenario), there is
no record to diagnose it after the fact. With this feature, the repair loop's outcome is logged with
the same level of detail already used for the model's main-turn reasoning, so this path is no longer
a diagnostic blind spot.

**Why this priority**: Observability improvement that makes the defect in User Story 1 (and any
future issue in this path) diagnosable from logs alone, instead of requiring a manual correlation
exercise against raw conversation data. Independent of whether User Story 1's skip logic is present.

**Independent Test**: Can be fully tested by forcing the repair loop to run (a reply that promises
an action without a backing tool call) and confirming the repair call's outcome — reason/response
content, not just a bare "repair ran" flag — appears in application logs.

**Acceptance Scenarios**:

1. **Given** the claim-consistency check judges a reply inconsistent and the repair loop runs,
   **When** the repair call returns, **Then** its outcome is recorded in the application log at the
   same level of detail as the main turn's reasoning log entry.

---

### Edge Cases

- What happens when a tool-decided handoff turn's reply also contains a separate, unrelated claim
  that itself would have been genuinely inconsistent (e.g., an unrelated promise elsewhere in the
  same message, unconnected to the handoff)? → Not verified or repaired once the turn's handoff has
  already been deterministically decided by a successful tool call; this is an accepted trade-off of
  this feature (see Assumptions), not a defect to fix here.
- What happens when the `handover_to_human` tool is called but fails (does not return success)? →
  The turn is not treated as already-decided; the claim-consistency check and repair loop continue
  to run exactly as they do today.
- What happens when the conversation stops being open for an unrelated reason (e.g., closed by
  another process) before the response auditor runs at all? → The existing early-return behavior for
  a non-pending conversation is unaffected by this feature.
- What happens for a handoff decided by the response auditor's own classifier (a different code path
  that never reaches the model a second time in the way this feature addresses) or by the
  automatic-handoff-at-qualified-stage mechanism? → Both are unaffected; this feature only changes
  the path where the model itself calls the handoff tool mid-turn.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Once a turn's handoff has already been deterministically decided by a successful call
  to the handoff tool, the response auditor MUST NOT run the claim-consistency check on that turn's
  reply.
- **FR-002**: Once a turn's handoff has already been deterministically decided by a successful call
  to the handoff tool, the response auditor MUST NOT invoke the repair loop (no second call to the
  model) for that turn.
- **FR-003**: For a tool-decided handoff turn, the customer-facing message and the internal transfer
  note MUST both be exactly the text and reason produced by the original, successful tool call —
  never overwritten by content from a later re-prompt.
- **FR-004**: For a turn where no tool has already deterministically decided a handoff, the
  claim-consistency check and repair loop MUST continue to run exactly as they do today, with no
  behavior change from this feature.
- **FR-005**: When the repair loop itself causes the model to decide a handoff that had not been
  flagged before repair started, that outcome MUST continue to be used exactly as it is today
  (no change to this specific case).
- **FR-006**: When the repair loop runs, its full outcome (including any reasoning produced, not
  only the final reply text) MUST be recorded in the application log.

### Key Entities

- **Tool-Decided Handoff Flag**: Per-turn state indicating a handoff has already been
  deterministically decided by a successful call to the handoff tool within the current turn,
  before the response auditor's consistency check would otherwise run. Already exists today to skip
  the action classifier; this feature extends its effect to also skip the consistency check and
  repair loop.
- **Repair Outcome Log Entry**: A new log record capturing what the repair loop's model call
  produced (reasoning and response), created whenever the repair loop actually runs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Replaying the conversation pattern that surfaced this defect (a question that leads
  the model to call the handoff tool and write its own closing message in the same turn) produces a
  customer-facing message identical to what the model originally wrote, with no invented references
  to a prior turn, confusion, or correction.
- **SC-002**: 100% of turns where the handoff tool has already succeeded make zero additional calls
  to the consistency-check/repair step.
- **SC-003**: The existing repair-loop behavior for (a) a reply that promises an action with no
  backing tool call, and (b) a handoff first decided during repair, is unchanged — both continue to
  pass their existing test coverage with no regression.
- **SC-004**: Every time the repair loop runs, its outcome is readable from logs alone, without
  needing to correlate raw request/response data.

## Assumptions

- The chosen approach is to skip the claim-consistency check entirely for a tool-decided handoff
  turn (mirroring the existing pattern that already skips the action classifier for the same
  condition), rather than the more conservative alternative of still running the check but blocking
  only the repair loop's model call and falling back to a fixed generic message on an inconsistent
  verdict. The source diagnostic document recommends the former as simpler and more consistent with
  the file's existing pattern; the latter remains available as a fallback design if review during
  implementation prefers it.
- The persona-configuration ambiguity over whether a pricing question counts as an "administrative
  question" that should trigger a handoff at all is out of scope — that is an operator-editable
  persona/prompt concern, not a code defect, and is independent of this feature.
- The response auditor's classifier-driven handoff path (a different, closed set of reasons) and the
  automatic handoff at a qualified pipeline stage are unaffected; this feature only changes the path
  where the model itself calls the handoff tool mid-turn.
- The fixed fallback handoff message and the handoff service's default note text are unchanged by
  this feature.
- This is a backend behavioral fix with an added log entry; it introduces no new user-facing UI.
