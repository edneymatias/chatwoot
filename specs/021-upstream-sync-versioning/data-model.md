# Phase 1 Data Model: Upstream Sync, Branch Rebranding & Versioning Scheme

This feature has no application data model (no new database tables, no new Ruby/JS domain
objects). The "entities" here are git/process concepts already named in the spec's Key Entities
section, documented with their attributes and lifecycle so `tasks.md` can reference them
precisely.

## Fork branch (`ichatr-main`)

**Represents**: The fork's single permanent long-term branch, renamed from `matias-kanban`.

**Attributes**:
- `name`: `ichatr-main` (post-rename); previously `matias-kanban`
- `remote_ref`: `origin/ichatr-main`
- `merge_target_for`: all future feature branches, hotfixes, and upstream syncs (via PR)

**Lifecycle**:
1. `matias-kanban` (pre-sync) — receives the `develop` merge, resolves conflicts, passes the
   validation gate.
2. `matias-kanban` → renamed to `ichatr-main` (local `git branch -m`), pushed to `origin`.
3. `ichatr-main` (steady state) — permanent; never renamed again by this feature; all subsequent
   work branches off it and merges back via PR.

**Invariant**: Exactly one such branch exists at a time; `origin/matias-kanban` MUST NOT exist
once step 2 completes (FR-001).

## Mirror branch (`develop`)

**Represents**: The local reference branch the sync script's `--audit` mode merge-bases against
by default.

**Attributes**:
- `name`: `develop`
- `tracks`: `upstream/develop`, fast-forward only

**Lifecycle**: Fast-forwarded on every sync (this phase's sync, and every future one); never
receives a local commit. State is fully determined by `upstream/develop` at any point in time.

**Invariant**: `git log develop..upstream/develop` and `git log upstream/develop..develop` are
both empty immediately after any fast-forward (i.e., `develop` == `upstream/develop`).

## Sync manifest gate

**Represents**: The existing `bin/sync-custom-module-hooks` script's `--check` and `--audit`
modes, used unmodified as this feature's pass/fail validation gate.

**Attributes** (as already implemented by the script, not modified by this feature):
- `MANIFEST`: array of `{ file, anchor, insert }` entries — the source of truth for tracked
  wiring-point insertions in core files
- `--check` output: for each `MANIFEST` entry, present/missing in its target file
- `--audit <base_ref>` output: for each core file modified since `base_ref` and not in the
  script's `excluded`/`out_of_scope` list, `covered` (has a `MANIFEST` entry) or `gap` (does not)

**Lifecycle per gap** (introduced by this feature's clarification, not a script code change):
`gap` → triaged by maintainer → one of:
- `manifest_entry` — added to `MANIFEST` in the script
- `excluded` — added to the script's `excluded`/`out_of_scope` list
- `follow_up` — logged as a follow-up item outside this phase; sync fails loudly citing the file
  and the upstream change responsible (FR-006a)

**Invariant**: The sync is not "done" (FR-006) until `--check` reports zero missing entries,
`--audit` reports zero gaps left in the raw `gap` state (every gap has moved to one of the three
terminal states above), and the full test suites pass.

## Fork version tag

**Represents**: The tag format that will identify a fork release relative to its upstream base,
documented by this feature but not cut by it (FR-007).

**Attributes**:
- `upstream_base_version`: sourced from `package.json`'s `version` field at release-cut time
  (e.g. `4.16.2`)
- `N`: positive integer, scoped to `upstream_base_version`
- `tag`: `<upstream_base_version>-ichatr.<N>` (e.g. `4.16.2-ichatr.1`)

**Lifecycle**:
- First release cut against a given `upstream_base_version` → `N = 1`
- Additional release cut against the *same* `upstream_base_version` (e.g. a hotfix) → `N`
  increments
- First release cut after syncing to a *new* `upstream_base_version` → `N` resets to `1`

**Invariant**: `N` is never compared or carried across different `upstream_base_version` values.
