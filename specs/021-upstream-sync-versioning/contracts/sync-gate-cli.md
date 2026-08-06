# Contract: Sync Validation Gate (CLI)

This feature's only "interface" is the existing `bin/sync-custom-module-hooks` CLI, used
unmodified as the pass/fail gate for the sync (FR-006/FR-006a). This document specifies the
contract this feature relies on — not a new interface being built.

## `bin/sync-custom-module-hooks --check`

**Purpose**: Verify every `MANIFEST` entry's `insert` text is still present in its `file`,
adjacent to its `anchor`, after the merge.

**Preconditions**: Run from repo root, on the post-merge working tree (`ichatr-main` or
pre-rename `matias-kanban`, HEAD at the merge commit or later).

**Inputs**: None (reads `MANIFEST` constant baked into the script and the current working tree).

**Outputs / exit contract**:
- Exit `0`: every `MANIFEST` entry found in its target file.
- Non-zero exit: at least one `MANIFEST` entry missing — merge conflict resolution silently
  dropped a fork customization. **Sync gate MUST treat this as a hard failure** (FR-006, gate
  step 1).

## `bin/sync-custom-module-hooks --audit [BASE_REF]`

**Purpose**: Detect core-file changes since `BASE_REF` that aren't yet covered by a `MANIFEST`
entry.

**Preconditions**: Run from repo root, on the post-merge working tree.

**Inputs**:
- `BASE_REF` (optional): a resolvable git ref. If omitted, defaults to
  `git merge-base <current-branch> develop`.

**Outputs / exit contract**:
- For each file changed (`git diff --name-status BASE_REF...HEAD` plus any uncommitted working-tree
  changes) that is not excluded by the script's built-in `excluded`/`out_of_scope` rules:
  - Listed under `covered` if it has a `MANIFEST` entry.
  - Listed under `gap` if it does not.
- **Consumer contract for this feature** (not enforced by the script itself, enforced by the
  maintainer/process per FR-006/FR-006a): every `gap` entry MUST be resolved to exactly one of:
  1. A new `MANIFEST` entry added to the script (re-run `--audit` to confirm it moves to
     `covered`), or
  2. Added to the script's `excluded`/`out_of_scope` list (re-run `--audit` to confirm it no
     longer appears at all), or
  3. Logged as a follow-up item, with the sync run treated as failed for this file until that
     follow-up is resolved — the sync process must surface the file path and a description of
     the upstream change responsible when taking this path.
- The sync is not "done" until a final `--audit` run against the merge-base shows zero entries
  left in the raw `gap` state (every gap has moved to `covered`, `excluded`, or an explicitly
  logged follow-up).

## Test suites (consumed, not modified)

**Purpose**: Final gate step (FR-006, step 3).

**Contract**:
- `bundle exec rspec` MUST exit `0`.
- `pnpm test` MUST exit `0`.
- Both MUST be run against the post-merge tree, after the manifest gate above passes — not before,
  and not as a substitute for it.
