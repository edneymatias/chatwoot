# Feature Specification: Upstream Sync, Branch Rebranding & Versioning Scheme

**Feature Branch**: `021-upstream-sync-versioning`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "Phase 30: Upstream Sync, Branch Rebranding & Versioning Scheme — catch the fork's working branch up with upstream Chatwoot (61 commits behind), rename `matias-kanban` to the fork's permanent branch `ichatr-main`, keep `develop` as a plain upstream mirror, validate the merge against the sync-script manifest/audit gate and full test suite, and settle the fork's version-tag scheme ahead of later release-engineering phases. Derived from `docs/kanban/ciclo 7/10-upstream-sync-and-versioning/spec30.md`."

## Clarifications

### Session 2026-08-06

- Q: When upstream and the fork both meaningfully changed the same logic in a wiring file (a
  semantic conflict, not just a textual one), is there a default rule for which side wins? → A:
  No fixed default. Each such conflict is judged case-by-case, guided by the fork's existing
  "Upstream Compatibility First" principle: the fork is built on top of what Chatwoot provides, so
  a fork customization must be re-evaluated against upstream's change rather than blindly
  reasserted — otherwise the same conflict recurs on every future sync.
- Q: If an `--audit` gap turns out to need real code changes to re-integrate with upstream's new
  version of a file (not just a manifest/exclusion-list entry), is that rework in scope for this
  sync phase? → A: No — this phase's gate stops at the merge building green with tests passing.
  Any gap that needs more than a manifest/exclusion entry fails the sync loudly, pointing exactly
  at the file/gap in question and what changed in upstream that caused it, and is logged as a
  follow-up item rather than silently deferred or expanded into ad hoc rework within this phase.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Maintainer brings the fork current with upstream without losing customizations (Priority: P1)

A maintainer needs the fork's working branch to include the latest 61 commits from upstream
Chatwoot's `develop` branch before any release-engineering work can begin. They fast-forward a
mirror of upstream, merge it into the fork's branch, resolve any conflicts in the core files the
fork customizes, and confirm — through the sync script's manifest gate and the full test suite —
that no existing customization was silently dropped during conflict resolution.

**Why this priority**: This is the blocking prerequisite for every later release-engineering
phase (table-prefix rename, CI/CD, release cut). None of that work can safely start on a stale,
61-commits-behind base.

**Independent Test**: Can be fully tested by performing the sync end-to-end on a real checkout and
confirming: the merge completes, `bin/sync-custom-module-hooks --check` reports every existing
manifest entry still present, `bin/sync-custom-module-hooks --audit` reports zero untriaged gaps,
and the full test suite (`bundle exec rspec`, `pnpm test`) passes.

**Acceptance Scenarios**:

1. **Given** the local `develop` branch has zero local-only commits, **When** the maintainer
   fast-forwards it to `upstream/develop`, **Then** the fast-forward completes cleanly with no
   conflict resolution required.
2. **Given** `develop` is caught up with upstream, **When** the maintainer merges it into the
   fork's working branch with a single merge commit, **Then** conflicts (expected primarily in
   files like `dashboard.routes.js`, `Sidebar.vue`, `actionCable.js`, `store/index.js`,
   `settings.routes.js`, `automationHelper.js`) are resolved case-by-case — re-evaluating each
   fork customization against upstream's change rather than reflexively keeping either side — and
   the build is green.
3. **Given** the merge has landed, **When** the maintainer runs
   `bin/sync-custom-module-hooks --check`, **Then** every existing manifest insertion is confirmed
   still present in its target file.
4. **Given** the merge has landed, **When** the maintainer runs
   `bin/sync-custom-module-hooks --audit`, **Then** every core file changed since the merge-base
   that lacks a manifest entry is reported as a gap, and each gap is triaged: either added as a
   manifest entry, added to the script's excluded/out-of-scope list, or — if it needs real code
   rework to re-integrate with upstream's change — logged as a follow-up item rather than fixed
   inline in this phase.
5. **Given** a gap requires more than a manifest/exclusion entry to resolve, **When** the
   maintainer triages it, **Then** the sync fails loudly, naming the exact file/gap and the
   upstream change that caused it, instead of silently passing or expanding into ad hoc rework.
6. **Given** the manifest gate passes and any follow-up items are logged, **When** the maintainer
   runs the full backend and frontend test suites, **Then** both pass before the sync is
   considered complete.

---

### User Story 2 - Fork gets a permanent branch identity instead of a feature-branch name (Priority: P1)

The fork is becoming a standalone product with its own release cadence, not a temporary feature
branch on top of Chatwoot. A maintainer renames the branch that currently reads like a personal
feature branch (`matias-kanban`) to a name that correctly identifies it as the fork's permanent
long-term branch (`ichatr-main`), so all future work — this release, v1.1, v2.0, ongoing features —
has one unambiguous branch to target.

