# Tasks: Release Automation

**Input**: Design documents from `/specs/024-release-automation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create `bin/ichatr-release` file and ensure it is executable

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

*(No blocking foundational infrastructure is required for this feature, as it primarily introduces a standalone script and extends an existing GitHub workflow. User stories can proceed immediately.)*

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Maintainer cuts a new release tag (Priority: P1) 🎯 MVP

**Goal**: Provide a CLI script that safely computes the next version tag, determines the changelog range, and pushes the tag upon interactive confirmation.

**Independent Test**: Run `bin/ichatr-release` on a clean and dirty working tree, verifying that it computes the correct next tag, calculates the correct changelog range, correctly aborts on dirty trees or user cancellation, and successfully tags and pushes on confirmation.

### Implementation for User Story 1

- [x] T002 [US1] Implement dirty tree check (abort if dirty) in `bin/ichatr-release`
- [x] T003 [US1] Implement upstream base version parsing from `package.json` in `bin/ichatr-release`
- [x] T004 [US1] Implement logic to fetch existing `<base>-ichatr.*` tags and compute the next tag (abort if malformed) in `bin/ichatr-release`
- [x] T005 [US1] Implement changelog range logic (`<base>..HEAD` for first release, `<prev>..HEAD` for subsequent) in `bin/ichatr-release`
- [x] T006 [US1] Implement interactive confirmation prompt displaying the tag and range in `bin/ichatr-release`
- [x] T007 [US1] Execute actual `git tag -a` and `git push origin` commands upon confirmation in `bin/ichatr-release`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Automated Changelog and Release Notes (Priority: P1)

**Goal**: Extend the CI pipeline to automatically generate a changelog using `git-cliff` and publish a GitHub Release when a fork release tag is pushed.

**Independent Test**: Push a test tag matching `*-ichatr.*` and verify that the `release_notes` job runs in the CI workflow, commits `CHANGELOG.md` to `ichatr-main`, and creates a GitHub Release. Also verify that upstream tags are ignored.

### Implementation for User Story 2

- [x] T008 [US2] Update `on.push.tags` trigger in `.github/workflows/publish_ee_docker.yml` to strictly match `*-ichatr.*`
- [x] T009 [US2] Add a new `release_notes` job to `.github/workflows/publish_ee_docker.yml` that runs alongside the Docker build
- [x] T009b [US2] Add step to dynamically compute changelog range (first release vs subsequent) in `.github/workflows/publish_ee_docker.yml`
- [x] T010 [US2] Add step to run `git-cliff` for the computed range in `.github/workflows/publish_ee_docker.yml`
- [x] T010b [US2] Add logic to parse `git-cliff` output and provide a default fallback message if empty in `.github/workflows/publish_ee_docker.yml`
- [x] T011 [US2] Add step to prepend `git-cliff` output to `CHANGELOG.md` and commit to `ichatr-main` in `.github/workflows/publish_ee_docker.yml`
- [x] T012 [US2] Add step to execute `gh release create` using the `git-cliff` output and Docker image reference in `.github/workflows/publish_ee_docker.yml`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

- [x] T013 [P] Document the new automated release process in `docs/AGENTS.md` under the "Release Process" section
- [x] T014 Run validation scenarios using `specs/024-release-automation/quickstart.md`, including verifying that a mid-flight CI failure halts safely without automatic rollback

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: N/A
- **User Stories (Phase 3+)**: US1 and US2 can be implemented in parallel. US1 modifies a local script, US2 modifies a CI workflow.
- **Polish (Final Phase)**: Depends on all user stories being complete.

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies.
- **User Story 2 (P1)**: Depends on US1 only for End-to-End testing, but implementation can happen concurrently.

### Parallel Opportunities

- US1 and US2 can be developed concurrently by different team members or agents.
- T013 (Documentation) can be drafted in parallel with development tasks.

---

## Parallel Example: Concurrent Development

```bash
# Launch implementation of the CLI script
Task: "Implement dirty tree check..." (T002)

# Simultaneously launch CI workflow updates
Task: "Update on.push.tags trigger..." (T008)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 3: User Story 1
3. **STOP and VALIDATE**: Ensure the script correctly calculates and tags versions locally.

### Incremental Delivery

1. Complete User Story 1 → Script can tag and push versions (MVP)
2. Complete User Story 2 → CI automatically supplements the pushed tags with changelogs and releases.
