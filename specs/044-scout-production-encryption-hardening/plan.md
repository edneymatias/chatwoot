# Implementation Plan: Scout Production Encryption Hardening

**Branch**: `044-scout-production-encryption-hardening` | **Date**: 2026-08-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/044-scout-production-encryption-hardening/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Close the production-safety gap identified in spec64.md/spec61.md: make it possible to (a) get the
three `ACTIVE_RECORD_ENCRYPTION_*` keys into the real production Docker Swarm stack via a
mechanism Swarm actually honors, and (b) confirm, and prove, that `Scout`/`ScoutTool` sensitive
fields (`api_key_override`/`auth_headers`) cannot be persisted in plaintext when those keys are
missing in production. Research (see `research.md`) found that requirement (b) is **already fully
implemented and tested** by Phase 1 (`specs/042-scout-core-data-model`): both models call
`encrypts` unconditionally, and Rails' own `ActiveRecord::Encryption` raises
`ActiveRecord::Encryption::Errors::Configuration` on save whenever keys are absent in
`RAILS_ENV=production` (no fallback exists outside dev/test), which `scout_spec.rb`/
`scout_tool_spec.rb` already assert. The remaining, genuinely new work for this feature is
therefore deployment configuration and an operator verification runbook, not application code:
update `docker-compose.production.yaml` so the keys can actually reach the Swarm stack, and
document/validate the verification steps in `quickstart.md`.

## Technical Context

**Language/Version**: Ruby on Rails 7.1.5.2 (existing app; no new language/runtime)

**Primary Dependencies**: Rails `ActiveRecord::Encryption` (built-in, already wired in
`config/application.rb`); no new gems

**Storage**: PostgreSQL — existing `ichatr_scouts`/`ichatr_scout_tools` tables, no schema change

**Testing**: RSpec — existing `custom/spec/models/scout_spec.rb` and `scout_tool_spec.rb` already
cover the fail-closed behavior this feature depends on; used as acceptance evidence, not extended
unless a gap is found during implementation

**Target Platform**: Docker Swarm production deployment (Linux)

**Project Type**: Single Rails monolith (existing) — this feature is a deployment-configuration and
operational-verification change, not a new service or module

**Performance Goals**: N/A (not a runtime-performance-sensitive change; verification steps are a
one-time manual operator action per deploy)

**Constraints**: No new application code required for FR-004–FR-007 (see research.md §1); changes
confined to the fork-owned `docker-compose.production.yaml` template and this feature's own
`quickstart.md` runbook — no core/enterprise files touched

**Scale/Scope**: Single production Swarm stack; smallest-change scope per research.md

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS, WITH JUSTIFICATION. `docker-compose.production.yaml`
  is in fact an upstream-tracked file (present in Chatwoot since `1ee17cc82`, still receiving
  upstream commits). The edit is nonetheless justified because it is strictly additive — three new
  blank `ACTIVE_RECORD_ENCRYPTION_*` lines appended to each service's existing `environment:` block,
  following the file's own established `POSTGRES_PASSWORD=` placeholder pattern — with no
  restructuring, renaming, or removal of existing keys. No merge-blocking extension point exists for
  a deploy-template's `environment:` list (unlike application code, there is no
  `prepend_mod_with`-equivalent for Compose files), so a direct additive edit is the smallest
  mergeable change available; future `upstream/develop` changes to this file's other keys/services
  are expected to apply cleanly around these lines. No `app/`/`enterprise/` files are touched. The
  Scout models already comply (Phase 1's decision record).
- **II. Smallest Production-Ready Change**: PASS — reinforced by research.md's finding that no new
  guard/validation code is needed; the plan explicitly avoids adding a redundant `before_save`
  check or a rake task wrapping an existing one-line method call.
- **III. Adhere to Established Conventions**: PASS. The `docker-compose.production.yaml` edit
  follows the file's existing `environment:`/placeholder-comment pattern (as used for
  `POSTGRES_PASSWORD`); no Ruby/JS code is added that would need RuboCop/ESLint conformance.
- **IV. Safe, Reversible Change Management**: PASS. All changes are additive config lines and a new
  documentation file; nothing destructive.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS — N/A. No core logic or public API surface is
  touched; `enterprise/` is unaffected.

No blocking violations. One Principle I justification recorded above (direct, additive edit to the
upstream-tracked `docker-compose.production.yaml`) — see Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/044-scout-production-encryption-hardening/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command) — no new entities
├── quickstart.md         # Phase 1 output (/speckit-plan command) — operator runbook
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory is produced — this feature exposes no new API endpoint, CLI command, or
UI surface (see data-model.md).

### Source Code (repository root)

```text
docker-compose.production.yaml   # Add explicit ACTIVE_RECORD_ENCRYPTION_* placeholders to the
                                  # `rails` and `sidekiq` services' `environment:` blocks
                                  # (research.md §3); no other repository code changes.

custom/app/models/scout.rb       # Unchanged — already satisfies FR-004/FR-006/FR-007
custom/app/models/scout_tool.rb  # Unchanged — already satisfies FR-005/FR-006/FR-007
custom/spec/models/scout_spec.rb       # Unchanged — existing "fails closed" coverage is the
custom/spec/models/scout_tool_spec.rb  # acceptance evidence for FR-004/FR-005 (research.md §1)
```

**Structure Decision**: This is a configuration-and-documentation-only feature on top of the
existing single-Rails-app structure — no new source tree, service, or module is introduced. The
only tracked-file change is `docker-compose.production.yaml`; the rest of the deliverable is the
`quickstart.md` operator runbook already produced in this plan's Phase 1 design step.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Principle | What's touched | Why needed | Simpler alternative rejected because |
|-----------|-----------------|------------|----------------------------------------|
| I. Upstream Compatibility First | Direct edit to upstream-tracked `docker-compose.production.yaml` (adding blank `ACTIVE_RECORD_ENCRYPTION_*` entries to `rails`/`sidekiq` `environment:` blocks) | The three keys must reach Docker Swarm at deploy time; `env_file:` is confirmed unreliable under `docker stack deploy` (spec61.md/spec64.md), and this is the file operators actually copy to run the real stack | A fork-owned override file (e.g. `docker-compose.override.yaml`) was rejected because CLAUDE.md scopes that mechanism to local/untracked dev overrides only, not production secrets delivery, and Swarm stack files don't support Compose's dev-only override-merge convention the same way `docker compose` does locally |
