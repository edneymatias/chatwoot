# Contract: turn prompt/tool assembly (v2 execution path only — v1 is untouched, FR-015)

Delta on top of `084-scout-instructions-open-playbook/contracts/turn_prompt_blocks.md`, which this
document supersedes for the parts that change. Block 1 (`[Identity]`/`[Communication]`/`[Memory]`/
`[Safety]`) and Block 3 (pinned playbook body + pending fields) are **unchanged** — reproduced here
only to show where Block 2 now sits relative to them.

```
[Instructions block]           always present, unchanged content/composition
[Playbook index block]         always present — now lists the openable set, not the full catalog
[Playbook body + pending]      present only when a playbook is pinned (`decision.playbook.present?`) — unchanged
```

## What changed: Block 2's input

`Custom::ScoutV2::Playbook::IndexBuilder.call(openable)` — same method, same list format
(`[Playbook Index]` header + one `- name: trigger` line per entry), but its argument is now
`Custom::ScoutV2::Playbook::OpenableSet.call(catalog:, pinned: decision.playbook)` (`data-model.md` §3)
instead of the raw loaded `catalog`. When that set is empty, the header is followed by
`IndexBuilder::EMPTY_INDEX_LINE` — `Nenhum playbook disponível para abrir neste turno.` — which
replaces Brief 04's `EMPTY_CATALOG_LINE` ("Nenhum procedimento específico habilitado no catálogo.").
The old line would contradict Block 3 when a procedure is pinned and no situational playbook exists
(FR-003). Concretely:

| Turn state | Index block lists |
|---|---|
| Nothing pinned, catalog non-empty | Every playbook in the catalog (situational **and** `when_state`-bearing) — same as Brief 04 |
| Nothing pinned, catalog empty | `EMPTY_INDEX_LINE` (**changed wording**) |
| A procedure pinned, ≥1 situational playbook | Only playbooks with `when_state.blank?` (situational) — **new**, this is the fix Brief 11 exists to make |
| A procedure pinned, no situational playbook | `EMPTY_INDEX_LINE` (**new**: Brief 04 listed the full catalog here, e.g. the shipped `qualificacao`) |

"Pinned" here and throughout means `decision.playbook.present?` — the spec's Key Entity
"Pinned Procedure": a fresh state match or a stored pin of either `activation_reason`.

This is also, verbatim, the set `open_playbook` will accept this turn (`contracts/open_playbook_tool.md`)
— one list, one acceptance rule, computed once per turn.

## What's new: mid-turn instructions/tools replacement (the "interruption takeover")

Not a new *block* in the sense above (Blocks 1/2/3 describe the **initial** system message for the
turn) — it's what the system message and tool catalog become for every `chat.ask` tool-loop
iteration **after** `open_playbook` resolves a situational playbook (`open_playbook_tool.md`, Path
A). From that iteration onward, for the rest of the same top-level turn:

```
[Instructions block]           unchanged content — same builder, same scout config
[Playbook index block]         unchanged content — same openable set as the turn's initial one
```
— i.e. exactly Blocks 1+2 with **no Block 3**, even if Block 3 was present a moment ago. This is
literally `TurnRunner#build_instructions(nil, nil, openable)`, computed once at turn start and
handed to `Tools::OpenPlaybook` as `TurnSetup#baseline_instructions` (`data-model.md` §4) — not
recomputed at takeover time, since neither the scout's config nor the openable set changes within a
turn.

Tool catalog for the same iteration onward: the always-on tools (`TurnRunner`'s single
`always_on_tools` list — today `search_knowledge_base`, injected as `TurnSetup#baseline_tools`), plus
`open_playbook` (FR-009), plus whatever the newly opened situational playbook's own `tools:`
frontmatter declares. Nothing is carried over from a procedure that was pinned before the
interruption. A second interruption opened later in the same turn repeats this exactly, replacing
the first interruption's tools in the same way (FR-010). Tool calls that come later in the same
model response resolve against this new catalog (FR-016, `open_playbook_tool.md`).

## Initial tool catalog (turn start)

Registered one at a time via `chat.with_tool` (unchanged mechanism), in this order:

| Turn state | Tools |
|---|---|
| Nothing pinned, catalog non-empty | always-on + `open_playbook` |
| Nothing pinned, catalog empty | always-on only (**changed**: Brief 04 offered `open_playbook` here) |
| Procedure pinned, ≥1 situational playbook in catalog | always-on + pinned playbook's declared tools + `open_playbook` (**new**) |
| Procedure pinned, no situational playbook | always-on + pinned playbook's declared tools (unchanged) |

## Unchanged from Brief 04 (reproduced for completeness)

- Block 1 (`Instructions::Builder.call(scout:)`): 4 fixed sections, scout-configurable content only
  within `[Communication]`.
- Block 3: present only when `Router.call` returns a non-blank `decision.playbook` at the *start*
  of the turn — this predicate is evaluated once, before any interruption can run, and is never
  re-evaluated mid-turn (Decision 5/FR-011: the interruption doesn't change what's pinned, so there
  is nothing to re-evaluate).
- `TurnRunner::FALLBACK_INSTRUCTIONS` stays removed (Brief 04 FR-019).
