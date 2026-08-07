# Implementation Plan: Adapt CI/CD Pipeline

**Branch**: `[023-ci-cd-pipeline]` | **Date**: 2026-08-07 | **Spec**: [spec.md](file:///home/matias/dev/chatwoot/specs/023-ci-cd-pipeline/spec.md)

**Input**: Feature specification from `/specs/023-ci-cd-pipeline/spec.md`

## Summary

This phase adapts the existing GitHub Actions CI/CD workflows for the single-maintainer `ichatr` fork by retaining and adjusting test/lint actions to run on `ichatr-main`, converting the enterprise Docker workflow to build and push to a custom Docker Hub registry on git tag creation, and deleting unnecessary upstream workflows (e.g., Codespaces, Heroku, auto-assign, etc.).

## Technical Context

**Language/Version**: YAML (GitHub Actions)

**Primary Dependencies**: GitHub Actions, Docker, Docker Hub

**Storage**: N/A

**Testing**: GitHub Actions workflow execution on pushes and pull requests

**Target Platform**: GitHub Actions CI/CD environments

**Project Type**: CI/CD Pipeline

**Performance Goals**: N/A

**Constraints**: Workflows must not reference Chatwoot Cloud or Heroku targets. The published Docker image must include the `enterprise/` directory.

**Scale/Scope**: 5 active workflows remaining, down from 14.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS - Although modifying and deleting upstream files, these changes are isolated to `.github/workflows/` and explicitly instructed by the kanban specification. They do not affect the main application code or database schema. 
- **II. Smallest Production-Ready Change**: PASS - The changes are scoped specifically to removing noise and adapting essential CI/CD checks for the personal fork.
- **III. Adhere to Established Conventions**: PASS - Re-using the existing test and lint workflows ensures all code style conventions are preserved.
- **IV. Safe, Reversible Change Management**: PASS - Deletions are in git history and can be restored if needed from upstream.
- **V. Dual-Tree Awareness**: PASS - `publish_ee_docker.yml` specifically includes the `enterprise/` directory, adhering to the requirement of preserving enterprise logic.

## Project Structure

### Documentation (this feature)

```text
specs/023-ci-cd-pipeline/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
# GitHub Actions Pipeline
.github/
└── workflows/
    ├── lint_pr.yml                 (kept as-is)
    ├── publish_ee_docker.yml       (adapt to publish to edneymatias/ichatr)
    ├── run_foss_spec.yml           (adapt triggers to ichatr-main)
    ├── size-limit.yml              (adapt triggers to ichatr-main)
    └── test_docker_build.yml       (kept as-is)
```

**Structure Decision**: The `.github/workflows/` directory will be pruned of unnecessary upstream workflows, leaving exactly 5 workflows that are adapted for the `ichatr` fork's requirements.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Deleting upstream workflow files | Irrelevant to the personal fork; specifically instructed by the project specification to eliminate noise. | Disabling them (rejected because they accumulate as dead files and add noise to the active tree). |
