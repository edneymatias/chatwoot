# Implementation Plan: Release Automation

**Branch**: `024-release-automation` | **Date**: 2026-08-07 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/024-release-automation/spec.md`

## Summary

Automate the release process by providing a CLI script (`bin/ichatr-release`) to safely compute and push version tags, and extending the existing Docker publish workflow in GitHub Actions to automatically generate a changelog using `git-cliff` and publish a GitHub Release when a fork tag is pushed.

## Technical Context

**Language/Version**: Ruby (for CLI script), YAML (for GitHub Actions)

**Primary Dependencies**: `git`, `git-cliff`, GitHub Actions (`gh` CLI implicitly available)

**Storage**: N/A

**Testing**: Manual validation and CI execution

**Target Platform**: Local developer environments (Linux/macOS) and GitHub Actions runner (Ubuntu)

**Project Type**: Developer Tooling & CI Pipeline

**Performance Goals**: Script execution < 1 minute

**Constraints**: Must isolate fork-specific changelogs from upstream inheritance using Conventional Commits.

**Scale/Scope**: Single new script file and modification to one existing CI workflow file.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Smallest Production-Ready Change**: Yes, extending an existing workflow instead of building a complex separate pipeline.
- **Adhere to Established Conventions**: Yes, mirroring the `bin/ichatr-migration` wrapper pattern and using standard Ruby scripts.
- **Safe, Reversible Change Management**: The script prompts interactively before pushing tags, preventing destructive accidents. Mid-flight CI errors stop the workflow to require manual intervention rather than performing unsafe automatic rollbacks.
- **Dual-Tree Awareness**: N/A (Internal tooling).

## Project Structure

### Documentation (this feature)

```text
specs/024-release-automation/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── cli.md
└── tasks.md             # Phase 2 output (generated later)
```

### Source Code (repository root)

```text
bin/
└── ichatr-release

.github/
└── workflows/
    └── publish_ee_docker.yml

docs/
└── AGENTS.md
```

**Structure Decision**: The feature is minimal. The script lives in `bin/` alongside other wrappers, the workflow changes modify an existing file in `.github/workflows/`, and `AGENTS.md` is updated in place.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*(No violations)*
