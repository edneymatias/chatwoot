# Data Model: Release Automation

This feature introduces no new database tables, fields, or persistent domain models. It is exclusively a developer tooling and continuous integration (CI) automation feature.

## State Transitions
While there are no database entities, the repository's Git state transitions are as follows:

1. **Tag Computation**: `bin/ichatr-release` reads `package.json` and local Git tags.
2. **Tag Creation**: An annotated tag is created locally (`git tag -a ...`).
3. **Tag Push**: The tag is pushed to `origin`.
4. **CI Trigger**: GitHub Actions triggers on the pushed tag.
5. **Changelog Commit**: A commit is made to `ichatr-main` updating `CHANGELOG.md`.
6. **Release Publication**: A GitHub Release is drafted and published via `gh release create`.