**Why this priority**: Every future sync, every future feature branch, and every future release
depends on there being one correctly-named, permanent branch to merge into. Doing this after the
sync (rather than before) avoids re-doing the rename mid-conflict-resolution.

**Independent Test**: Can be fully tested by confirming `ichatr-main` exists locally and on
`origin`, `origin/matias-kanban` no longer exists, and a new feature branch cut from `ichatr-main`
can be opened and merged back via PR.

**Acceptance Scenarios**:

1. **Given** the sync onto `matias-kanban` is complete, **When** the maintainer renames it to
   `ichatr-main` and pushes to `origin`, **Then** `origin/ichatr-main` exists and the old
   `origin/matias-kanban` ref is deleted.
2. **Given** `ichatr-main` is the fork's permanent branch, **When** any future work (feature,
   hotfix, or the next upstream sync) is started, **Then** it branches off `ichatr-main` and merges
   back into it via PR, with no separate `release/*` branch scheme in use.
3. **Given** `develop` exists as the sync reference, **When** any contributor looks for where
   direct work should happen, **Then** they find `develop` is never committed to directly — it
   stays a fast-forward-only mirror of `upstream/develop` used by
   `bin/sync-custom-module-hooks --audit`'s default merge-base comparison.

---

### User Story 3 - Release engineer has an unambiguous version-tag scheme for future releases (Priority: P2)

Before any release-engineering phase (table-prefix rename, CI/CD, release cut) needs to cut a
version tag or Docker image tag, the fork's versioning scheme is already decided, so those later
phases don't have to stop and re-litigate it.

**Why this priority**: Lower priority than the sync and rename themselves because no tag is
actually cut in this phase — but the scheme must be settled now so later phases have a stable
target to build tooling against.

**Independent Test**: Can be fully tested by confirming the documented scheme unambiguously
produces the next tag for both a fresh-upstream-base release and a same-base hotfix release,
without needing further discussion.

**Acceptance Scenarios**:

1. **Given** the fork is releasing against upstream base `4.16.2`, **When** the first fork release
   is cut against that base, **Then** it is tagged `4.16.2-ichatr.1`.
2. **Given** a hotfix is needed against the same upstream base without pulling new upstream
   commits, **When** the next fork release is cut, **Then** it is tagged `4.16.2-ichatr.2` (`N`
   incremented, base unchanged).
3. **Given** the fork syncs to a new upstream base (e.g. `4.17.0`), **When** the first release is
   cut against that new base, **Then** `N` resets to `.1` (`4.17.0-ichatr.1`) regardless of how
   high `N` reached on the previous base.
4. **Given** a version string must work as a git tag, a Docker image tag, and a `package.json`
   `version` field without translation, **When** the tag is formatted, **Then** it uses a hyphen
   (not `+`) to separate the upstream base from the fork identifier and increment.

---

### Edge Cases

- What happens if a manifest-covered core file's conflict resolution accidentally drops the
  fork's customization during the merge? → Caught by `bin/sync-custom-module-hooks --check` before
  the sync is considered done; the sync is not complete until this passes.
- What happens if a core file was modified since the last manifest update but isn't a real wiring
  point (e.g. incidental churn)? → Triaged by hand into the script's `excluded`/`out_of_scope`
  list rather than added as a manifest entry.
- What happens when upstream and the fork both meaningfully changed the same logic in a wiring
  file (a semantic conflict, not just a textual one)? → No fixed default side wins; it's judged
  case-by-case, re-evaluating the fork's customization against upstream's new behavior per the
  "Upstream Compatibility First" principle, rather than reflexively keeping the fork's prior
  implementation.
- What happens if an `--audit` gap needs real code changes to re-integrate with upstream's version
  of a file, not just a manifest/exclusion-list entry? → Out of scope for this phase's merge gate;
  the sync fails loudly identifying the exact file and upstream change responsible, and the
  rework is logged as a follow-up item rather than done inline here.
- What happens if `develop` has local-only commits at sync time (deviating from being a pure
  mirror)? → Out of scope for this pass; today's `develop` is confirmed to have zero local-only
  commits, so no conflict-resolution path is defined for that case.
- What happens to in-flight branches still referencing `matias-kanban` after the rename? → Not
  addressed by this phase; it covers the rename and ref cleanup on `origin`, not migration of
  other contributors' local branches.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The fork MUST rename its working branch `matias-kanban` to `ichatr-main`, push it to
  `origin`, and delete the old `origin/matias-kanban` ref.
- **FR-002**: `ichatr-main` MUST become the fork's single permanent long-term branch: all future
  work (current release, subsequent releases, ongoing features) branches off it and merges back
  via PR, with no separate `release/*` branch scheme.
