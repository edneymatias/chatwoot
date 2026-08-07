# Phase 33: Release Cut (Version Tags, Changelog & Release Notes)

**Depends on**: Phase 31 (table-prefix rename) and Phase 32 (CI/CD pipeline)
merged and validated — this phase builds the actual release mechanics on
top of the tag-triggered Docker publish workflow Phase 32 established.

## Context

Phase 30 defined the versioning scheme (`<upstream-base-version>-ichatr.<N>`)
but explicitly deferred cutting any real tag. Phase 32 built the CI/CD
pipeline that publishes a Docker image whenever a tag is pushed, but didn't
touch changelog/release-notes generation. This phase closes both gaps: a
script that mechanically computes and pushes the next release tag, and a
CI job — extending Phase 32's existing tag-triggered workflow — that
generates a changelog and GitHub Release automatically whenever that
happens.

Upstream Chatwoot has no `CHANGELOG.md`, no `.github/release.yml`, and no
release-notes workflow to inherit from (confirmed by inspecting
`upstream/develop`), so this phase introduces its own tooling rather than
adapting an existing upstream mechanism — using
[`git-cliff`](https://git-cliff.org/), an off-the-shelf Conventional
Commits changelog generator, rather than hand-rolling one.

## Version-tag helper script

**FR-001**: A new `bin/ichatr-release` script (mirroring Phase 31's
`bin/ichatr-migration` wrapper pattern):
1. Reads the upstream base version from `package.json`'s `version` field
   (e.g. `4.16.2`).
2. Finds the highest existing `<base>-ichatr.N` tag for that base
   (`git tag --list "<base>-ichatr.*"`) and computes the next `N` (`1` if
   none exist for this base yet).
3. Prints the computed tag name and asks for interactive confirmation
   before doing anything destructive/visible — pushing a tag immediately
   triggers the CI publish pipeline (FR-004), so this is a deliberate
   gate, not a formality.
4. On confirmation, creates an annotated tag (`git tag -a <tag> -m
   "<tag>"`) on the current `ichatr-main` HEAD and pushes it
   (`git push origin <tag>`).

**FR-002**: The script also resolves and prints the changelog range it
computed (see FR-003) as part of its confirmation prompt, so the maintainer
can sanity-check the range before pushing.

## Changelog range logic

**FR-003**: The range passed to `git-cliff` is derived automatically from
the versioning scheme itself, not entered by hand:
- **First release for a given base** (`N=1`): range is
  `<upstream-base-tag>..HEAD` (e.g. `v4.16.2..HEAD`) — this naturally
  excludes every commit that arrived from upstream (already contained in
  the base tag) and includes only what the fork added on top of that sync.
- **Additional release on the same base** (`N>1`, e.g. a hotfix): range is
  `<previous-ichatr-tag>..HEAD` — only what's new since the last fork
  release, not the whole base-to-now history again.

This means the changelog only ever documents fork-specific work; changes
inherited from upstream are the concern of upstream's own release notes,
not this repo's.

## CI job: changelog & release notes

**FR-004**: The tag-triggered workflow Phase 32 adapted
(`publish_ee_docker.yml`) gets a new job in the same workflow file — not a
separate workflow — that runs alongside the existing Docker build/publish
job:
1. Run `git-cliff` with the range resolved by FR-003 (passed via the tag
   name / a computed base-ref, not re-derived in CI) to produce changelog
   text grouped by Conventional Commit type (`feat`/`fix`/etc.).
2. Prepend that block to `CHANGELOG.md` and commit it directly to
   `ichatr-main` (bot commit, using the same git-identity approach already
   used for other automated commits in this repo) — no PR, since the
   maintainer already made the deliberate decision when confirming the tag
   push in FR-001.
3. Create a GitHub Release for the tag via `gh release create`, using the
   same `git-cliff`-generated text as the body, with one line appended
   that `CHANGELOG.md` does not get: `Docker image:
   edneymatias/ichatr:<tag>` — deploy info belongs in the release
   announcement, not the in-repo changelog file.

**FR-005**: The workflow's trigger is narrowed from Phase 32's
`on.push.tags: ['*']` to `on.push.tags: ['*-ichatr.*']`, so only tags
matching the fork's own release format trigger the publish+changelog
pipeline — an upstream tag (e.g. `v4.17.0`) landing in the repo via
`git fetch upstream --tags` and accidentally being pushed to `origin` no
longer fires it.

## Documentation

**FR-006**: `AGENTS.md` gets a new **"Release Process"** section, written
in general/steady-state terms (no reference to phase numbers, since this
must remain accurate for every future release including syncs to new
upstream bases):
- Prerequisites: clean working tree on `ichatr-main`, test suites green
  (`bundle exec rspec`, `pnpm test`).
- Run `bin/ichatr-release`; confirm the computed tag and changelog range
  when prompted.
- What happens automatically after push: CI generates the changelog,
  commits `CHANGELOG.md`, creates the GitHub Release, and publishes the
  Docker image.
- Where the artifacts end up: `CHANGELOG.md` in the repo, a GitHub Release
  entry, and `edneymatias/ichatr:<tag>` (plus a floating `latest`) on
  Docker Hub.

## Out of scope

- Actually running `bin/ichatr-release` to cut the first real tag — a
  deliberate action taken after this phase is merged and validated, not
  part of the phase itself.
- Any deploy-to-environment step — Phase 32 already scoped this out;
  publishing to Docker Hub remains the full extent of the automation.
- Editing or curating `git-cliff`'s generated text by hand — the pipeline
  is fully automatic per the "automático" decision; manual editing of a
  published `CHANGELOG.md` entry, if ever needed, is a separate follow-up
  commit like any other doc fix.
- Changelog coverage for anything upstream — out of scope by design (see
  Context); consult upstream's own release notes for upstream changes.
