# Contract: turn prompt block assembly (v2 execution path only — v1 is untouched, FR-017)

`Custom::ScoutV2::TurnRunner` composes exactly one `RubyLLM::Chat` system instruction per turn, by
concatenating ordered blocks with a blank line between each (FR-018):

```
[Instructions block]           always present
[Playbook index block]         always present, even when it lists zero playbooks
[Playbook body + pending]      present only when a playbook is forced by conversation state
```

## Block 1 — Instructions (`Custom::ScoutV2::Instructions::Builder.call(scout:)`)

Exactly four sections, this fixed order, nothing else appended (FR-001):

| Header | Source | Scout-configurable? |
|---|---|---|
| `[Identity]` | Fixed prose (role + topic scope) + `scout.name`/`scout.account.name` interpolation | No (data only) |
| `[Communication]` | `scout.tone` enum → 1 of 5 fixed sentences, `scout.response_length` enum → 1 of 3 fixed sentences, `scout.greeting` (squished to one line) quoted or a generic fallback — either way scoped to the first reply of the conversation, never repeated | Yes — enum values + greeting text |
| `[Memory]` | Fixed prose (retention policy) — `Instructions::Builder::MEMORY_SECTION` | No |
| `[Safety]` | Fixed prose (anti-hallucination, anti-false-promise, detect-and-mirror language, commercial scope + refusal rule, knowledge-base-exists declaration) — `Instructions::Builder::SAFETY_SECTION` | No |

Changing `scout.tone`, `scout.response_length`, or `scout.greeting` changes only the
`[Communication]` section's content on the next call — no other section is affected, and nothing
is achieved by editing prose (FR-007).

## Block 2 — Playbook index (`Custom::ScoutV2::Playbook::IndexBuilder.call(catalog)`)

```
[Playbook Index]
- <playbook.name>: <playbook.trigger>
- <playbook.name>: <playbook.trigger>
```

One line per entry currently returned by `Custom::ScoutV2::Playbook::Loader.load_all` (FR-009,
FR-010) — no separate "enabled" flag exists; catalog membership *is* enabled. When the catalog is
empty, the block is still emitted with the header, followed by a single non-list line stating none
are enabled (FR-018, SC-007) — the block is never blank/omitted.

## Block 3 — Forced playbook body (unchanged from the pre-existing state-activation path)

Present only when `Router.call` returns a non-blank `decision.playbook` (i.e. a playbook is
currently forced by conversation state, per `research.md` §2's definition — state-matched *or*
continuing from a prior activation, state- or trigger-based). Content: `playbook.body.strip`,
followed by a pending-required-fields block when the active opportunity has any (unchanged
formatting/logic from before this feature, now in `Custom::ScoutV2::Playbook::PendingFieldsFormatter`).

## Removed by this feature (FR-019)

`TurnRunner::FALLBACK_INSTRUCTIONS` — the pre-existing placeholder shown when no playbook was
forced, which told the model to "use the knowledge base when useful" (violating FR-006's "must
not instruct when to consult it"). Superseded by Block 1 + Block 2 always being present regardless
of whether a playbook is forced.
