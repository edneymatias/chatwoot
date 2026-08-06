# Phase 0 Research: Upstream Sync, Branch Rebranding & Versioning Scheme

No `NEEDS CLARIFICATION` markers remain in the Technical Context (all decisions were already
settled in `spec30.md` and confirmed/sharpened during `/speckit-clarify`). This document records
the supporting decisions needed to turn the spec's functional requirements into an executable
runbook.

## Decision: Sync order (identify latest release tag → merge → gate → rename)

**Decision**: Execute in this exact order: (1) fetch upstream tags and identify the most recently
created tag on `chatwoot/chatwoot` as the sync target, (2) merge that tag into `matias-kanban`
with a single merge commit — or skip this step entirely if the branch is already at parity with
the tag, (3) run the full validation gate (`--check`, `--audit`, test suites), (4) only once
green, rename `matias-kanban` → `ichatr-main` and push/delete refs.

**Rationale**: FR-004/FR-005 require the sync target to be the latest upstream release tag, never
`upstream/develop` HEAD — an earlier execution of this feature merged `develop` HEAD directly and
had to be reverted after review found it pulled in incomplete/unreleased upstream work.
Sequencing the rename *after* the gate passes (rather than before or interleaved) avoids doing a
hard-to-reverse ref deletion (Constitution IV) on a branch that later turns out to need more
conflict-resolution work — if something goes wrong mid-merge, the maintainer is still working
under the old, safely disposable branch name.

**Alternatives considered**: Syncing against `upstream/develop` HEAD — rejected after review;
`develop` can contain features mid-rollout across multiple PRs or not yet shipped in any release,
which is unacceptable for a base the fork builds a product release on. Renaming first, then
merging on `ichatr-main` — rejected because it front-loads an irreversible step (deleting
`origin/matias-kanban`) before the merge is known to be safe, with no benefit (nothing depends on
the new name existing before the merge lands).

## Decision: Conflict-resolution stance (no fixed default side)

**Decision**: Per the Clarifications session, there is no standing rule that "fork always wins"
or "upstream always wins" on a semantic conflict. Each conflicted hunk in a manifest-tracked file
is resolved by re-reading upstream's new version of that logic and re-applying the fork's
customization on top of it, not by mechanically picking one side of the diff.

**Rationale**: Constitution Principle I (Upstream Compatibility First) — the fork is layered on
top of Chatwoot, so a stale fork implementation that ignores upstream's change becomes technical
debt that resurfaces on every subsequent sync.

**Alternatives considered**: A fixed "ours" or "theirs" git merge strategy per file — rejected;
explicitly ruled out during clarification (Option C chosen over A/B) because a blanket rule would
either silently drop upstream improvements or silently drop fork customizations depending on
direction, neither of which is safe to automate for a manifest-tracked wiring point.

## Decision: Audit-gap triage outcomes (manifest entry / exclusion / follow-up)

**Decision**: `bin/sync-custom-module-hooks --audit` gaps are triaged into exactly three buckets:
(1) new `MANIFEST` entry, (2) added to the script's `excluded`/`out_of_scope` list, or (3) if
closing the gap needs real code rework beyond a manifest/exclusion entry, logged as a follow-up
item and the sync fails loudly naming the file and the upstream change responsible (FR-006a).

**Rationale**: Keeps this phase's scope bounded to "get current and correctly tracked" per
Constitution Principle II (Smallest Production-Ready Change) and the spec's own out-of-scope
section — rework belongs to a dedicated follow-up, not ad hoc expansion of this sync.

**Alternatives considered**: Blocking the sync until every gap is fully re-integrated in code —
rejected during clarification (Option A chosen over B) as unbounded scope creep that could stall
the sync indefinitely on unrelated rework.

## Decision: Versioning scheme format and scope of `N`

**Decision**: `<upstream-base-version>-ichatr.<N>`, hyphen-delimited, `N` scoped per upstream
base and reset to `1` on every new base (FR-008/FR-009). The upstream base version is read
directly from the value already tracked in `package.json`'s `version` field at release-cut time
(that field already mirrors the upstream Chatwoot version this fork is built on, confirmed by the
current `package.json` value `4.16.2` matching the upstream base cited in the spec).

**Rationale**: A hyphen keeps the string valid as a git tag, Docker tag, and `package.json`
`version` field without translation (FR-008) — SemVer's `+build` metadata syntax is invalid in
Docker tags and some git tooling, and `~`/`_` are non-standard. Sourcing the base version from the
existing `package.json` field avoids introducing a second, parallel place to track "what upstream
version are we on."

**Alternatives considered**: A global incrementing counter independent of upstream base —
rejected by spec (FR-009 explicitly scopes `N` per base). SemVer build-metadata (`+`) suffix —
rejected by spec (FR-007) for cross-context validity reasons already stated above.

## Decision: Where the branch-model and versioning scheme get documented

**Decision**: Record the branch model (`ichatr-main` permanent, `develop` mirror-only, no
`release/*` scheme) and the version-tag scheme in `CLAUDE.md` under a new short section, since
`CLAUDE.md` is this repo's existing single source of tactical/day-to-day guidance (per the
constitution's Governance section: "`CLAUDE.md` takes precedence for day-to-day tactical detail").

**Rationale**: Avoids creating a second, competing doc location for branch/release conventions;
matches the constitution's own stated division of responsibility between the constitution
(architectural/governance) and `CLAUDE.md` (tactical detail like exact branch names).

**Alternatives considered**: A new standalone doc under `docs/` — rejected as unnecessary
indirection for a short, stable piece of tactical guidance that contributors already look to
`CLAUDE.md` for.
