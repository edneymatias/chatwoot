# Feature Specification: Adapt CI/CD Pipeline

**Feature Branch**: `[023-ci-cd-pipeline]`

**Created**: 2026-08-07

**Status**: Draft

**Input**: User description: "/speckit-specify @[docs/kanban/ciclo 6/12-ci-cd-pipeline/spec32.md]"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Maintainer tests code changes (Priority: P1)

As a maintainer, I want CI to automatically run tests and linters when I push or open a PR against the `ichatr-main` branch, so that I can catch regressions and ensure code quality without manual effort.

**Why this priority**: Fast and reliable feedback on code quality is the foundation of any CI pipeline.

**Independent Test**: Push a commit or open a PR to `ichatr-main` and verify that the `run_foss_spec` and `size-limit` workflows run and pass/fail correctly.

**Acceptance Scenarios**:

1. **Given** a new commit on `ichatr-main`, **When** the commit is pushed, **Then** `run_foss_spec` and `size-limit` run automatically.
2. **Given** a pull request targeting `ichatr-main`, **When** it is opened or updated, **Then** `run_foss_spec`, `size-limit`, `lint_pr`, and `test_docker_build` run automatically.

---

### User Story 2 - Maintainer publishes a new release (Priority: P1)

As a maintainer, I want to automatically build and publish a Docker image to Docker Hub whenever I create a new git tag, so that I have a reliable release artifact mapped 1:1 with version tags.

**Why this priority**: Automating the release process reduces human error and establishes a consistent deployment artifact strategy.

**Independent Test**: Create and push a new git tag and verify that the `publish_ee_docker` workflow triggers and publishes the correctly tagged image to Docker Hub.

**Acceptance Scenarios**:

1. **Given** a new git tag, **When** it is pushed to the repository, **Then** the workflow builds the image and pushes it to `edneymatias/ichatr` with the exact version tag and `latest`.

---

### User Story 3 - Remove irrelevant workflows (Priority: P2)

As a maintainer, I want irrelevant upstream workflows to be deleted so that the repository's CI configuration is clean and easier to maintain.

**Why this priority**: Removing noise helps focus on the workflows that actually matter for the personal fork.

**Independent Test**: Navigate to `.github/workflows` and verify that the removed workflow files are no longer present.

**Acceptance Scenarios**:

1. **Given** the adapted CI pipeline, **When** I inspect the `.github/workflows` directory, **Then** only the 5 expected active workflows are present.

### Edge Cases

- What happens when a PR is merged into a branch other than `ichatr-main`?
- How does the system handle a docker build failure during the publish step?
- What happens if the Docker Hub credentials (secrets) are missing or invalid?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST run `run_foss_spec.yml` on pushes and PRs targeting the `ichatr-main` branch.
- **FR-002**: System MUST run `size-limit.yml` on pushes to the `ichatr-main` branch.
- **FR-003**: System MUST trigger the Docker publish workflow only on git tag creation (`on.push.tags: ['*']`).
- **FR-004**: System MUST publish the Docker image to the `edneymatias/ichatr` repository on Docker Hub.
- **FR-005**: System MUST include the `enterprise/` directory in the published Docker image.
- **FR-006**: System MUST tag the published Docker image with the git tag name and a floating `latest` tag.
- **FR-007**: System MUST retain `lint_pr.yml` and `test_docker_build.yml` unchanged.
- **FR-008**: System MUST NOT include irrelevant upstream workflows (e.g., `publish_foss_docker.yml`, `deploy_check.yml`, etc.).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of pushes and PRs to `ichatr-main` trigger the expected linting and testing jobs.
- **SC-002**: 100% of new git tags trigger a successful Docker image build and push to Docker Hub.
- **SC-003**: The `.github/workflows` directory contains exactly 5 active workflow files.

## Assumptions

- Requires existing Docker Hub secrets (`DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`) to be configured in the repository.
- The `ichatr-main` branch exists and is the primary branch.
- The table-prefix rename feature has landed prior to these CI runs.
- Deploying the image to a staging/production environment is out of scope.
