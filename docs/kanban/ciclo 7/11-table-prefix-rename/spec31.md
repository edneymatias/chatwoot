# Phase 31: Table Prefix Rename & Migration Namespace Policy

**Depends on**: Phase 30 (upstream sync — do this on top of the synced,
`ichatr-main`-renamed base, not before), none functionally beyond that

## Context

Every custom table created by the Kanban module uses a `matias_` prefix —
not professional-looking for a module that's becoming its own product
("ichatr"). This phase renames the prefix to `ichatr_` and, while touching
every custom migration anyway, also closes the second concern the original
placeholder (`spec20`, now superseded by this spec) raised: migration
timestamp collisions with upstream.

The local/dev database has no data worth preserving, so this is done as a
direct edit of the original migration files (not a new `rename_table`
migration) followed by a full local rebuild — the cleanest possible result,
with no `matias_`-prefixed table ever having existed in the migration
history.

## Table & file inventory

**FR-001**: 7 tables renamed: `matias_opportunities` →
`ichatr_opportunities`, `matias_pipeline_stages` → `ichatr_pipeline_stages`,
`matias_opportunity_stage_changes` → `ichatr_opportunity_stage_changes`,
`matias_pipeline_stage_required_fields` →
`ichatr_pipeline_stage_required_fields`,
`matias_pipeline_closing_required_fields` →
`ichatr_pipeline_closing_required_fields`,
`matias_pipeline_card_field_configs` → `ichatr_pipeline_card_field_configs`,
`matias_pipeline_currency_settings` → `ichatr_pipeline_currency_settings`.

**FR-002**: All 13 existing custom migration files under `db/migrate/` are
edited in place — table/column/index symbols and `foreign_key: { to_table:
... }` references updated from `matias_*` to `ichatr_*` — and renamed (both
filename and class name) to match, e.g.
`20260730224300_create_matias_pipeline_stages.rb` /
`CreateMatiasPipelineStages` becomes
`21260730224300_create_ichatr_pipeline_stages.rb` /
`CreateIchatrPipelineStages` (see FR-004 for the timestamp change). The two
explicitly-named indexes
(`idx_matias_pipeline_stage_req_fields_on_acc_and_attr_def`,
`idx_matias_pipeline_closing_req_fields_on_acc_attr_outcome`) get their
`name:` string updated to the `ichatr_` equivalent in the same edit. No new
migration is added — because these are `create_table`/`add_column`/
`add_index` statements being edited directly (not a `rename_table` against
an existing table), every Rails-default-named index, foreign key, and
sequence is generated correctly under the new name automatically, with no
extra rename step needed.

**FR-003**: 7 models get `self.table_name = 'matias_...'` updated to
`'ichatr_...'` (`Opportunity`, `PipelineStage`, `OpportunityStageChange`,
`PipelineStageRequiredField`, `PipelineClosingRequiredField`,
`PipelineCardFieldConfig`, `PipelineCurrencySetting`). Their `annotaterb`
schema-comment blocks are regenerated via `bundle exec annotaterb models`
after the DB rebuild (FR-006), not hand-edited. The one raw-SQL reference
outside the ORM — `custom/app/policies/opportunity_policy.rb:48`
(`'matias_opportunities.assignee_id = :user_id OR '`) — is updated by hand,
since it isn't reachable by the model's `table_name` change.

## Migration timestamp policy

**FR-004**: All 13 migration files above are re-stamped with their
timestamp's year shifted **+100 years** (e.g. `20260730224300` →
`21260730224300`), preserving each file's original relative ordering
(only the year digits change, so chronological order among the 13 files is
untouched).

**FR-005**: Going forward, every new ichatr-authored migration is created
with the same +100-year offset applied to its real authoring timestamp.
This is a permanent, mechanical rule — not a per-migration judgment call —
so it needs no manual cross-checking against upstream, ever: upstream
Chatwoot will never generate a real migration timestamped 100 years in the
future, so a version collision (or ordering ambiguity) between an ichatr
migration and an upstream one becomes structurally impossible. A new
wrapper script, `bin/ichatr-migration NAME`, runs the standard
`rails generate migration` and rewrites the generated file's timestamp
(filename prefix) to apply the +100-year offset automatically, so nobody
has to compute the offset by hand. This closes the migration-collision
question raised by the original `spec20` placeholder — no reserved
timestamp *range* scheme was needed, just a fixed future offset.

## Rebuild & verification

**FR-006**: Local database is rebuilt from scratch:
`bundle exec rails db:drop db:create db:migrate` — acceptable because the
local/dev database holds no data worth preserving. `db/schema.rb` is
regenerated as part of this.

**FR-007**: After the rebuild, a final repo-wide case-insensitive grep for
`matias` outside `docs/` must return zero hits (excluding this spec's own
historical references and any other kanban docs describing past state) —
confirming no stray reference to the old prefix was missed in models,
policies, factories, or elsewhere.

**FR-008**: Full test suite (`bundle exec rspec`, `pnpm test`) must pass
green before this phase is considered done.

## Out of scope

- Any change to tables outside the 7 listed — no other part of the schema
  uses the `matias_` prefix.
- Renaming the `matias-kanban` git branch — already done in Phase 30
  (`ichatr-main`).
- Preserving any existing local data through the rename — explicitly not a
  goal; the local DB is disposable.
- Retroactively re-stamping any *upstream* migration — the +100-year offset
  applies only to ichatr-authored migrations.
