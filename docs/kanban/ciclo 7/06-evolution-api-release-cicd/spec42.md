# Phase 42: Evolution API Release CI/CD — Publish `-ichatr.N` Tags to Own Docker Hub

**Depends on**: Phase 40 (Evolution API referral patch) — this phase provides the missing release
pipeline noted as out of scope there. Applies to `edneymatias/evolution-api` (external fork, not
part of this repo, at `/home/matias/dev/evolution-api`).

## Context

Phase 40 patched Evolution API but explicitly left "CI/CD pipeline to publish the patched image to
Docker Hub (`edneymatias/evolution-api`)" out of scope, tracking it as a separate backlog item.
This phase closes that gap, mirroring the versioning scheme and release flow already established
for the Chatwoot fork (`CLAUDE.md`, "Fork Versioning Scheme" / "Release Process" sections):
tags of the form `<upstream-base-version>-ichatr.<N>`, cut via a confirmation-gated script that
tags and pushes, with CI taking over from there.

For evolution-api, the upstream base is `package.json`'s `"version": "2.3.7"`, so the first release
tag is `2.3.7-ichatr.1`. No tags exist in the fork yet (`git tag --list` returns empty) and no
upstream tags have been pulled — consistent with the fork's existing practice of tracking upstream
tagged releases only, not `main`/`develop` tip.

**Docker Hub target confirmed**: `edneymatias/evolution-api` repository already exists on Docker
Hub; `DOCKER_USERNAME`/`DOCKER_PASSWORD` secrets are already configured in the
`edneymatias/evolution-api` GitHub repo, pointed at that account.

### Existing CI/CD inventory (evolution-api repo)

Three near-identical Docker publish workflows exist, all targeting upstream's own Docker Hub
namespace (`evoapicloud/evolution-api`), not the user's fork:

- `.github/workflows/publish_docker_image.yml` — triggers on tag push matching `"*.*.*"`, uses
  `docker/metadata-action` with `type=semver,pattern=v{{version}}`.
- `.github/workflows/publish_docker_image_latest.yml` — triggers on push to `main`, publishes
  `:latest`.
- `.github/workflows/publish_docker_image_homolog.yml` — triggers on push to `develop`, publishes
  `:homolog`.

All three share the same steps: `actions/checkout@v5` (with submodules), `docker/metadata-action@v5`,
`docker/setup-qemu-action@v3`, `docker/setup-buildx-action@v3`, `docker/login-action@v3` (reading
`secrets.DOCKER_USERNAME`/`secrets.DOCKER_PASSWORD`), `docker/build-push-action@v6`
(`linux/amd64,linux/arm64`).

Also present, unrelated to Docker publishing: `check_code_quality.yml` (lint + Prisma-generate +
build on push/PR to `main`/`develop`) and `security.yml` (CodeQL + dependency review). Neither is
modified by this phase.

Two Dockerfiles exist: `Dockerfile` (primary multi-stage build, what all three existing publish
workflows use) and `Dockerfile.metrics` (separate, much smaller build — purpose not investigated;
out of scope here, see below).

**Note on GitHub Actions default state**: GitHub disables Actions by default on forked repositories
until explicitly enabled. The existing three workflows may not currently be live in
`edneymatias/evolution-api` at all. This phase's changes are designed to be correct regardless of
that toggle's state, but do not depend on it.

**A collision worth designing around, not just a namespace mismatch**: `publish_docker_image.yml`'s
tag trigger pattern (`"*.*.*"`) already matches `-ichatr.` tags — a tag like `2.3.7-ichatr.1`
satisfies `"*.*.*"` under standard glob semantics (`*` absorbs any characters including the extra
dots and hyphen). If that workflow is (or becomes) enabled, pushing an `-ichatr.N` tag would fire
it too, but its `type=semver,pattern=v{{version}}` filter won't match a non-`v`-prefixed,
non-standard-semver tag — `docker/metadata-action` would emit no tags, producing a confusing,
functionally-empty build/push attempt. Addressed by FR-002 below.

## Changes

- **FR-001**: New workflow `.github/workflows/publish_docker_image_release.yml`, triggered only on
  tag pushes matching `"*-ichatr.*"` (matches `2.3.7-ichatr.1`, `2.3.7-ichatr.2`, etc.; does not
  match plain upstream-style tags like `v2.3.7`). Steps mirror the existing publish workflows
  exactly (checkout w/ submodules, QEMU, buildx, `docker/login-action` with the same
  `DOCKER_USERNAME`/`DOCKER_PASSWORD` secrets, `docker/build-push-action@v6`,
  `linux/amd64,linux/arm64`), with two differences:
  - `docker/metadata-action` targets `images: edneymatias/evolution-api` with
    `tags: |` containing two entries: `type=raw,value={{tag}}` (the exact pushed tag, e.g.
    `2.3.7-ichatr.1`) and `type=raw,value=latest` (floating tag) — mirrors Chatwoot's own
    versioned-tag-plus-floating-`latest` release pattern.
  - Builds from the existing primary `Dockerfile` only (not `Dockerfile.metrics` — out of scope,
    see below).
