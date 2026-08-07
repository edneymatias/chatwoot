# Quickstart: Validation Guide for Release Automation

This guide outlines how to validate the release automation tooling end-to-end.

## Prerequisites
- Clean working directory on the `ichatr-main` branch or a test branch simulating it.
- A local `package.json` with a valid `version` field (e.g., `4.16.2`).
- Appropriate permissions to push tags to the origin repository.

## Scenario 1: Initial Release for a Base Version
1. Ensure no tags matching `<current-base>-ichatr.*` exist locally or on origin.
2. Run the script: `bin/ichatr-release`
3. Verify the output states the next tag is `<current-base>-ichatr.1`.
4. Verify the changelog range is `v<current-base>..HEAD`.
5. Enter `N` or abort. The tag should not be created.

## Scenario 2: Subsequent Release
1. Create a dummy tag to simulate a previous release: `git tag -a 4.16.2-ichatr.1 -m "test"`
2. Run the script: `bin/ichatr-release`
3. Verify the output states the next tag is `4.16.2-ichatr.2`.
4. Verify the changelog range is `4.16.2-ichatr.1..HEAD`.
5. Enter `y` to confirm.
6. Verify the tag was created locally (`git tag -l`) and pushed to origin.

## Scenario 3: CI Pipeline Trigger
1. Ensure you have pushed a valid fork tag (e.g., from Scenario 2) to a repository with GitHub Actions enabled for this branch.
2. Navigate to the GitHub Actions tab in the repository.
3. Verify the `Publish Chatwoot EE docker images` workflow is triggered.
4. Wait for the `release_notes` job to complete.
5. Check the `ichatr-main` branch commit history to verify a new commit was added updating `CHANGELOG.md`.
6. Navigate to the GitHub Releases page and verify a new release exists for the tag, containing the generated release notes.

## Edge Case Validations
- **Dirty Tree**: Modify a tracked file without committing, then run `bin/ichatr-release`. It should abort immediately with an error.
- **Empty Changelog**: Push a tag where `git-cliff` finds no conventional commits. Verify the CI pipeline still successfully creates a GitHub Release with a default message (e.g., "No notable changes").
