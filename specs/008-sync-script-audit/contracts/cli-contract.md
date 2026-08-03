# CLI Contract: `bin/sync-custom-module-hooks --audit`

This is the external interface this feature exposes: a new mode on an existing CLI script.
`--check` and `--apply` are pre-existing and unchanged by this feature except that `--check` must
continue to pass against the enlarged `MANIFEST` (FR-008).

## Invocation

```
bin/sync-custom-module-hooks --audit [BASE_REF]
```

- `BASE_REF` (optional, positional): any git ref/SHA resolvable in the current repository.
  - **Default** (omitted): the merge-base of the current branch and `develop`.
  - **Invalid/unresolvable ref, or no merge-base with the current branch**: the script MUST exit
    non-zero with a clear error message (fail loudly — this is a misconfigured invocation, not a
    "zero gaps" result, per spec.md's edge cases).

## Output contract

The script prints two labeled sections to stdout, one line per file:

```
covered   <path>
covered   <path>
...
gap       <path>   (needs MANIFEST entry)
gap       <path>   (needs MANIFEST entry)
...
```

- Files are grouped so all `covered` lines print before all `gap` lines (matches the "two buckets"
  framing in FR-005 and the source phase doc).
- If there are zero gaps, the script still prints the `covered` section (if any) and a final
  summary line, e.g. `0 gaps found.` — this is the exact condition User Story 3 / SC-004 checks
  for after the manifest update lands.
- Files matched by an exclusion rule (FR-003) never appear in either section — they are silently
  dropped before classification, not listed as a third category.

## Exit status

| Condition | Exit code |
|---|---|
| Audit ran successfully, regardless of gap count | `0` |
| `BASE_REF` given but unresolvable, or no merge-base found | non-zero |

Audit mode is a **reporting** tool, not a gate: per FR-005/FR-009 its job is to inform a
maintainer, so a non-zero gap count is not itself a failure condition (mirrors that `--check` is
the mode that fails/succeeds; `--audit` is read-only discovery). This matches how the source
phase doc uses `--audit` as an acceptance check by inspecting its printed output ("should report
zero gaps"), not its exit code.

## Existing contracts, unchanged

- `bin/sync-custom-module-hooks --check` — exit `0` iff every `MANIFEST` entry's `file` exists and
  either already contains `insert` or contains `anchor` to insert after; must still pass after the
  8 new entries are added (FR-006/FR-008).
- `bin/sync-custom-module-hooks --apply` (or no flag) — unchanged; not exercised by this feature
  beyond the existing spec coverage.
