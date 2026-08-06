# Phase 13: Standalone Patch Package Extraction

**Status**: dropped — see decision below

**Decision (2026-08-06)**: Dropped. See Phase 30
(`docs/kanban/ciclo 7/10-upstream-sync-and-versioning/spec30.md`) — this
fork is shipping as a full checkout via its own Docker image, not as a
patch applied onto a pinned upstream base, so standalone extraction no
longer serves a purpose. The manifest/audit machinery this phase depended
on (Phase 10) lives on, repurposed as the upstream-sync validation gate.
**Depends on**: Phase 10 (sync script + manifest must be complete and
accurate first — the manifest is the actual inventory of every core-file
touch, and becomes the input for whatever extraction mechanism gets
designed here)

## Quick Preview

Instead of the custom Kanban module living permanently inside this
checkout's git history, extract it into its own self-contained repository
holding only the patch (the `custom/` source plus the core-file touches
currently tracked in `bin/sync-custom-module-hooks`'s `MANIFEST`). A
script would pull a pinned/homologated Chatwoot version, apply the patch,
and leave the tree ready to use — possibly retargetable to a specific
Chatwoot release, not just whatever commit this fork happens to be on
today.

Motivation: keep the amount of untracked drift from upstream from
accumulating (raised alongside Phase 10), and stop carrying the full
Chatwoot source tree inside a repo that's conceptually just "one team's
Kanban add-on."

Open questions for the brainstorm:

- Patch format: raw diff/patch files applied via `git apply`, a
  maintained commit series (rebase/cherry-pick onto the pinned base), or
  the existing anchor/insert `MANIFEST` mechanism extended to also cover
  content that today lives as full-file diffs (not just single-line
  inserts)?
- Version pinning: track a specific upstream tag/commit as "homologated,"
  with an explicit process for bumping it (and re-validating the patch
  still applies)?
- What happens to `custom/`'s own tests, migrations
  (`db/migrate/*matias*`), and seed helpers (`lib/seeders/account_seeder.rb`)
  — do they travel as part of the patch package, or stay separate?
- Local/fork-only files excluded from Phase 10's manifest scope
  (`docker-compose.yaml`, `.gitignore`, `AGENTS.md`) — do these get
  reintroduced as part of the bootstrap script's own scaffolding (since
  they'd no longer be "core touches" to a shared tree, just this new
  repo's own dev setup)?
- Where does this new repo live, and what's the actual bootstrap script's
  interface (`./bootstrap.sh <chatwoot-ref> <target-dir>`? a Rake task?)?
- How does this interact with ongoing development — does `matias-kanban`
  keep being the working branch, with periodic re-extraction, or does
  development move to happen directly against the patch repo?