- **FR-003**: The local `develop` branch MUST be kept as a plain, fast-forward-only mirror of
  `upstream/develop`, never carrying its own commits, existing solely as the reference branch the
  sync script's audit mode merge-bases against by default.
- **FR-004**: The sync MUST fast-forward local `develop` to `upstream/develop` before any merge
  into `ichatr-main` happens.
- **FR-005**: The sync MUST merge `develop` into `ichatr-main` using a single merge commit (not a
  rebase), so conflicts are resolved once rather than replayed across the fork's existing commit
  history. There is no fixed default for which side (upstream or fork) wins a semantic conflict —
  each is judged case-by-case, re-evaluating the fork's customization against upstream's change
  rather than reflexively keeping either side's prior implementation.
- **FR-006**: The sync MUST NOT be considered complete until, in order: (1) the sync script's
  `--check` mode confirms every existing manifest entry is still present post-merge, (2) the sync
  script's `--audit` mode reports zero untriaged gaps in core-file changes since the merge-base —
  where "triaged" means a gap is either added as a manifest entry, added to the
  `excluded`/`out_of_scope` list, or, if it needs real code rework to re-integrate with upstream's
  change, logged as a follow-up item — and (3) the full backend and frontend test suites pass.
- **FR-006a**: If an `--audit` gap needs more than a manifest/exclusion entry to resolve, the sync
  MUST fail loudly, identifying the exact file/gap and the upstream change that caused it, rather
  than passing silently or expanding into ad hoc rework within this phase.
- **FR-007**: This phase MUST NOT cut any version tag or Docker image — that is explicitly
  deferred to a later release-cut phase, after table-prefix rename and CI/CD are in place and
  validated in staging.
- **FR-008**: Fork releases MUST be tagged using the scheme
  `<upstream-base-version>-ichatr.<N>` (e.g. `4.16.2-ichatr.1`), using a hyphen so the identifier
  is valid unmodified as a git tag, a Docker image tag, and a `package.json` `version` field.
- **FR-009**: `N` MUST be scoped to the upstream base version, not global: it increments only for
  an additional fork release cut against the same upstream base (e.g. a hotfix requiring no new
  upstream commits), and MUST reset to `.1` the first time a release is cut against a newly synced
  upstream base, regardless of how high `N` reached on the previous base.

### Key Entities

- **Fork branch (`ichatr-main`)**: The fork's permanent long-term branch, renamed from
  `matias-kanban`; target of all future feature work and future upstream syncs.
- **Mirror branch (`develop`)**: A local branch that only ever fast-forwards to
  `upstream/develop`; the fixed reference point the sync script's audit compares against.
- **Sync manifest gate**: The existing `bin/sync-custom-module-hooks` script's `--check` and
  `--audit` modes, used here as the pass/fail gate for whether a sync merge preserved and fully
  tracked the fork's customizations.
- **Fork version tag**: A tag of the form `<upstream-base-version>-ichatr.<N>` identifying a fork
  release relative to the upstream Chatwoot version it's built on.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The fork's working branch contains 100% of the 61 upstream commits it was behind,
  with zero manifest entries lost in the process (verified by a clean `--check` pass).
- **SC-002**: The `--audit` gate reports zero untriaged core-file gaps at sync completion — every
  gap found is either converted into a manifest entry, explicitly excluded, or logged as a
  follow-up item with the specific file and upstream change identified.
- **SC-003**: 100% of the backend and frontend test suites pass on the merged branch before the
  sync is marked done.
- **SC-004**: Within one PR cycle after this phase lands, a contributor can correctly identify
  `ichatr-main` as the branch to target for new work without needing to ask, and no work lands on
  `origin/matias-kanban` (the ref no longer exists).
- **SC-005**: Given any two release scenarios (new upstream base vs. same-base hotfix), a release
  engineer can derive the correct next version tag from the documented scheme alone, with zero
  ambiguity or need for discussion.

## Assumptions

- The local `develop` branch has zero local-only commits at sync time, as already confirmed, so
  the fast-forward step needs no conflict-resolution path in this phase.
- Conflict resolution during the `develop` → `ichatr-main` merge is expected primarily in the core
  files already tracked by the sync manifest; files outside that set are lower-risk but still
  covered by the `--audit` gap check.
- No other contributors have in-flight local branches based on `matias-kanban` that need explicit
  migration guidance as part of this phase; the rename is scoped to `origin` and the maintainer's
  local repo.
- The table-prefix rename, CI/CD pipeline, and release-cut phases (including the first actual tag
  cut and image publish) are separate, already-scoped phases that consume the versioning scheme
  defined here but are not implemented by it.
