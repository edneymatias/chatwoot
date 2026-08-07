# CLI Contract: `bin/ichatr-release`

## Command
`bin/ichatr-release`

## Description
A script for maintainers to cut new releases based on the repository's versioning scheme (`<upstream-base-version>-ichatr.<N>`). It computes the next version tag, determines the changelog range, and interactively prompts the user for confirmation before tagging and pushing.

## Usage
Run the script from the root of the repository without any arguments:
```bash
bin/ichatr-release
```

## Behavior and Exit Codes
- **Success (0)**: Tag was correctly computed, user confirmed, and tag was created and pushed successfully.
- **Error (1)**: 
  - Working tree is dirty.
  - Highest existing tag is malformed.
  - User aborted at the confirmation prompt.
  - `git tag` or `git push` commands failed.

## Interactive Output Example
```text
Current base version: 4.16.2
Highest existing tag: 4.16.2-ichatr.1

Next tag: 4.16.2-ichatr.2
Changelog range: 4.16.2-ichatr.1..HEAD

Are you sure you want to cut this release? This will push the tag to origin immediately. [y/N]: y
Tag 4.16.2-ichatr.2 created and pushed. CI pipeline will now generate release notes.
```
