# Contract: Memory-Interpretation Warning in the System Prompt

**Surface**: the string returned by `Custom::Scout::SystemPromptsService.build(scout:, contact:, …)`,
specifically the `contact_context_section` fragment.

**Producer**: `Custom::Scout::SystemPromptsService#contact_context_section`
(`custom/app/services/custom/scout/system_prompts_service.rb`).

**Consumer**: Scout's main LLM turn (via the assembled system prompt).

## Emission condition

| Contact state                              | Warning present in prompt? |
|--------------------------------------------|----------------------------|
| `@contact.present?` and `@contact.notes.any?` | YES                     |
| `@contact.present?` and no notes            | NO                         |
| no contact (`@contact` nil)                 | NO (section not rendered)  |

The warning is appended within `contact_context_section`, alongside (and independent of) the
existing `identity_warning` and `phone_request_warning`; enabling it must not alter their presence,
ordering, or text.

## Required semantic assertions (the warning text MUST convey all three)

1. **Notes are past summaries, not current facts** — the notes describe prior, already-concluded
   conversations, not a request or fact active in the current turn. (FR-001)
2. **Personalization/anticipation is allowed and encouraged** — notes MAY/SHOULD be used to
   personalize the approach and proactively anticipate the contact's likely current interest,
   including nudging toward scheduling. (FR-003)
3. **Never a standalone handoff justification** — a note alone NEVER justifies `handover_to_human`;
   the transfer signal must come from the current conversation's own messages. (FR-002)

## Style constraints

- pt-BR, `AVISO:`-prefixed just-in-time paragraph, matching `identity_warning`/`phone_request_warning`.
- Names the concrete tool `handover_to_human`.
- No i18n key required (consistent with the sibling `AVISO:` warnings, which are inline pt-BR).

## Non-goals

- Does NOT instruct Scout to hide, drop, or de-duplicate any note.
- Does NOT weaken or delay a genuine present-turn human request (that path is unchanged; FR-004).
- Does NOT touch `guardrails_section` or any other prompt section.
