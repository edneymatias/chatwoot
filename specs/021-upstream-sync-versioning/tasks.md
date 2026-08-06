# Tasks: Upstream Sync, Branch Rebranding & Versioning Scheme

**Input**: Design documents from `/specs/021-upstream-sync-versioning/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/sync-gate-cli.md, quickstart.md

**Tests**: Not applicable as authored code — this feature adds no new application code to unit-test.
Validation is performed via the existing `bin/sync-custom-module-hooks` gate and the existing
`bundle exec rspec` / `pnpm test` suites, run as gate steps within User Story 1.

**Organization**: Tasks are grouped by user story (spec.md) to enable independent validation of
each story's outcome. Note: User Story 2 (branch rename) is intentionally sequenced *after* User
Story 1's checkpoint completes — the spec requires the rename to happen only once the sync gate
has passed (see plan.md's Constitution Check, Principle IV). User Story 3 (versioning scheme) is
pure documentation and has no dependency on git state, so it can run in parallel with US1/US2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files/commands, no dependency on an incomplete task)
- **[Story]**: Maps task to US1, US2, or US3 from spec.md
- File paths are exact where a file is touched; git/CLI commands are given verbatim where a task
  is an operation rather than a file edit

## Path Conventions

No new source tree (see plan.md's Project Structure). Tasks operate on the existing repository:
git refs (`develop`, `matias-kanban`/`ichatr-main`, `origin`, `upstream`), the existing
`bin/sync-custom-module-hooks` script, manifest-tracked frontend files, and `CLAUDE.md`.

---

## Phase 1: Setup

**Purpose**: Confirm the environment is ready to run the sync before touching any branch state

- [ ] T001 Verify `origin` and `upstream` remotes are configured and `upstream` is reachable: `git remote -v` then `git fetch upstream --dry-run`
- [ ] T002 [P] Confirm the working tree is clean on `matias-kanban` before starting: `git status`
- [X] T003 [P] Confirm `bin/sync-custom-module-hooks` is present and executable (`ls -l bin/sync-custom-module-hooks`) per [contracts/sync-gate-cli.md](./contracts/sync-gate-cli.md) — the actual `--check` baseline run happens once in Phase 2 (T004), not here

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the pre-merge baseline so post-merge gate results (Phase 3) can be
compared against a known-good starting point

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Run `bin/sync-custom-module-hooks --check` on `matias-kanban` pre-merge and confirm exit `0` (baseline manifest integrity, per [data-model.md](./data-model.md)'s Sync manifest gate entity)
- [X] T005 [P] Run `docker compose exec rails bundle exec rspec` on `matias-kanban` pre-merge and confirm it is green (baseline correctness before the merge introduces any regression) — 8203 examples, 1 pre-existing unrelated failure (`spec/builders/agent_builder_spec.rb:47`, stock upstream code untouched by any fork commit, unrelated to sync-versioning scope; accepted as baseline per user decision)
- [X] T006 [P] Run `docker compose exec vite pnpm test` on `matias-kanban` pre-merge and confirm it is green (baseline correctness before the merge introduces any regression)
- [ ] T007 Confirm local `develop` has zero local-only commits relative to `upstream/develop`: `git log upstream/develop..develop` returns empty (per spec Assumptions) — `develop` is a reference mirror only, never the sync source

**Checkpoint**: Baseline confirmed green — the sync merge can now begin

---

## Phase 3: User Story 1 - Maintainer brings the fork current with the latest stable upstream release (Priority: P1) 🎯 MVP

**Goal**: Bring the fork's working branch to parity with the **latest tagged** upstream release
(never `upstream/develop` HEAD) with zero manifest customizations lost and zero untriaged
`--audit` gaps, validated by the full test suite.

**Correction (2026-08-06)**: an earlier attempt at this story merged `upstream/develop` HEAD
(commit `e0dffe3f4`) directly into `matias-kanban`. That merge, and the speckit-tracking commits
built on top of it, were reverted (`git reset --hard` back to `c4f25799b`) after review found the
merged range included unreleased/mid-rollout upstream work (e.g. a commit explicitly titled part
1 of a 5-part feature rollout) and had broken the `vite` dev container (a merged-in commit added
the `brakeman` gem to `Gemfile` without the container's gemset being rebuilt). Tasks T008-T016
below are rewritten to target the latest release tag instead of `develop` HEAD.

**Independent Test**: Confirm the fork's branch is merged with (or already at parity with) the
latest upstream release tag, `--check` reports every manifest entry present, `--audit` reports
zero untriaged gaps, and both test suites pass (spec.md User Story 1 Independent Test).

### Implementation for User Story 1

- [X] T008 [US1] Identify the sync target — the latest tag on `chatwoot/chatwoot`, never `upstream/develop` HEAD: `git fetch upstream --tags && git tag --sort=-creatordate --list 'v*' | head -1` (found: `v4.16.2`)
- [X] T009 [US1] Check whether `matias-kanban` is already at parity with the target tag: `git merge-base HEAD v4.16.2` vs. `git rev-list -1 v4.16.2` — confirmed the merge-base is only one trivial "Bump version to 4.16.2" commit short of the tag's release-merge commit, i.e. already at parity. **No merge performed** — this task is a no-op for the current sync; re-run against the new tag next time upstream cuts a release.
- [ ] T010 [US1] (Next sync only, once a new upstream tag exists) Merge the target tag into `ichatr-main` with a single merge commit: `git merge --no-ff <tag>`
- [ ] T011 [US1] (Next sync only) Resolve conflicts in manifest-tracked files (`app/javascript/dashboard/routes/dashboard/dashboard.routes.js`, `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`, `app/javascript/dashboard/helper/actionCable.js`, `app/javascript/dashboard/store/index.js`, `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js`, `app/javascript/dashboard/helper/automationHelper.js`) case-by-case, re-reading upstream's new logic and re-applying the fork's customization on top of it (no fixed default side — per Clarifications session and Constitution Principle I)
- [ ] T012 [US1] (Next sync only) Resolve conflicts in any other files touched by the merge outside the manifest-tracked set, applying the same case-by-case stance
- [ ] T013 [US1] (Next sync only) Confirm the app builds after conflict resolution (Rails boots, `pnpm build` or dev server compiles cleanly, `vite` container boots)
- [X] T014 [US1] Run `bin/sync-custom-module-hooks --check` on the current (already-at-parity) tree and confirm exit `0` — all 40 wiring points present
- [ ] T015 [US1] (Next sync only) Run `bin/sync-custom-module-hooks --audit` against the merge-base and triage every `gap` per [contracts/sync-gate-cli.md](./contracts/sync-gate-cli.md): add a `MANIFEST` entry, add the path to the script's `excluded`/`out_of_scope` list, or log a follow-up and fail the sync loudly (FR-006a)
- [ ] T016 [US1] (Next sync only) Re-run `bin/sync-custom-module-hooks --audit` and confirm zero entries remain in the raw `gap` state
- [ ] T017 [US1] Run `docker compose exec rails bundle exec rspec` on the current tree and confirm green — T005's baseline run was already performed on this exact commit (`c4f25799b`) before the bad merge attempt; only the manifest script (`bin/sync-custom-module-hooks`, not exercised by rspec) changed since, so re-running is a formality, not expected to surface anything new
- [ ] T018 [US1] Run `docker compose exec vite pnpm test` on the current tree and confirm green — same rationale as T017, relative to T006's baseline run

**Checkpoint**: `matias-kanban` is confirmed at parity with the latest upstream release tag
(`v4.16.2`), the manifest gate is clean, and the `vite` container boots. This is the point at
which User Story 2 (rename) may begin. Tasks marked "(Next sync only)" become active the next
time a new upstream tag is cut.

---

## Phase 4: User Story 2 - Fork gets a permanent branch identity instead of a feature-branch name (Priority: P1)

**Goal**: Rename `matias-kanban` to the fork's permanent branch `ichatr-main` on `origin`, with
the old ref removed, so all future work has one unambiguous branch to target.

**Independent Test**: Confirm `ichatr-main` exists locally and on `origin`,
`origin/matias-kanban` no longer exists, and a new feature branch cut from `ichatr-main` can be
opened and merged back via PR (spec.md User Story 2 Independent Test).

**Depends on**: Phase 3 checkpoint (do not rename before the sync gate has passed — Constitution
Principle IV, research.md's "Sync order" decision).

### Implementation for User Story 2

- [ ] T019 [US2] Rename the branch locally: `git branch -m matias-kanban ichatr-main`
- [ ] T020 [US2] **Confirm with the user before pushing** (this creates the new shared ref on `origin`, visible to other contributors), then push the renamed branch: `git push origin ichatr-main`
- [ ] T021 [US2] **Confirm with the user before deleting** — this is a hard-to-reverse operation on a shared ref (Constitution Principle IV) — then delete the old ref on `origin`: `git push origin --delete matias-kanban`
- [ ] T022 [US2] Verify the rename: `git ls-remote --heads origin ichatr-main` returns one line, `git ls-remote --heads origin matias-kanban` returns empty
- [ ] T023 [US2] Open a throwaway branch from `ichatr-main`, confirm it opens and merges back via PR (validates SC-004), then delete the throwaway branch

**Checkpoint**: `ichatr-main` is the fork's sole permanent branch; `origin/matias-kanban` is gone.

---

## Phase 5: User Story 3 - Release engineer has an unambiguous version-tag scheme for future releases (Priority: P2)

**Goal**: Document the `<upstream-base-version>-ichatr.<N>` versioning scheme so later
release-engineering phases don't need to re-litigate it. No tag is cut in this phase (FR-007).

**Independent Test**: Confirm the documented scheme unambiguously produces the next tag for both
a fresh-upstream-base release and a same-base hotfix release, without needing further discussion
(spec.md User Story 3 Independent Test).

**Depends on**: Nothing — pure documentation, can run in parallel with Phase 3/4.

### Implementation for User Story 3

- [X] T024 [P] [US3] Add a "Branch model" section to `CLAUDE.md` documenting `ichatr-main` as the fork's single permanent branch, `develop` as a fast-forward-only mirror, and that there is no separate `release/*` branch scheme (per research.md's "doc placement" decision)
- [X] T025 [P] [US3] Add a "Fork versioning scheme" section to `CLAUDE.md` documenting the `<upstream-base-version>-ichatr.<N>` tag format, that the base version is sourced from `package.json`'s `version` field, and that `N` is scoped per upstream base and resets to `1` on a new base
- [X] T026 [US3] Validate the documented rule against the three spec acceptance scenarios: base `4.16.2` first release → `4.16.2-ichatr.1`; same-base hotfix → `4.16.2-ichatr.2`; new base `4.17.0` first release → `4.17.0-ichatr.1` (not continuing `N` from the old base)

**Checkpoint**: Versioning scheme is documented in `CLAUDE.md` and unambiguous per the validation
above; no tag has been cut.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and closing out the source phase doc

- [ ] T027 Run through [quickstart.md](./quickstart.md) end-to-end on the final state to confirm all three user stories validate cleanly
- [ ] T028 [P] Cross-reference `docs/kanban/ciclo 7/10-upstream-sync-and-versioning/spec30.md` to `specs/021-upstream-sync-versioning/` (e.g. a short "Implemented as" note) so the kanban doc and the spec-kit artifact stay linked
- [ ] T029 Open a PR summarizing the sync (commit range pulled in), the branch rename, and the `CLAUDE.md` versioning-scheme doc update, per the repo's PR description format

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — establishes the pre-merge baseline; BLOCKS User Story 1
- **User Story 1 (Phase 3)**: Depends on Foundational — this is the sync itself
- **User Story 2 (Phase 4)**: Depends on User Story 1's checkpoint (rename only after the gate passes)
- **User Story 3 (Phase 5)**: Depends only on Foundational being reachable (no git-state dependency); may run in parallel with Phase 3/4
- **Polish (Phase 6)**: Depends on Phases 3, 4, and 5 all being complete

### User Story Dependencies

- **User Story 1 (P1)**: No dependency on other stories — the sync itself
- **User Story 2 (P1)**: Depends on User Story 1's checkpoint (sequential, not parallel, by design — see research.md)
- **User Story 3 (P2)**: Independent of User Story 1/2; pure documentation

### Parallel Opportunities

- T002 and T003 (Setup) can run in parallel
- T005 and T006 (Foundational baseline test runs) can run in parallel with each other (and with T004)
- T024 and T025 (US3 doc sections) can run in parallel with each other, and the whole of Phase 5 can run in parallel with Phase 3/4
- T028 (kanban doc cross-reference) can run in parallel with T027 (quickstart validation)

---

## Parallel Example: Foundational Baseline

```bash
# Launch both baseline test-suite runs together (Phase 2):
Task: "Run docker compose exec rails bundle exec rspec on matias-kanban pre-merge"
Task: "Run docker compose exec vite pnpm test on matias-kanban pre-merge"
```

## Parallel Example: User Story 3 alongside User Story 1/2

```bash
# While the sync (Phase 3) or rename (Phase 4) is in progress, documentation can proceed:
Task: "Add Branch model section to CLAUDE.md"
Task: "Add Fork versioning scheme section to CLAUDE.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (baseline confirmed green)
3. Complete Phase 3: User Story 1 (the sync itself)
4. **STOP and VALIDATE**: `--check`/`--audit` clean, both test suites green
5. This alone unblocks every later release-engineering phase, even before the rename lands

### Incremental Delivery

1. Setup + Foundational → baseline confirmed
2. User Story 1 → sync complete, validated independently (MVP)
3. User Story 2 → branch renamed, validated independently
4. User Story 3 → versioning scheme documented, validated independently (can slot in anytime after Foundational)
5. Polish → quickstart re-run, kanban doc cross-referenced, PR opened

---

## Notes

- No `[Story]` label on Setup/Foundational/Polish tasks per the format rules
- This feature has no code entities/services/endpoints, so there are no Models/Services/Endpoints
  subsections within each story — tasks are git operations, gate runs, and doc edits
- Commit after each logical group (e.g., after the merge lands and gate passes; after the rename;
  after the `CLAUDE.md` doc update) rather than after every single command
- Verify the Phase 3 checkpoint (gate green) before starting Phase 4 (rename) — this ordering is
  load-bearing per Constitution Principle IV, not arbitrary
