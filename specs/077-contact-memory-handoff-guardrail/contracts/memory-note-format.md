# Contract: Dated Memory-Note Content Format

**Surface**: the `content` value persisted for each `Note` created by
`Custom::Scout::ContactNotesService#generate_and_update_notes`.

**Producer**: `Custom::Scout::ContactNotesService` (`custom/app/services/custom/scout/contact_notes_service.rb`).

**Consumers**:
- Scout's prompt, via `LlmFormatter::ContactLlmFormatter#build_notes` (renders `content` verbatim —
  upstream/shared, **not** modified).
- The dashboard contact Notes view (renders `content` verbatim, plus its own independent timestamp).

## Format

```
[DD/MM/YYYY] <summary text>
```

- `DD/MM/YYYY` = generation date (`%d/%m/%Y`) in the conversation's effective timezone
  (inbox timezone → account default → app default).
- Exactly one space between the closing `]` and the summary.
- Applied per note, only when the generated summary is present (no bare `[DD/MM/YYYY]` note).

## Invariants

| Case                                                   | Behavior                              |
|--------------------------------------------------------|---------------------------------------|
| New note generated after this change                   | `content` starts with `[DD/MM/YYYY] ` |
| Blank/empty generated summary                          | Not persisted (unchanged guard)       |
| Note that existed before this change                   | Left unchanged — no retroactive date  |
| LLM generation error                                   | Returns `[]`, persists nothing (unchanged) |

## Return value

`generate_and_update_notes` returns the array of note strings it persisted. Per the dated contract,
those strings now include the date prefix (the return value equals the persisted `content`). The
existing spec assertion comparing the return array to bare summaries is updated accordingly.
