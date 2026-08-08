# Phase 30: Upstream Sync, Branch Rebranding & Versioning Scheme

**Implemented as**: [specs/021-upstream-sync-versioning](../../../../specs/021-upstream-sync-versioning/)
(spec-kit feature `021-upstream-sync-versioning`)

**Depends on**: Phase 10 (sync script + manifest — `bin/sync-custom-module-hooks`,
must already exist and be runnable in `--check`/`--audit`/apply modes, which
it is)

## Context

This fork is about to become a standalone product ("ichatr"): its own
Docker image, its own registry, its own release cadence — not just a
Chatwoot checkout with a Kanban add-on bolted on. Before any of the
release-engineering work (CI/CD, image publishing, table-prefix rename) can
happen, the fork's working branch needs to (a) sit on a known-stable
upstream base, and (b) get a permanent identity as the fork's long-term
branch instead of a feature-branch name (`matias-kanban`) that no longer
describes what it is.

This phase is purely about getting the branch onto a stable base and
correctly identified — no image publishing, no table rename, no version tag
cut yet. Those are separate phases (table-prefix rename, CI/CD, release
cut), deliberately sequenced after this one so they build on a stable base.

**Correction (2026-08-06)**: an earlier pass of this phase merged the fork
up to the tip of `upstream/develop` directly. That was a mistake and has
been reverted. `upstream/develop` is Chatwoot's active integration branch —
it can and does contain features that are incomplete or mid-rollout across
multiple PRs (e.g. a commit explicitly titled as part 1 of a 5-part
rollout), as well as features that haven't shipped in any tagged release
yet. Merging that HEAD into the fork risks shipping unfinished upstream
behavior and inheriting upstream build/toolchain issues that haven't been
stabilized for a release. **The fork must be synced against the latest
*tagged* upstream release, never against `develop` HEAD.** At the time of
this correction the latest upstream tag is `v4.16.2`, and the fork's branch
was already at parity with it before the bad merge was attempted (its
pre-merge tip's merge-base with `v4.16.2` was one trivial version-bump
commit short of the tag) — so no sync merge is actually needed right now.
This phase's only concrete remaining action is the branch rename below; the
sync procedure is documented for the next time a new upstream tag is cut.

**Decision made during brainstorming**: Phase 13 (standalone patch-package
extraction into its own bootstrap-able repo) is dropped. It was designed
for a scenario where the Kanban module would be distributed independently
of a full Chatwoot checkout; that no longer applies now that the fork
itself — full checkout included — is the thing being shipped as v1.0's
Docker image. The manifest/audit machinery Phase 13 depended on (Phase 10)
is still very much needed, just repurposed here as the sync's validation
gate rather than as input to a patch-extraction tool.

## Branch model going forward

**FR-001**: `matias-kanban` is renamed to `ichatr-main`
(`git branch -m matias-kanban ichatr-main`), pushed to `origin`, and the old
`origin/matias-kanban` ref is deleted. `ichatr-main` becomes the fork's
single permanent long-term branch (model "A" from the brainstorm): all
future work (this release, v1.1, v2.0, ongoing features) branches off it
and merges back via PR; there is no separate `release/*` branch scheme.
Future upstream syncs repeat this same phase's steps periodically, merging
into `ichatr-main` directly.

**FR-002**: The local `develop` branch is kept as a plain mirror of
`upstream/develop` — fast-forwarded whenever it's needed for reference
(e.g. diffing an in-progress upstream feature before it ships), never
diverges with its own commits, and is **never merged into `ichatr-main`
directly**. It exists purely as a read reference; it is not the sync
source.

## Sync procedure

**FR-003**: The sync target is always the **latest tagged upstream
release** (`git tag --sort=-creatordate | head -1` against the
`chatwoot/chatwoot` upstream remote), never `upstream/develop` HEAD. A sync
is triggered by a new upstream tag being cut, not on a schedule and not by
`develop` moving.

**FR-004**: Merge the upstream release tag into `ichatr-main` with a single
merge commit (not rebase) — chosen because `ichatr-main` is a permanent
branch, not a short-lived feature branch; a single merge resolves conflicts
once instead of replaying conflict resolution across each of the fork's
existing commits. Conflicts are expected primarily in the core files the
manifest already tracks (`dashboard.routes.js`, `Sidebar.vue`,
`actionCable.js`, `store/index.js`, `settings.routes.js`,
`automationHelper.js`, etc.), since those are exactly the files both
upstream and the fork touch.

**FR-005**: After the merge lands (conflicts resolved, build green), the
sync isn't considered done until this gate passes, in order:
1. `bin/sync-custom-module-hooks --check` — every existing MANIFEST
   insertion must still be present in its target file post-merge. A
   conflict resolution that silently dropped a customization is caught
   here.
2. `bin/sync-custom-module-hooks --audit` — detects any core file changed
   since the merge-base that isn't yet covered by a MANIFEST entry (custom
   touches made since the manifest was last updated). Every reported gap
   is triaged by hand: either added as a new MANIFEST entry, or added to
   the script's own `excluded`/`out_of_scope` list if it's legitimately not
   a wiring point that needs tracking.
3. Full test suite (`bundle exec rspec`, `pnpm test`) run to green.

**FR-006**: No version tag is cut as part of this phase. The versioning
scheme is decided here (see below) so later phases don't need to
re-litigate it, but the actual tag/release happens in the release-cut
phase, after the table-prefix rename and CI/CD phases are also done and
validated in the staging environment.

## Versioning scheme

**FR-007**: Fork releases are tagged `<upstream-base-version>-ichatr.<N>`
(e.g. `4.16.2-ichatr.1`), using a hyphen (not `+`) so the identifier is
valid as a git tag, a Docker image tag, and a `package.json` `version`
field without translation between contexts.

**FR-008**: `N` is scoped to the upstream base version, not global — it
increments only when cutting an additional fork release **against the same
upstream base** (e.g. a hotfix that doesn't require pulling new upstream
commits: `4.16.2-ichatr.1` → `4.16.2-ichatr.2`). The first release cut
after syncing to a new upstream base always resets to `.1` (e.g. the next
sync to `4.17.0` starts at `4.17.0-ichatr.1`, regardless of how high `N`
reached on the previous base).

## Out of scope

- Cutting any actual version tag or Docker image — belongs to the
  release-cut phase, after table-prefix rename and CI/CD are in place.
- Table-prefix rename and migration-collision policy — separate phase
  (already scoped in the "Custom Module Infra Hardening" spec).
- CI/CD pipeline changes — separate phase.
- Pointing the production VPS at a new image — explicitly deferred by the
  user to be done manually, later, after a staging/homologação environment
  validates the release.
- Phase 13 (standalone patch-package extraction) — dropped, not
  resurrected by this phase.