- **FR-002**: `publish_docker_image.yml`'s tag trigger is narrowed from `"*.*.*"` to `"v*.*.*"`,
  its only change — keeps it scoped to upstream-style `v`-prefixed semver tags and prevents it from
  ever matching `-ichatr.N` tags. Defensive, not load-bearing given Actions-disabled-by-default on
  forks, but cheap and correct regardless of that toggle's state.
  `publish_docker_image_latest.yml` and `publish_docker_image_homolog.yml` (branch-push triggers,
  not tag-based) are untouched — no collision risk.
- **FR-003**: New `bin/ichatr-release` script (bash — evolution-api is a Node/TS project with no
  Ruby toolchain, unlike the Chatwoot fork) that mirrors Chatwoot's `bin/ichatr-release` behavior
  exactly:
  1. Aborts if `git status --porcelain` is non-empty (dirty tree).
  2. Reads `version` from `package.json` as the base version.
  3. Lists local tags matching `<base>-ichatr.*`, computes the next `N` (starts at 1 if none
     exist; increments the highest existing `N` for the current base; resets to 1 whenever the
     base version itself changes — since the tag prefix `<base>-ichatr.` naturally changes with
     it, no separate reset logic is needed beyond scoping the tag search to the current base).
  4. Prints current base version, highest existing matching tag (or "None"), the computed next
     tag, and prompts `y/N` confirmation before doing anything remote.
  5. On confirmation: creates an annotated tag (`git tag -a <tag> -m "Release <tag>"`) and pushes
     it (`git push origin <tag>`).
  6. On decline or any command failure: aborts with a clear error message, no partial state left
     behind (no tag created if the push step is never reached; if tag creation fails, no push is
     attempted).

## Impact analysis

- **No changelog or GitHub Release automation.** Chatwoot's CI additionally generates a changelog,
  commits it to the main branch, and creates a GitHub Release on tag push. This phase does not
  replicate that for evolution-api — confirmed out of scope for this pass; the only required
  artifact is the Docker Hub image. Revisit as a separate phase if wanted later.
- **No CI gating (lint/build/tests) before tag push.** The release script's only precondition is a
  clean git tree, matching Chatwoot's own `bin/ichatr-release`, which likewise has no test-running
  step of its own (tests are a documented *manual prerequisite* in Chatwoot's Release Process, not
  something the script enforces). evolution-api additionally has `check_code_quality.yml` running
  independently on `main`/`develop` pushes — not tag pushes — so it provides no signal at
  release-tag time either way; this phase does not change that.
  `Dockerfile.metrics` publishing is not addressed by this phase — its purpose was not
  investigated, and none of the three existing publish workflows build or push it either, so this
  phase preserves that status quo rather than introducing new scope.
- **Idempotency / re-push safety.** If a tag already exists locally (e.g. a prior failed release
  attempt got as far as `git tag` but not `git push`), the script's tag-listing step (step 3 above)
  would count it toward the "highest existing tag" calculation, so a re-run computes the *next* N,
  not a duplicate — consistent with Chatwoot's own script behavior, not a new design decision.

## Validation

Manual only, gated by this fork's standing constraint: no commits and no tag pushes until the user
has validated locally and given explicit "ok" (per `CLAUDE.md`: *"NUNCA crie commits ou envie
alterações (push) para o remote antes de expressa validação/teste local pelo usuário."*).
Validation for this phase specifically means: running `bin/ichatr-release` locally against the
current repo state (expect it to compute and offer `2.3.7-ichatr.1` as the next tag, since no
matching tags exist yet), confirming the prompt text and computed values look right, then (only
after explicit user "ok") actually confirming the push and watching the new
`publish_docker_image_release.yml` workflow run in GitHub Actions to confirm
`edneymatias/evolution-api:2.3.7-ichatr.1` and `:latest` land on Docker Hub.

## Out of scope

- **Changelog generation and GitHub Release creation** — Chatwoot's CI does both on tag push; not
  replicated here in this pass (see "Impact analysis").
- **`Dockerfile.metrics` publishing** — separate, smaller build, not currently published by any
  existing workflow either; preserving status quo.
- **CI-enforced test/lint gating before a release tag can be pushed** — matches Chatwoot's own
  script, which likewise only enforces a clean git tree, not passing tests, as a scripted
  precondition.
- **Modifying `publish_docker_image_latest.yml` or `publish_docker_image_homolog.yml`** — no
  collision with this phase's tag-scoped trigger; left untouched.
