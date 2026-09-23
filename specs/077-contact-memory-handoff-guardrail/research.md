# Phase 0 Research: Contact Memory Handoff Pretext Guardrail

All Technical Context items were resolvable from the scout root-cause preview
(`docs/kanban/ciclo 10/scout/32-contact-memory-handoff-pretext-guardrail/spec-preview.md`) and direct
reading of the implicated `custom/` services. No open `NEEDS CLARIFICATION` remain.

## Decision 1 — Where the guardrail instruction lives

- **Decision**: Add a new conditional paragraph inside
  `Custom::Scout::SystemPromptsService#contact_context_section`
  (`custom/app/services/custom/scout/system_prompts_service.rb:96-102`), extracted into a private
  `memory_notes_warning` helper and appended to the section only when `@contact.notes.any?`.
- **Rationale**: `contact_context_section` is the *single* place any Scout prompt receives the
  contact's memory (`@contact.to_llm_text` → `LlmFormatter::ContactLlmFormatter`). Confirmed by
  preview §2 and §4: the Phase 12 `ActionClassifierService`/`ResponseAuditor` never see memory, so
  the gap is entirely in the main prompt. Instructing at the point of injection is the smallest,
  most salient fix and needs no duplication in `guardrails_section`.
- **Alternatives considered**:
  - *Add a bullet to the static `guardrails_section`* — rejected: not co-located with the notes it
    governs, so less salient (the same reason `identity_warning`/`phone_request_warning` are emitted
    as just-in-time `AVISO:` paragraphs next to the data rather than as static guardrail bullets).
  - *Filter/rewrite notes before injection (drop human-request notes)* — rejected: violates FR-003
    (memory must stay usable for personalization) and FR-008 (no mechanical trigger); the correct
    behavior is Scout's judgment, not deletion.
  - *Harden the Phase 12 auditor to inspect memory* — rejected: FR-007 requires the safety net to be
    unchanged, and the auditor is skipped when a tool already flags handoff (preview §4).

## Decision 2 — Warning content contract

- **Decision**: The paragraph, in pt-BR `AVISO:` style, must assert three points explicitly:
  (a) notes are summaries of prior, already-concluded conversations, not facts/requests of the
  current turn; (b) they MAY/SHOULD be used to personalize and proactively anticipate the contact's
  likely current interest (including nudging toward scheduling); (c) a note NEVER, on its own,
  justifies `handover_to_human` — the transfer signal must be present in the current conversation's
  own messages.
- **Rationale**: Directly encodes FR-001 (a), FR-003 (b), FR-002 (c). The three-part framing keeps
  User Story 3 (personalization) alive while closing User Story 1 (stale-note handoff), and names the
  exact tool (`handover_to_human`) so the model binds the rule to the concrete action, matching how
  the existing warnings name `update_contact`.
- **Alternatives considered**: A terse "ignore old notes for handoff" one-liner — rejected: an
  overly broad "ignore" risks suppressing the personalization the spec explicitly protects (SC-003).

## Decision 3 — Emission condition

- **Decision**: Emit only when `@contact.notes.any?` (and, as today, only when `@contact.present?`
  so `contact_context_section` runs at all).
- **Rationale**: Edge case in spec — a contact with no notes has nothing to guard; emitting the
  paragraph would be noise. Mirrors how `identity_warning`/`phone_request_warning` are each gated on
  their own precondition.
- **Alternatives considered**: Always emit — rejected: needless prompt bloat and a self-contradictory
  "these notes…" reference when there are none.

## Decision 4 — Note origin date at generation

- **Decision**: In `Custom::Scout::ContactNotesService#generate_and_update_notes`
  (`contact_notes_service.rb:11-19`), prefix each non-blank note with `"[DD/MM/YYYY] "` before
  `@contact.notes.create!`, so the persisted `content` carries the date.
- **Rationale**: `LlmFormatter::ContactLlmFormatter#build_notes` renders `note.content` verbatim
  (`app/services/llm_formatter/contact_llm_formatter.rb:19-21`, shared upstream with Captain). Baking
  the date into the stored content makes it appear everywhere the note text is shown — Scout's prompt
  and the dashboard Notes view — with zero edit to the shared formatter (FR-005), honoring Principle I
  (upstream isolation). Dating reinforces FR-001 by making a note's age legible at the point of use.
- **Alternatives considered**:
  - *Edit `ContactLlmFormatter#build_notes` to render `note.created_at`* — rejected: touches an
    upstream file shared with Captain (Principle I violation; explicitly out of scope in preview).
  - *Derive the date in the prompt builder from `note.created_at`* — rejected: would not surface in
    the dashboard Notes view (FR-005 requires the date visible everywhere the text shows), and would
    re-date pre-existing notes, violating FR-006.

## Decision 5 — Date format and timezone

- **Decision**: Format as `%d/%m/%Y` (e.g. `[22/09/2026]`), computed in the conversation's effective
  timezone — `@conversation.inbox&.timezone` when present, else the account default, else the app
  default — using an `ActiveSupport::TimeZone` conversion of `Time.current`.
- **Rationale**: pt-BR day-first date matches Scout's operating language and the preview's example.
  Notes are generated at handoff time; using the conversation/inbox timezone (the same source
  `current_time_section` already uses for Scout's clock) prevents a UTC day-boundary from mislabeling
  a late-evening BRT note with the next day. Date-only (no time) is sufficient for "how old is this
  note" legibility and keeps the prefix compact.
- **Alternatives considered**: `Time.current` in raw app/UTC tz — rejected: risks a one-day drift for
  evening conversations in negative-offset timezones. Including a timestamp — rejected: unnecessary
  precision, noisier prompt.

## Decision 6 — No retroactivity / no loop-suppression

- **Decision**: Only notes created from this change onward are dated; existing notes (#41–53) are left
  byte-for-byte unchanged. Semantic de-duplication of reinforcement-loop notes (preview §5) is **not**
  implemented.
- **Rationale**: FR-006 forbids retroactive edits. The reinforcement loop (preview §5) is broken by
  the revised interpretation (FR-001/FR-002) refusing a note as standalone handoff justification, not
  by suppressing note generation — matching the spec's Assumptions and Principle II (smallest change,
  no speculative mechanism).
- **Alternatives considered**: Skip re-creating a note semantically identical to an existing one —
  rejected as over-engineering per the spec's own scope note and Principle II.

## Decision 7 — Verification approach

- **Decision**: Unit specs assert the observable outputs directly — the rendered system prompt string
  (`SystemPromptsService.build`) and the persisted `Note#content`. Acceptance behavior is exercised
  through the real entry point with `Custom::Scout::PlaygroundRunner` replays: (1) a contact carrying
  a resolved-human-request note engaging normally → continues qualification, no `handover_to_human`;
  (2) a genuine present-turn human request (with or without notes) → immediate handoff.
- **Rationale**: Matches the conversation-replay + prompt-behavior conventions of prior guardrail
  phases (23, 29) named in the spec Assumptions, and satisfies Principle VI's "real entry point"
  requirement. The existing external LLM boundary (`RubyLLM::Chat`) is the only permitted double
  (Principle VII).
- **Alternatives considered**: Asserting internal helper return values only — rejected: Principle VI
  requires at least one test through the real entry point per acceptance criterion.
