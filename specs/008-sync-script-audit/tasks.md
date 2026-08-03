# Tasks: Sync Script Audit Mode

**Input**: Design documents from `/specs/008-sync-script-audit/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli-contract.md, quickstart.md

**Tests**: Included — the existing `spec/bin/sync_custom_module_hooks_spec.rb` already establishes
an RSpec convention for this script, and User Story 3's acceptance criteria depend on `--check`/
`--audit` both being re-verified, so test coverage is added alongside each story rather than as a
separate opt-in step.

**Organization**: Tasks are grouped by user story (US1, US2, US3 per spec.md) for independent
implementation and testing. All script-edit tasks target the single file
`bin/sync-custom-module-hooks`, so most are sequential rather than `[P]` — parallelism here mainly
applies across independent RSpec examples once written test-by-test is unnecessary given the tiny
file count.

## Phase 1: Setup

**Purpose**: Confirm the starting point is clean before extending the script.

- [x] T001 Run `bin/sync-custom-module-hooks --check` and
      `docker compose exec rails bundle exec rspec spec/bin/sync_custom_module_hooks_spec.rb` to
      confirm the pre-feature baseline passes (11 existing manifest entries, 3 existing specs)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared audit-mode plumbing that both US1 (raw gap discovery) and US2 (exclusion
filtering) build on. MUST complete before either user story phase starts.

**⚠️ CRITICAL**: These tasks all edit `bin/sync-custom-module-hooks` sequentially (same file).

- [x] T002 Add `--audit [BASE_REF]` mode to the `ARGV[0]` dispatch in
      `bin/sync-custom-module-hooks` (alongside existing `--check`/`--apply` handling)
- [x] T003 Implement `BASE_REF` resolution in `bin/sync-custom-module-hooks`: use the given
      positional arg if present, otherwise shell out to `git merge-base <current-branch> develop`;
      exit non-zero with a clear error if the ref is unresolvable or no merge-base exists (per
      contracts/cli-contract.md)
- [x] T004 Implement diff computation in `bin/sync-custom-module-hooks`: union
      `git diff --name-status BASE_REF...HEAD` with the working-tree diff, keep only `M`-status
      paths (drop `A`/`D`/renames per spec.md Edge Cases)

**Checkpoint**: `--audit` now resolves a base ref and produces a raw list of modified core files.
User stories 1 and 2 can now build on this independently.

---

## Phase 3: User Story 1 - Maintainer discovers untracked core-file touches (Priority: P1) 🎯 MVP

**Goal**: Running audit mode against a base reference correctly partitions modified core files
into `covered` (has a `MANIFEST` entry) and `gap` (no entry) buckets.

**Independent Test**: Run audit mode against a known base reference and confirm modified core
files land in the correct `covered`/`gap` bucket, with unmodified/added files never flagged.

### Implementation for User Story 1

- [x] T005 [US1] Implement covered/gap classification in `bin/sync-custom-module-hooks`: for each
      candidate file from T004, mark `covered` if its path matches a `MANIFEST` entry's `file`,
      else `gap`
- [x] T006 [US1] Implement the two-bucket stdout output format in `bin/sync-custom-module-hooks`
      (`covered`/`gap` lines, all `covered` before all `gap`, summary line e.g. `N gaps found.`)
      per contracts/cli-contract.md; audit mode always exits `0` on a successful run regardless of
      gap count (per FR-005/FR-009)

### Tests for User Story 1

- [x] T007 [US1] Add RSpec coverage in `spec/bin/sync_custom_module_hooks_spec.rb` for: a modified
      file with a manifest entry reports `covered`, a modified file without one reports `gap`, a
      newly-added (non-`M`-status) file is never flagged
- [x] T008 [US1] Add RSpec coverage in `spec/bin/sync_custom_module_hooks_spec.rb` for default
      `BASE_REF` resolution via merge-base, and non-zero exit with a clear error when `BASE_REF` is
      unresolvable or has no merge-base

**Checkpoint**: User Story 1 is independently functional — audit mode reports accurate raw
covered/gap buckets (still noisy, since exclusions land in US2).

---

## Phase 4: User Story 2 - Maintainer excludes known noise from every future audit (Priority: P2)

**Goal**: Declared, data-driven exclusion rules suppress expected noise (schema.rb, spec/doc
files, non-English locales, annotate-gem churn) before classification.

**Independent Test**: Modify a file matching a declared exclusion pattern and confirm it never
appears in either bucket, even with no manifest entry.

### Implementation for User Story 2

- [x] T009 [US2] Add the `:path`-kind exclusion rule list in `bin/sync-custom-module-hooks`
      (`db/schema.rb`, `spec/**`, `docs/**`, `*.md`, non-English locale directories) as declarative
      data per FR-004
- [x] T010 [US2] Add the `:content`-kind annotate-gem exclusion rule in
      `bin/sync-custom-module-hooks`: for the fixed list of annotate-candidate model files, fetch
      the patch content via `git diff` and exclude only when every changed line falls inside the
      `# == Schema Information` ... block (per the clarification in spec.md — any additional
      non-annotate change means the file still surfaces as a gap)
- [x] T011 [US2] Apply all exclusion rules uniformly in `bin/sync-custom-module-hooks` before
      classification (T005), dropping matched files silently rather than listing them as a third
      category (per contracts/cli-contract.md)

### Tests for User Story 2

- [x] T012 [US2] Add RSpec coverage in `spec/bin/sync_custom_module_hooks_spec.rb` for path-based
      exclusions: `db/schema.rb`, a spec/doc file, and a non-English locale file are never flagged
      even without a manifest entry
- [x] T013 [US2] Add RSpec coverage in `spec/bin/sync_custom_module_hooks_spec.rb` for the
      annotate-gem rule: a file whose entire diff is annotate churn is excluded, and a file with
      annotate churn plus one unrelated change still surfaces as a `gap`

**Checkpoint**: Both user stories independently functional — audit mode now reports only genuine,
non-noise gaps.

---

## Phase 5: User Story 3 - Maintainer closes the gaps found by the first real audit (Priority: P1)

**Goal**: Add the 8 real `MANIFEST` entries found by the first audit run
(`docs/kanban/ciclo 2/06-sync-script-update/spec10.md`), then re-verify with `--check` and
`--audit`.

**Independent Test**: Run `--check` after the manifest update (all entries resolve), then re-run
`--audit 9d769dfcd` against the original range and confirm `0 gaps found.`

### Implementation for User Story 3

- [x] T014 [US3] Add `MANIFEST` entry for `config/application.rb` (eager_load_paths additions for
      `custom/lib` and `custom/app/**`) in `bin/sync-custom-module-hooks`
- [x] T015 [US3] Add `MANIFEST` entry for `config/routes.rb` (`resources :pipeline_stages` with
      nested `required_fields`, and `resources :opportunities`) in `bin/sync-custom-module-hooks`
- [x] T016 [US3] Add `MANIFEST` entry for `config/features.yml` (`opportunities` feature flag
      entry) in `bin/sync-custom-module-hooks`
- [x] T017 [US3] Add `MANIFEST` entry for `app/services/automation_rules/action_service.rb`
      (`prepend_mod_with('AutomationRules::ActionService')` wiring for the `create_opportunity`
      automation action) in `bin/sync-custom-module-hooks`
- [x] T018 [US3] Add comma-safe `MANIFEST` entry for
      `app/javascript/dashboard/i18n/locale/en/settings.json` (new automation-builder keys) in
      `bin/sync-custom-module-hooks`, per research.md's comma-safe JSON insert approach
- [x] T019 [US3] Add comma-safe `MANIFEST` entry for
      `app/javascript/dashboard/i18n/locale/en/automation.json` (new automation-builder keys) in
      `bin/sync-custom-module-hooks`, per research.md's comma-safe JSON insert approach
- [x] T020 [US3] Add `MANIFEST` entry for `app/javascript/dashboard/helper/automationHelper.js`
      (`create_opportunity` action support in the rule builder) in `bin/sync-custom-module-hooks`
- [x] T021 [US3] Add `MANIFEST` entry for
      `app/javascript/dashboard/composables/useAutomationValues.js` (`create_opportunity` action
      support in the rule builder) in `bin/sync-custom-module-hooks`

### Verification for User Story 3

- [x] T022 [US3] Run `bin/sync-custom-module-hooks --check` and confirm all manifest entries (the
      original 11 plus the 8 new ones) resolve successfully against the current tree (FR-008)
- [x] T023 [US3] Run `bin/sync-custom-module-hooks --audit 9d769dfcd` and confirm it reports
      `0 gaps found.` — the acceptance proof for SC-004
- [x] T024 [US3] Verify SC-003 directly: in a fresh clone/worktree checked out at the pre-manifest
      commit (no manual core-file edits), run `bin/sync-custom-module-hooks --apply` and confirm
      the custom Kanban module is fully wired in (all 19 manifest entries applied) using only the
      script — no manual editing of `config/application.rb`, `config/routes.rb`,
      `config/features.yml`, or the other 5 gap files required

**Checkpoint**: All user stories complete and independently verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T025 [P] Run
      `docker compose exec rails bundle exec rspec spec/bin/sync_custom_module_hooks_spec.rb` and
      confirm all existing and new examples pass
- [x] T026 [P] Run `docker compose exec rails bundle exec rubocop -a bin/sync-custom-module-hooks`
      and resolve any offenses introduced by the new code
- [x] T027 Execute `quickstart.md` steps 1-5 end-to-end as final manual validation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup; BLOCKS both User Story 1 and User Story 2
- **User Story 1 (Phase 3)**: Depends on Foundational; independent of User Story 2
- **User Story 2 (Phase 4)**: Depends on Foundational; layers exclusion filtering in front of US1's
  classification (T011 calls T005), so in practice implement after US1 lands, though the two
  stories test different concerns and could be built by different people against the same
  foundational diff/dispatch code
- **User Story 3 (Phase 5)**: Depends on User Story 1 and User Story 2 both being complete (the
  gaps it closes are only meaningful once audit mode correctly reports them)
- **Polish (Phase 6)**: Depends on all user stories being complete

### Within Each User Story

- Implementation tasks before their corresponding test tasks are written against real behavior
  (T005-T006 before T007-T008; T009-T011 before T012-T013)
- All `MANIFEST`-entry tasks in US3 (T014-T021) are independent of each other in content but edit
  the same file/array, so apply them sequentially to avoid merge overlap
- Verification tasks (T022-T024) run only after all US3 manifest entries land

### Parallel Opportunities

- T025 and T026 in Polish can run in parallel (different tool invocations, no shared state)
- Within US3, T014-T021 are conceptually independent (different manifest entries) but touch the
  same file/array, so they are not marked `[P]`

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP & VALIDATE**: Run audit mode against `9d769dfcd` and confirm the raw covered/gap split is
   accurate (still noisy — no exclusions yet)

### Incremental Delivery

1. Setup + Foundational → audit mode resolves a base ref and lists modified core files
2. Add User Story 1 → covered/gap classification works → validate independently
3. Add User Story 2 → exclusion rules suppress known noise → validate independently
4. Add User Story 3 → the 8 real gaps are closed and re-verified → validate independently (SC-004)
5. Polish → full spec suite, rubocop, quickstart pass

## Notes

- `[P]` tasks = different files or independent tool invocations, no shared-state conflicts
- `[Story]` label maps each task to its user story for traceability
- This is a single-script CLI feature (no web/mobile project structure) — all paths are
  repo-relative per plan.md's Project Structure section

## Phase 7: Convergence

- [x] T028 Move `# rubocop:disable Layout/LineLength` below the shebang in `bin/sync-custom-module-hooks` so the script executes correctly per Constitution III (contradicts)
