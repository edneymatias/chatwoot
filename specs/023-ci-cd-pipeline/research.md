# Research: Adapt CI/CD Pipeline

## Overview

This document captures the findings from the research phase (Phase 0) for the CI/CD pipeline adaptation feature. Because the requirements provided in the kanban specification are highly explicit and direct regarding which workflows to modify and delete, there are no structural or technical unknowns requiring further investigation.

## Decisions

- **Decision:** Use `.github/workflows/run_foss_spec.yml` and `size-limit.yml` for automated testing and linting, changing their branch triggers to `ichatr-main`.
- **Rationale:** These workflows contain the essential test/lint suites (RuboCop, ESLint, Jest, RSpec) needed for the fork and do not rely on upstream-specific infrastructure.
- **Alternatives considered:** Writing a new workflow from scratch (rejected as it would duplicate existing logic and make merging upstream changes harder).

- **Decision:** Adapt `.github/workflows/publish_ee_docker.yml` to be the sole Docker publishing workflow, triggered exclusively on git tags.
- **Rationale:** The fork does not strip the `enterprise/` directory, so starting from the `publish_ee_docker.yml` template makes the most sense. Tag-based triggering enforces the 1:1 mapping between git version tags and Docker Hub images.
- **Alternatives considered:** Retaining both FOSS and EE publish workflows (rejected because the fork only ships one image).

- **Decision:** Delete irrelevant upstream workflows completely rather than disabling them.
- **Rationale:** Reduces repository noise and aligns with the kanban specification's goal of stripping the workflow set down to what actually serves the single-maintainer fork.
- **Alternatives considered:** Disabling via `if: false` or renaming to `.yml.disabled` (rejected as it leaves dead files in the active tree).
