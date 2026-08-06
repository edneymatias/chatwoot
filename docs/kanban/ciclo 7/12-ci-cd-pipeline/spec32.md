# Phase 32: CI/CD Pipeline for the ichatr Fork

**Depends on**: Phase 30 (`ichatr-main` must exist as the branch name CI
triggers reference) and Phase 31 (table-prefix rename should land first so
CI runs against the final schema/table names, not `matias_*`)

## Context

Chatwoot's existing GitHub Actions workflows were built for a public,
multi-contributor open-source project with its own Cloud/Heroku deployment
target and community-management needs (stale-issue bots, PR auto-assignment,
Codespaces images, etc.). None of that applies to this fork: single
maintainer, no external contributors, no Chatwoot Cloud/Heroku deploy
target, own Docker Hub account. This phase strips the workflow set down to
what actually serves the fork — running tests/lint on every change, and
building+publishing a Docker image under the fork's own name when a version
is tagged — and deletes everything else outright (recoverable via git
history if ever needed again, so nothing is truly lost).

## Workflows to adapt

**FR-001**: `run_foss_spec.yml` is kept and adapted: its `on.push.branches`
and `on.pull_request` branch filters are updated from `develop`/`master` to
`ichatr-main`. The `lint-backend` (rubocop), `lint-frontend` (eslint),
`frontend-tests`, and `backend-tests` (with Postgres/Redis services) jobs
are otherwise unchanged — they don't reference upstream-specific
infrastructure.

**FR-002**: `publish_ee_docker.yml` is adapted into the fork's single Docker
publish workflow (rather than keeping both `publish_foss_docker.yml` and
`publish_ee_docker.yml` — the fork ships one image, not a CE/EE split), per
the following decisions confirmed during brainstorm:
- The `enterprise/` directory is kept in the built image (the fork never
  applied the CE-stripping step historically, so removing it now would be a
  behavior change, not a status quo preservation).
- `DOCKER_REPO` points to `edneymatias/ichatr` on Docker Hub.
- Trigger changes from `publish_ee_docker.yml`'s original push/schedule
  triggers to **git tag creation only** (`on.push.tags: ['*']`), since the
  versioning scheme (Phase 30, FR-007/FR-008) is exactly the set of strings
  that should map 1:1 to published images — every tag is a release, every
  release is a tag.
- The image tag pushed to Docker Hub is derived directly from the git tag
  (e.g. tag `4.16.2-ichatr.1` → Docker tag `edneymatias/ichatr:4.16.2-ichatr.1`),
  plus a floating `latest` tag updated on every publish.
- Docker Hub credentials are stored as repository secrets
  (`DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`) exactly as the existing
  workflow already expects — no change to the auth mechanism itself, only
  to which account/repo they point at.

**FR-003**: `size-limit.yml` is kept and adapted: its branch trigger updates
to `ichatr-main`. No other changes — it's a genuinely useful regression
check with no upstream-specific dependencies.

## Workflows kept unchanged

**FR-004**: `lint_pr.yml` (conventional-commit PR title check) and
`test_docker_build.yml` (build-only sanity check on PRs, no push) are kept
as-is. Neither references upstream-specific branches, infrastructure, or
Chatwoot Cloud concepts, and both continue to serve the fork's own PR
workflow.

## Workflows deleted

**FR-005**: The following workflows are deleted outright (not disabled/
moved) — recoverable via `git log -- .github/workflows/<name>.yml` or
`upstream/develop` if ever needed again, so deletion is the correct default
over letting dead files accumulate in the active tree:

- `publish_foss_docker.yml` — superseded by the adapted
  `publish_ee_docker.yml` (FR-002); the fork doesn't ship a separate
  CE-stripped image.
- `frontend-fe.yml` — duplicates the `frontend-tests`/`lint-frontend` jobs
  already covered by `run_foss_spec.yml`.
- `deploy_check.yml` — Heroku/Chatwoot Cloud PR-preview specific; no
  equivalent infrastructure exists for this fork.
- `nightly_installer.yml` — validates the public `install.sh` onboarding
  path for prospective Chatwoot self-hosters; not relevant to a private
  fork's release flow.
- `auto-assign-pr.yml` — rotates PR review assignment across Chatwoot's
  maintainer list; no reviewer pool to rotate through.
- `stale.yml` / `lock.yml` — issue/PR hygiene bots for a high-traffic
  public tracker; not applicable to a single-maintainer private fork.
- `ghsa-linear-sync.yml` — syncs GitHub Security Advisories into Chatwoot's
  internal Linear workspace; depends on credentials/infra this fork
  doesn't have.
- `logging_percentage_check.yml` — Chatwoot's internal structured-logging
  coverage gate, specific to their own conventions.
- `publish_codespace_image.yml` — prebuilds a GitHub Codespaces devcontainer
  image for external contributors; the fork develops via local Docker
  Compose (per `CLAUDE.md`), not Codespaces.

## Net result

After this phase: `run_foss_spec.yml` (tests/lint, triggers on
`ichatr-main` push/PR) + the adapted `publish_ee_docker.yml` (build/publish
to `edneymatias/ichatr`, triggers on version-tag creation) +
`size-limit.yml` (adapted trigger) + `lint_pr.yml` + `test_docker_build.yml`
unchanged = 5 active workflows, down from 14. This becomes the CI/CD gate
the release-cut phase (Phase 33 or later) relies on to publish the first
tagged image.

## Out of scope

- Actually cutting the first version tag / triggering the first publish —
  belongs to the release-cut phase, after this phase and Phase 31 are both
  merged and validated.
- Standing up a staging/homologação environment — the user's own separate
  effort, outside this repo's CI/CD.
- Pointing the production VPS at a published image — explicitly deferred
  by the user to be done manually, later.
- Any deploy-to-environment workflow (staging or production) — none
  exists today and none is being added; publishing the image to Docker Hub
  is the full extent of this phase's automation.
