---
description: "Task list for CI/CD pipeline adaptation"
---

# Tasks: Adapt CI/CD Pipeline

**Input**: Design documents from `/specs/023-ci-cd-pipeline/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

*(No setup tasks are required for this feature, as it purely consists of modifying existing GitHub Actions workflows.)*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

*(No foundational tasks are required for this feature. We assume `ichatr-main` already exists as per the feature dependencies.)*

---

## Phase 3: User Story 1 - Maintainer tests code changes (Priority: P1) 🎯 MVP

**Goal**: Ensure automated testing and linting pipelines trigger correctly on pushes and pull requests against `ichatr-main`.

**Independent Test**: Push a commit or open a PR to `ichatr-main` and verify that the `run_foss_spec` and `size-limit` workflows run and pass/fail correctly.

### Implementation for User Story 1

- [X] T001 [P] [US1] Modify branch triggers (`on.push.branches` and `on.pull_request`) to `ichatr-main` in .github/workflows/run_foss_spec.yml
- [X] T002 [P] [US1] Modify branch triggers to `ichatr-main` in .github/workflows/size-limit.yml

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Maintainer publishes a new release (Priority: P1)

**Goal**: Automate building and publishing a Docker image to Docker Hub whenever a new git tag is created.

**Independent Test**: Create and push a new git tag and verify that the `publish_ee_docker` workflow triggers and publishes the correctly tagged image to Docker Hub.

### Implementation for User Story 2

- [X] T003 [P] [US2] Adapt workflow triggers to `on.push.tags: ['*']`, set `DOCKER_REPO` to `edneymatias/ichatr`, and ensure the Docker push step tags the image with both the git tag and `latest` in .github/workflows/publish_ee_docker.yml

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Remove irrelevant workflows (Priority: P2)

**Goal**: Delete unused and irrelevant upstream GitHub Actions workflows to simplify maintenance.

**Independent Test**: Verify that the removed workflow files are no longer present in `.github/workflows`.

### Implementation for User Story 3

- [X] T004 [P] [US3] Delete .github/workflows/publish_foss_docker.yml
- [X] T005 [P] [US3] Delete .github/workflows/frontend-fe.yml
- [X] T006 [P] [US3] Delete .github/workflows/deploy_check.yml
- [X] T007 [P] [US3] Delete .github/workflows/nightly_installer.yml
- [X] T008 [P] [US3] Delete .github/workflows/auto-assign-pr.yml
- [X] T009 [P] [US3] Delete .github/workflows/stale.yml
- [X] T010 [P] [US3] Delete .github/workflows/lock.yml
- [X] T011 [P] [US3] Delete .github/workflows/ghsa-linear-sync.yml
- [X] T012 [P] [US3] Delete .github/workflows/logging_percentage_check.yml
- [X] T013 [P] [US3] Delete .github/workflows/publish_codespace_image.yml

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T014 Run quickstart.md validation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: N/A
- **Foundational (Phase 2)**: N/A
- **User Stories (Phase 3-5)**: Can proceed in parallel.
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies.
- **User Story 2 (P1)**: No dependencies.
- **User Story 3 (P2)**: No dependencies.

### Parallel Opportunities

- All tasks across all stories are marked `[P]` and involve disjoint files, so they can theoretically all be executed in parallel.

---

## Parallel Example: User Story 3

```bash
# Delete all unused workflow files together in parallel
rm .github/workflows/publish_foss_docker.yml .github/workflows/frontend-fe.yml .github/workflows/deploy_check.yml .github/workflows/nightly_installer.yml .github/workflows/auto-assign-pr.yml .github/workflows/stale.yml .github/workflows/lock.yml .github/workflows/ghsa-linear-sync.yml .github/workflows/logging_percentage_check.yml .github/workflows/publish_codespace_image.yml
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 3: User Story 1
2. **STOP and VALIDATE**: Test User Story 1 independently

### Incremental Delivery

1. Add User Story 1 → Test independently
2. Add User Story 2 → Test independently
3. Add User Story 3 → Test independently

## Phase 7: Convergence

- [X] T015 Restrict `on.pull_request` trigger to `ichatr-main` branch in `.github/workflows/run_foss_spec.yml` per FR-001 (partial)
- [X] T016 Delete `.github/workflows/run_mfa_spec.yml` per SC-003 (contradicts)
