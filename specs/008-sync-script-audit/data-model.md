# Phase 1 Data Model: Sync Script Audit Mode

This feature has no persisted database entities — it operates entirely on git history and an
in-source Ruby array. The "entities" below are in-memory/source-level structures relevant to the
audit's logic, carried over from the Key Entities section of `spec.md`.

## MANIFEST entry (existing, extended with new data)

Already defined by the current script; unchanged in shape. Gains 8 new entries (per
`docs/kanban/ciclo 2/06-sync-script-update/spec10.md`'s findings) plus two comma-safe JSON-insert
entries.

| Field | Type | Notes |
|---|---|---|
| `file` | String (path) | Path relative to repo root |
| `anchor` | String | Exact text the insert is placed after |
| `insert` | String | Text spliced in immediately after the anchor |

No validation rules or lifecycle beyond what the script already enforces (`--check` fails loudly
if `file` doesn't exist or `anchor` isn't found).

## Exclusion rule

New concept, introduced by this feature (FR-003/FR-004).

| Field | Type | Notes |
|---|---|---|
| `kind` | Symbol/tag | `:path` (plain path/glob/regex match) or `:content` (needs diff-content inspection) |
| `pattern` | String/Regexp | For `:path` kind, matched against the file path |
| `matcher` | Proc/method (for `:content` kind only) | Given the file's diff hunks, returns true only if every changed line falls inside the annotate-gem schema-comment block |

Only one `:content`-kind rule exists in this feature (the annotate-gem rule); everything else
(`db/schema.rb`, `spec/**`/`specs/**`/docs/`*.md`, non-English locales) is `:path`-kind. The
iteration/exclusion pipeline treats both kinds uniformly (apply each rule, drop the file if any
rule matches) — only the per-rule "does this match" evaluator differs, keeping the control flow
data-driven per FR-004.

**No lifecycle/state transitions** — exclusion rules are static configuration data evaluated fresh
on each audit run.

## Audit finding

The output of one audit invocation — not persisted, printed to stdout.

| Field | Type | Notes |
|---|---|---|
| `file` | String (path) | The modified core file being reported |
| `status` | Enum: `covered` \| `gap` | `covered` if a `MANIFEST` entry targets this file; `gap` otherwise |

Relationships:
- Every `Audit finding` corresponds to exactly one file from the modified (`M`-status) diff
  between `BASE_REF` and HEAD+working-tree, after exclusion rules have removed non-candidates.
- A finding's `covered` status is derived by checking membership against the `file` values already
  present in `MANIFEST` — no separate lookup table is needed.

**No validation rules or state transitions** — a finding is a pure, stateless classification
computed once per audit run.
