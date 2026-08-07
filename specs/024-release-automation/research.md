# Phase 0: Research

## Script Language Decision
- **Decision**: Use Ruby for `bin/ichatr-release`.
- **Rationale**: The feature specification explicitly states to mirror the `bin/ichatr-migration` wrapper pattern. A quick inspection of `bin/ichatr-migration` confirms it is written in Ruby (`#!/usr/bin/env ruby`). Using Ruby keeps the scripting environment consistent and allows leveraging Ruby's robust standard library for interactive prompts and Git shell-outs if necessary.
- **Alternatives considered**: Bash. While adequate for basic Git operations, Bash handles interactive user prompts and complex string manipulation (like parsing `package.json` for base version and calculating the next tag) less elegantly than Ruby.

## GitHub Actions Workflow Integration
- **Decision**: Update `.github/workflows/publish_ee_docker.yml` to trigger only on `*-ichatr.*` tags and add a new job `release-notes` that runs alongside `build`.
- **Rationale**: The spec requires the changelog and release notes generation to happen in the existing publish workflow (FR-004, FR-005). The trigger `tags: ['*']` will be changed to `tags: ['*-ichatr.*']`. A new job (e.g., `release_notes`) will be added to run `git-cliff`, commit the `CHANGELOG.md` file using an automated bot identity, and execute `gh release create`.
- **Alternatives considered**: Creating a separate workflow file. This was explicitly rejected by the spec (FR-004: "not a separate workflow").

## git-cliff Integration
- **Decision**: Use a standard `git-cliff` configuration and run it via a GitHub Action step or CLI directly in the `release_notes` job.
- **Rationale**: `git-cliff` is a standard tool for conventional commits. It can be easily installed via standard GitHub Action tooling (e.g. `orhun/git-cliff-action` or downloading the binary) and executed against the computed range.
- **Alternatives considered**: Hand-rolling a conventional commit parser. Explicitly rejected by the spec.
