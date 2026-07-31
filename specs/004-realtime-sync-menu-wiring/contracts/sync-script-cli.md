# Contract: `bin/sync-custom-module-hooks` CLI

## Invocation

```
docker compose exec rails bin/sync-custom-module-hooks --check
docker compose exec rails bin/sync-custom-module-hooks --apply
docker compose exec rails bin/sync-custom-module-hooks        # defaults to --apply
```

## Modes

- `--check`: read-only. For every manifest entry, report `present` (insert text already found in
  file) or `missing` (anchor found but insert text absent) or `anchor_not_found` (anchor string
  itself missing from the file). Never writes. Exit `0` only if every entry is `present`; non-zero
  otherwise.
- `--apply` (default): for every manifest entry already `present`, skip (no-op — FR-011). For
  every entry `missing` its anchor, insert the text immediately adjacent to the anchor and write
  the file. For every entry whose anchor is `anchor_not_found`, record a failure for that file and
  do not apply any other pending entries for that same file (FR-006), but continue processing
  other files. Exit non-zero if any entry ended `anchor_not_found`.

## Output contract

On any `anchor_not_found`, stderr MUST include, at minimum, the file path and the exact anchor
string that could not be located — e.g.:

```
ERROR: anchor not found in app/javascript/dashboard/helper/actionCable.js: `'conversation.updated': this.onConversationUpdated,`
```

On a clean `--check` run, stdout reports a per-file summary and a final `All N wiring points
present.` line with exit code `0`.

## Manifest location

A single array of hashes at the top of the script (or a required sibling file), each entry:
`{ file:, anchor:, insert:, indent: (optional) }` — see `data-model.md`'s "Wiring point" entity.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | All manifest entries present (check) or successfully applied/already-present (apply) |
| non-zero | At least one anchor could not be located (fail-fast per FR-006) |
