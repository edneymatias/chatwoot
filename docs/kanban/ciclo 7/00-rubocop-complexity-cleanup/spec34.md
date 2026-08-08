# Phase 34: RuboCop Complexity/Size Cleanup

**Depends on**: none — this is a prerequisite for future fork development, not tied to the List
View v2 feature work in this cycle.

## Context

Preparing the last release, RuboCop flagged several fork-authored methods for excessive
complexity and length (`Metrics/AbcSize`, `Metrics/MethodLength`, `Metrics/CyclomaticComplexity`,
`Metrics/PerceivedComplexity`). To unblock the release, `rubocop --auto-gen-config` was run and
its output committed to `.rubocop_todo.yml`, which masks the offenses via per-file `Exclude`
lists (`AbcSize`, `MethodLength`) and a codebase-wide threshold bump (`CyclomaticComplexity`/
`PerceivedComplexity` `Max: 11`, up from RuboCop's defaults of `Max: 7`/`Max: 8`). None of the
underlying code was actually simplified — the offenses still exist, only hidden.

Since then, a new offense (`custom/app/services/custom/automation_rules/action_service.rb`,
introduced by recent automation-rules work) was added without going through
`--auto-gen-config`, so it is not masked and is the direct cause of `lint-backend` currently
failing on CI (`gh run list --branch ichatr-main` shows repeated failures). This confirms the
problem is recurring, not one-off, which is why this phase also adds guidance to `AGENTS.md` (and
therefore `CLAUDE.md`, which symlinks it) so future LLM-driven changes stay under the thresholds
instead of accumulating new exceptions.

**Explicit scope boundary**: `.rubocop_todo.yml` also masks two legacy/upstream rake-task files
(`lib/tasks/captain_assistant_migration.rake`, `lib/tasks/download_report.rake`) that happen to
benefit from the same `CyclomaticComplexity`/`PerceivedComplexity` `Max: 11` bump. Those files are
not fork-authored and are explicitly **not** touched by this phase — they stay masked
permanently. Only fork-owned code is refactored here.

## Backend — Config

- **FR-001**: Move `Metrics/CyclomaticComplexity: Max: 11` and `Metrics/PerceivedComplexity:
  Max: 11` out of `.rubocop_todo.yml` and into `.rubocop.yml` as permanent, documented project
  settings (alongside the existing `Metrics/MethodLength`/`Metrics/AbcSize` baseline overrides
  already there), with a comment explaining why the fork's threshold is looser than RuboCop's
  default (it permanently covers two legacy rake-task files this fork does not intend to touch;
  see FR-003).
- **FR-002**: Once each fork-owned method in scope (FR-004 through FR-009) is refactored to pass
  under the baseline `Metrics/MethodLength` (Max 19) and `Metrics/AbcSize` (Max 26) thresholds
  already defined in `.rubocop.yml`, remove its corresponding `Exclude` entry from
  `.rubocop_todo.yml`. This applies to `custom/app/models/opportunity.rb`,
  `custom/app/services/reports/opportunity_funnel_builder.rb`, `lib/seeders/account_seeder.rb`,
  and `spec/bin/sync_custom_module_hooks_spec.rb`.
- **FR-003**: All other `.rubocop_todo.yml` entries — including the `Exclude` lists that cover
  `lib/tasks/captain_assistant_migration.rake` and `lib/tasks/download_report.rake` (masked via
  the `Max: 11` bump moved in FR-001, plus their own `Layout`/`Lint` excludes) and every entry
  unrelated to complexity/size cops (`Layout/LineLength`, `RSpec/DescribeClass`,
  `RSpec/InstanceVariable`, `RSpec/LetSetup`, `Rails/Exit`, `Rails/I18nLocaleTexts`) — are left
  untouched. This phase does not attempt to fully revert to RuboCop's strict defaults.

## Backend — Refactors

Each item below must pass `docker compose exec rails bundle exec rubocop <file>` clean against the
baseline thresholds in `.rubocop.yml` (post-FR-001), with existing spec coverage for the touched
files still passing (`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec
rspec <corresponding spec>`), before its `.rubocop_todo.yml` exclude is removed.

- **FR-004**: `custom/app/models/opportunity.rb#as_json` (AbcSize 26.48/26) — extract the
  `contact` and `assignee` sub-hash construction into private helper methods (e.g.
  `contact_json`, `assignee_json`), reducing the branching/assignment load in the main method
  body.
- **FR-005**: `custom/app/models/opportunity.rb#validate_forward_stage_move_requirements`
  (AbcSize 27.96/26, CyclomaticComplexity 11/7, PerceivedComplexity 11/8) — extract the
  missing-required-fields computation (iterating `pipeline_stage.required_custom_attribute_definitions`
  and building `missing_keys`) into a private helper that returns the missing keys, keeping the
  validation method itself focused on the early-return guards and the `errors.add` call.
- **FR-006**: `custom/app/services/reports/opportunity_funnel_builder.rb#new_opportunities_over_time`
  (AbcSize 27.75/26, CyclomaticComplexity 10/7, PerceivedComplexity 10/8) — extract the
  day-bucketed count/value aggregation (the `group('DATE(created_at)')` queries and the
  `all_days.map` fills) into a private helper, keeping the public method focused on the `range`
  guard and assembling the final hash.
- **FR-007**: `lib/seeders/account_seeder.rb#seed_opportunities` (MethodLength 28/19) — extract
  the pipeline stage / custom attribute definition / required field setup into a private helper
  separate from the loop that creates the three sample opportunities.
- **FR-008**: `spec/bin/sync_custom_module_hooks_spec.rb#setup_files` (MethodLength 21/19) — split
  the fixture-writing logic into per-commit helper methods (e.g. one for each of the two git
  commits it writes), per this project's existing preference for direct per-example setup over
  monolithic helpers.
- **FR-009**: `custom/app/services/custom/automation_rules/action_service.rb#create_opportunity`
  (MethodLength 21/19, currently unmasked and failing CI) — extract the `assignee_id` resolution
  (the `assignee_id_param == 'same_as_conversation'` branch) into a private helper (e.g.
  `resolve_assignee_id`).

## Documentation

- **FR-010**: Add a short guideline to `AGENTS.md` (which `CLAUDE.md` symlinks, so it applies to
  all LLM tooling reading either file) under an existing or new subsection near the RuboCop
  command reference. It should state: run `bundle exec rubocop` on touched files before
  considering backend work done; stay under the project's `Metrics/MethodLength` (19) and
  `Metrics/AbcSize` (26) thresholds by extracting private helpers for distinct sub-steps (framed
  as consistent with the existing "avoid one-use private helpers unless they hide real complexity"
  guidance — complexity-driven extraction satisfies that exception); and that new
  `.rubocop_todo.yml` exceptions are not an acceptable way to resolve a complexity/length
  offense — only refactoring is.

## Out of scope

- The two legacy/upstream rake-task offenses masked by the `Max: 11` bump
  (`captain_assistant_migration.rake`, `download_report.rake`) — not fork-authored, left masked
  permanently (see FR-003).
- The `lint-frontend` CI failure on the current `ichatr-main` branch — an ESLint/frontend
  concern, unrelated to RuboCop.
- The `backend-tests` rspec failures currently seen on CI — not investigated as part of this
  phase; if any are caused by the refactors in this phase, they must still pass, but pre-existing
  unrelated failures are not this phase's responsibility to fix.
- Any other `.rubocop_todo.yml` entries not tied to `Metrics/AbcSize`, `Metrics/MethodLength`,
  `Metrics/CyclomaticComplexity`, or `Metrics/PerceivedComplexity` (see FR-003).
