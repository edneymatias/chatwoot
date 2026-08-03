# Implementation Plan: Sync Script Audit Mode

**Branch**: `008-sync-script-audit` | **Date**: 2026-08-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-sync-script-audit/spec.md`

## Summary

Extend the existing `bin/sync-custom-module-hooks` script (Ruby, stdlib-only, no gem
dependencies) with a new `--audit [BASE_REF]` mode that diffs a base git ref against the current
HEAD + working tree, drops paths matching a declared, data-driven set of permanent exclusion
rules, and reports the remaining modified core files as either **covered** (already has a
`MANIFEST` entry) or **gap** (modified, no entry). The one non-trivial rule — annotate-gem
schema-comment churn — requires inspecting diff *content*, not just changed paths, and per
clarification only excludes a file when its entire diff is annotate churn. After the audit mode
lands, the 8 gaps found by the first real run (see `docs/kanban/ciclo 2/06-sync-script-update/spec10.md`)
are added to `MANIFEST`, and `--check`/`--audit` are both re-run as the acceptance proof.

## Technical Context

**Language/Version**: Ruby (matches the existing script and repo's Ruby toolchain; no new
runtime required)

**Primary Dependencies**: None beyond Ruby stdlib (`json`) and shelling out to the `git` CLI
already available in the dev container — mirrors the existing script's zero-gem design

**Storage**: N/A — reads git history and the in-file `MANIFEST` constant; writes nothing except
the manifest source edit itself (a normal code change, not a runtime write)

**Testing**: RSpec, following the established pattern in `spec/bin/sync_custom_module_hooks_spec.rb`
(shell out to the script binary with a `TEST_MANIFEST` env override, assert on stdout + exit
status), run via `docker compose exec rails bundle exec rspec spec/bin/sync_custom_module_hooks_spec.rb`

**Target Platform**: Linux dev container (`rails` service) / any shell with `git` on `PATH`;
invoked interactively by a maintainer, not part of the app runtime

**Project Type**: Single-file CLI script (`bin/`)

**Performance Goals**: N/A — one-shot invocation over a bounded local git diff; no throughput or
latency target beyond "fast enough for interactive use between commands"

**Constraints**: Must preserve the existing script's zero-runtime-dependency design (Ruby stdlib +
`git` only, no network access, no new gems); exclusion rules must be expressed as data (patterns),
not per-file conditional branches, per FR-004

**Scale/Scope**: Single local git repository per invocation; no concurrency, no multi-user
considerations

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. `bin/sync-custom-module-hooks` is fork-owned
  tooling (not an upstream file); the audit mode only *reads* git history and prints a report, it
  never edits core files itself. Closing the gaps it finds (Phase 1c) uses the same
  anchor/insert `MANIFEST` mechanism already in place — no new core-editing mechanism introduced.
- **II. Smallest Production-Ready Change** — PASS. One additive mode branch in an existing
  `ARGV[0]` dispatch, plus manifest data entries; no refactor of `--check`/`--apply`, no
  speculative generalization beyond what FR-004 requires (data-driven exclusions).
- **III. Adhere to Established Conventions** — PASS. Ruby/RuboCop conventions for the script;
  RSpec tests follow the exact `run_script`/`TEST_MANIFEST` shape already used in
  `spec/bin/sync_custom_module_hooks_spec.rb`.
- **IV. Safe, Reversible Change Management** — PASS. Audit mode is read-only (git diff + stdout);
  no destructive git operations. Manifest edits are ordinary reversible source changes.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — N/A. No app-level endpoint, model, or
  controller surface is touched; this is dev tooling only, not product code.

No violations. Complexity Tracking is not needed.

**Post-Phase 1 re-check**: The Phase 1 design (data-model.md, contracts/cli-contract.md,
quickstart.md) introduces no new files, dependencies, or core-file edits beyond what was already
evaluated above — the `:content`-kind exclusion rule and comma-safe JSON insert are both
implementation detail within the existing single-script, data-driven structure. All five gates
remain PASS.

## Project Structure

### Documentation (this feature)

```text
specs/008-sync-script-audit/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/
│   └── cli-contract.md   # Phase 1 output — audit mode's CLI/output contract
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
bin/
└── sync-custom-module-hooks   # existing script; gains --audit mode + MANIFEST gap entries

spec/bin/
└── sync_custom_module_hooks_spec.rb   # existing spec file; gains audit-mode coverage
```

**Structure Decision**: No new files or directories. This is a targeted extension of one existing
CLI script and its one existing spec file — consistent with Principle II (smallest change) and
the fact that `bin/sync-custom-module-hooks` is a single-file, dependency-free tool by design.

## Complexity Tracking

*No Constitution Check violations — this section is intentionally empty.*
