# Feature Specification: Release Automation

**Feature Branch**: `024-release-automation`

**Created**: 2026-08-07

**Status**: Draft

**Input**: User description: "/speckit-specify @[docs/kanban/ciclo 6/13-release-cut/spec33.md]"

## Clarifications

### Session 2026-08-07
- Q: What happens when the release script is run on a dirty working tree? → A: Abort immediately with an error
- Q: How does the system handle a failure in the middle of the CI pipeline? → A: Fail the job and require manual intervention to fix/re-run
- Q: What happens if the highest existing tag is malformed? → A: Abort with an error asking the user to manually fix the tags
- Q: What should happen if git-cliff finds no conventional commits? → A: Proceed and create a GitHub Release with a default message

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Maintainer cuts a new release tag (Priority: P1)

As a maintainer, I want to run a single command that computes the next valid version tag and prompts for my confirmation, so that I can safely and confidently trigger a release without manual version math or git tag commands.

**Why this priority**: This is the manual entry point for the entire release automation workflow. Without this, the CI pipeline has no standardized trigger.

**Independent Test**: Can be fully tested by running the release script on a test branch and verifying it computes the correct tag, displays the correct commit range, and upon confirmation, pushes the tag to the repository.

**Acceptance Scenarios**:

1. **Given** no previous releases exist for the current base version, **When** the maintainer runs the release script, **Then** it computes the next tag as `1` and shows the range from the upstream base tag to HEAD.
2. **Given** a previous release exists for the current base version, **When** the maintainer runs the release script, **Then** it increments the release number and shows the range from the previous release tag to HEAD.

---

### User Story 2 - Automated Changelog and Release Notes (Priority: P1)

As a maintainer, I want the system to automatically generate a changelog and publish a GitHub Release whenever a valid fork version tag is pushed, so that I don't have to manually curate release notes or update documentation files.

**Why this priority**: Automating the artifact generation saves significant manual effort and ensures consistency in release documentation across the project's lifecycle.

**Independent Test**: Can be fully tested by pushing a test tag matching the fork version format and verifying that the CI pipeline successfully commits the changelog update and publishes the GitHub Release.

**Acceptance Scenarios**:

1. **Given** a valid fork release tag is pushed to the repository, **When** the CI pipeline triggers, **Then** it generates release notes grouped by commit type, commits them to the changelog file, and creates a public GitHub Release containing the notes and deployment instructions.
2. **Given** an upstream tag is pushed to the repository, **When** the CI pipeline evaluates triggers, **Then** it ignores the tag and does not generate fork-specific artifacts.

### Edge Cases

- What happens when the script is run on a dirty working tree? (Resolved: Abort immediately with an error)
- How does the system handle a failure in the middle of the CI pipeline (e.g., changelog committed, but GitHub Release creation fails)? (Resolved: Fail the job and require manual intervention to fix/re-run)
- What happens if the highest existing tag is malformed? (Resolved: Abort with an error asking the user to manually fix the tags)
- What should happen if `git-cliff` finds no conventional commits (e.g., empty changelog range) when the CI pipeline runs? (Resolved: Proceed and create a GitHub Release with a default message)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a CLI tool to compute the next sequential release tag based on the current upstream base version and existing fork tags.
- **FR-001b**: System MUST abort immediately with an error if the CLI tool is run on a dirty working tree.
- **FR-001c**: System MUST abort with an explicit error asking the user to manually fix the tags if the highest existing tag is malformed during computation.
- **FR-002**: System MUST interactively prompt the maintainer with the computed tag and changelog range for confirmation before performing any mutating actions.
- **FR-003**: System MUST compute the changelog range dynamically to isolate fork-specific changes, excluding upstream inheritance.
- **FR-004**: System MUST automatically generate release notes based on conventional commits within the computed range during the CI pipeline.
- **FR-004b**: System MUST gracefully handle an empty changelog range by proceeding and creating a GitHub Release with a default message (e.g., "No notable changes").
- **FR-005**: System MUST prepend the generated release notes to the project's changelog file and commit the changes directly to the main branch via an automated commit.
- **FR-006**: System MUST automatically create a GitHub Release containing the generated notes and deployment artifact references.
- **FR-006b**: System MUST fail the CI job upon any step failure and require manual intervention, without attempting automatic rollback of previously successful steps.
- **FR-007**: System MUST restrict automated release pipeline execution exclusively to tags matching the fork's versioning scheme.
- **FR-008**: System MUST update the project's governance documentation to reflect the new standardized release process.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Maintainer can initiate a complete release process in under 1 minute of active manual effort.
- **SC-002**: 100% of automatically generated release notes strictly contain fork-specific changes, properly isolating them from upstream changes.
- **SC-003**: The automated release pipeline successfully completes 100% of artifact generation (changelog commit, release notes publication) without requiring manual intervention after tag approval.
- **SC-004**: Non-fork tags (e.g. upstream tags) successfully bypass the release pipeline 100% of the time.

## Assumptions

- Maintainers have appropriate permissions to push tags directly to the repository.
- The CI environment has sufficient authentication and permissions to commit to the main branch and create GitHub Releases.
- The upstream base version is accurately maintained in the project's metadata file.
- Existing commit history within the changelog range adheres to Conventional Commits formatting to allow for automated grouping.
