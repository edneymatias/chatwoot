# Implementation Plan: Upstream Sync, Branch Rebranding & Versioning Scheme

**Branch**: `021-upstream-sync-versioning` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/021-upstream-sync-versioning/spec.md`

## Summary

Keep the fork's working branch (`matias-kanban`, soon `ichatr-main`) current with the **latest
tagged** upstream Chatwoot release (never `upstream/develop` HEAD), gated by the existing
`bin/sync-custom-module-hooks` manifest (`--check`/`--audit`) and the full test suite; then rename
the branch to its permanent identity (`ichatr-main`), keep `develop` a plain fast-forward mirror of
`upstream/develop` used only as a reference (never merged), and document (no tag cut) the
`<upstream-base-version>-ichatr.<N>` version scheme for later release phases. This is a
git/branch-operations and process-documentation feature — no new application code, models, or
endpoints. The technical approach is a sequenced set of git operations plus doc updates, validated
by tooling that already exists.

**Correction (2026-08-06)**: an earlier execution of this plan merged `upstream/develop` HEAD
directly, pulling in unreleased/mid-rollout upstream work; it was reverted. The sync target is now
always the latest upstream release tag (currently `v4.16.2`), which the fork's branch was already
at parity with before the bad merge — so this pass of the feature performs no merge, only the
branch rename and the corrected documentation.

## Technical Context

**Language/Version**: Ruby (sync script, already implemented), git CLI — no new language/runtime
introduced

**Primary Dependencies**: `bin/sync-custom-module-hooks` (existing, `--check`/`--audit`/apply
modes), git remotes `origin` (`edneymatias/chatwoot`) and `upstream` (`chatwoot/chatwoot`, already
configured)

**Storage**: N/A — no data/schema changes

**Testing**: `bundle exec rspec` (backend), `pnpm test` (frontend) — existing suites, run as the
sync's final gate; no new tests are written by this feature itself, since it produces no new
application behavior to unit-test

**Target Platform**: Fork's git repository / branch topology (`origin`, local checkout) — not a
runtime deployment target

**Project Type**: Repository/branch operations + documentation (not a web/mobile/library feature)

**Performance Goals**: N/A

**Constraints**: Must not cut a version tag or Docker image (explicitly out of scope, FR-007);
must not touch table-prefix rename or CI/CD (separate, already-scoped phases); `develop` must
remain a pure fast-forward mirror with zero local commits and is never merged into `ichatr-main`;
the sync source must always be the latest upstream release tag, never `upstream/develop` HEAD
(FR-004)

**Scale/Scope**: One merge of the latest upstream release tag into one permanent branch (a no-op
merge as of this correction, since the fork is already at parity with `v4.16.2`); versioning
scheme is a documentation decision with no immediate tag cut

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)** — PASS. This feature *is* the upstream
  sync; FR-005/edge cases explicitly require re-evaluating each fork customization against
  upstream's change case-by-case (per the Clarifications session) rather than reflexively keeping
  the fork's prior implementation, which is exactly this principle's mandate. No file
  renaming/restructuring beyond what upstream itself did is introduced.
- **II. Smallest Production-Ready Change** — PASS. Scope is deliberately bounded (FR-007, "Out of
  scope" section): no speculative tag cutting, no table-prefix work, no CI/CD changes bundled in.
  Audit gaps needing real rework are logged as follow-up items rather than expanded into ad hoc
  in-phase work (FR-006a), directly following this principle.
- **III. Adhere to Established Conventions** — PASS. No new code is introduced by this feature
  beyond conflict-resolution edits to existing files during the merge, which must already conform
  to existing RuboCop/ESLint conventions (enforced by the existing lint/test gate in FR-006).
- **IV. Safe, Reversible Change Management** — PASS with explicit gates. The branch rename
  (FR-001) deletes `origin/matias-kanban` — a hard-to-reverse ref deletion — so it requires
  explicit confirmation per this principle; the plan sequences it only after the merge is fully
  validated (User Story 2 depends on User Story 1 completing), minimizing the chance of needing to
  reverse it. No `--force`, `reset --hard`, or `--no-verify` is used at any step.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS. The manifest/audit gate (FR-006) already
  scans `app/` and treats `enterprise/app/models/` specially (schema-annotation exclusion logic in
  the existing script); no new endpoints or public API surface are introduced by this feature, so
  no new OSS/Enterprise parity decision is needed beyond what the existing audit already covers.

No violations requiring Complexity Tracking justification.

## Project Structure

### Documentation (this feature)

```text
specs/021-upstream-sync-versioning/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md         # Phase 1 output (/speckit-plan command)
├── contracts/            # Phase 1 output (/speckit-plan command) — sync-gate contract
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

This feature does not add a new application module. It operates on existing repository structure:

```text
bin/sync-custom-module-hooks   # existing script — MANIFEST array is the source of truth for
                                # tracked wiring points; --check/--audit are the validation gate
                                # used unmodified by this feature (no code changes to the script
                                # itself are required by this spec)

# Files most likely to carry merge conflicts (already tracked in MANIFEST, per spec FR-005 /
# User Story 1 acceptance scenario 2):
app/javascript/dashboard/routes/dashboard/dashboard.routes.js
app/javascript/dashboard/components-next/sidebar/Sidebar.vue
app/javascript/dashboard/helper/actionCable.js
app/javascript/dashboard/store/index.js
app/javascript/dashboard/routes/dashboard/settings/settings.routes.js
app/javascript/dashboard/helper/automationHelper.js

# Documentation updated by this feature (branch model, versioning scheme — no code):
docs/kanban/ciclo 7/10-upstream-sync-and-versioning/spec30.md   # source spec (reference only)
CLAUDE.md or a versioning doc under docs/ (see research.md for placement decision)
```

**Structure Decision**: No new source tree. This feature's "implementation" is (a) a sequence of
git operations against the existing repository and its `origin`/`upstream` remotes, gated by the
existing `bin/sync-custom-module-hooks` script, and (b) a documentation update recording the
branch model and version-tag scheme so later phases don't re-litigate it. `tasks.md` (Phase 2)
will therefore be an ordered runbook of git/validation steps plus a small doc-update task, not a
conventional model/service/test breakdown.

## Complexity Tracking

*No Constitution Check violations — section not needed.*
