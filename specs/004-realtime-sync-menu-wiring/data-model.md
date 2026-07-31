# Data Model: Realtime Sync & Menu/Route Wiring

No new persisted entities or schema changes in this phase — `Opportunity` and `PipelineStage`
(both from Phase 1) are reused as-is. This phase adds two transient/process entities only.

## Opportunity live update notification (transient — not persisted)

Built in `custom/app/models/opportunity.rb`'s `after_commit` callback and passed straight to
`ActionCableBroadcastJob.perform_later`; never stored.

| Field | Source | Notes |
|---|---|---|
| `id` | `Opportunity#id` | Identifies which opportunity changed |
| `pipeline_stage_id` | `Opportunity#pipeline_stage_id` | Lets the board move the card's column without a fetch |
| `status` | `Opportunity#status` (enum: `open`/`won`/`lost`) | |
| `contact_id` | `Opportunity#contact_id` | |
| `assignee_id` | `Opportunity#assignee_id` | Nullable |
| `updated_at` | `Opportunity#updated_at` | |
| `account_id` | `Opportunity#account_id` | Merged in for routing/logging, consistent with every other `account_token`-broadcast payload in `ActionCableListener#broadcast` |

Delivered as: `{ event: 'opportunity_updated', data: <above hash> }` over the `account_#{account_id}`
ActionCable stream (see `research.md` §1).

## Wiring point (manifest entry — lives in the sync script, not the database)

One entry in `bin/sync-custom-module-hooks`'s manifest array.

| Field | Meaning |
|---|---|
| `file` | Path to the shared/upstream file this entry targets |
| `anchor` | Exact existing string in `file` used to locate the insertion point |
| `insert` | The exact text to add adjacent to `anchor` (idempotency check: skip if already present) |
| `indent` (optional) | Explicit indentation override, if not inferable from `anchor`'s line |

No relationships between entries; each is checked/applied independently, but a failure on one
entry only halts further entries **for that same file** (FR-006), not the whole run.

## Wiring check/apply run (process outcome — not persisted)

The script's exit-time result: a list of `{ file, anchor, status: present|missing|inserted }` per
manifest entry, and an overall exit code (`0` = all present/inserted, non-zero = at least one
`missing`). This is printed to stdout/stderr for the maintainer; nothing is written to disk beyond
the target files themselves in `--apply` mode.
