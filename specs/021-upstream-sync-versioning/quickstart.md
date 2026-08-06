# Quickstart: Validating the Upstream Sync

Runnable validation for this feature's three user stories. See [data-model.md](./data-model.md)
for entity definitions and [contracts/sync-gate-cli.md](./contracts/sync-gate-cli.md) for the
exact gate contract.

## Prerequisites

- Local clone with both remotes configured: `origin` (`edneymatias/chatwoot`) and `upstream`
  (`chatwoot/chatwoot`) — already present in this checkout (`git remote -v`).
- `bin/sync-custom-module-hooks` present and runnable (already exists per this spec's
  dependency on Phase 10).
- Clean working tree (`git status` shows no pending changes) before starting.

## User Story 1: Sync validated by the manifest gate and test suite

1. Fast-forward the mirror:
   ```
   git checkout develop
   git fetch upstream
   git merge --ff-only upstream/develop
   ```
   Expected: fast-forward succeeds with no conflicts (spec Assumption: zero local-only commits on
   `develop` today).

2. Merge into the fork's working branch:
   ```
   git checkout matias-kanban
   git merge --no-ff develop
   ```
   Expected: conflicts (if any) appear primarily in manifest-tracked files (see plan.md's Project
   Structure list). Resolve each case-by-case per the Clarifications session — re-read upstream's
   new version of the logic and re-apply the fork's customization, rather than mechanically
   picking one side.

3. Run the manifest `--check` gate:
   ```
   bin/sync-custom-module-hooks --check
   ```
   Expected: exit `0`. Any non-zero exit means a customization was dropped during conflict
   resolution — fix before continuing.

4. Run the manifest `--audit` gate:
   ```
   bin/sync-custom-module-hooks --audit
   ```
   Expected: every reported file is `covered`. Triage any `gap` per the contract in
   `contracts/sync-gate-cli.md` (manifest entry, exclusion, or logged follow-up) and re-run until
   no gap remains untriaged.

5. Run the full test suites:
   ```
   docker compose exec rails bundle exec rspec
   docker compose exec vite pnpm test
   ```
   Expected: both exit `0`. Sync is not complete until this step is green.

## User Story 2: Branch rebranding

1. Confirm User Story 1's gate passed (do not rename before it does).
2. Rename and push:
   ```
   git branch -m matias-kanban ichatr-main
   git push origin ichatr-main
   git push origin --delete matias-kanban
   ```
3. Verify:
   ```
   git ls-remote --heads origin ichatr-main    # expect one line (ref exists)
   git ls-remote --heads origin matias-kanban   # expect empty (ref gone)
   ```
4. Open a throwaway branch from `ichatr-main`, confirm it can be merged back via PR (manual
   check in the repo's PR UI) — validates SC-004.

## User Story 3: Versioning scheme sanity check

No commands to run (no tag is cut in this phase). The scheme is shipped as new "Branch model" and
"Fork versioning scheme" sections in `CLAUDE.md` (tasks T024/T025) — validate that documentation
against [data-model.md](./data-model.md)'s "Fork version tag" section and the spec's acceptance
scenarios:
- Base `4.16.2`, first release → `4.16.2-ichatr.1`
- Same-base hotfix → `4.16.2-ichatr.2`
- New base `4.17.0`, first release → `4.17.0-ichatr.1` (not `.3`)

If a release engineer can derive all three from the documented rule alone, SC-005 is satisfied.
