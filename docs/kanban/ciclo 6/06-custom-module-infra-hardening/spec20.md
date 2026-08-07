# Phase 20 (candidate): Custom Module Infra Hardening

**Status**: placeholder — idea parked, not yet brainstormed
**Depends on**: none functionally, but touches every table/migration the
Kanban module has created so far (Phases 1, 6, 7, 19) — best done once
those are stable, not mid-flight

## Quick Preview

Two related infra concerns raised while reviewing table naming, worth
their own brainstorm:

### 1. Table/prefix naming

All custom tables use a `matias_` prefix (`matias_pipeline_stages`,
`matias_opportunities`, `matias_pipeline_stage_required_fields`, and
`matias_pipeline_closing_required_fields` once Phase 19 lands) — 6
migration files and 3+ models (`table_name = 'matias_...'`) reference it
today. Not professional-looking for a module meant to be reused/shared;
candidate replacement prefix floated: `ichatr` (needs confirming — spell
out what it stands for and confirm final spelling before touching
anything).

Renaming existing tables mid-flight means a migration (`rename_table`)
plus updating every model's `self.table_name`, plus rechecking anything
that references the old name as a raw string (foreign key names,
index names generated from the table name, `add_foreign_key` calls with
explicit `to_table:`).

### 2. Migration timestamp collision with upstream

Custom migrations live in the ordinary `db/migrate/` directory, interleaved
with upstream Chatwoot migrations, using normal timestamp-based
filenames. There's currently no scheme protecting against a future
upstream migration landing with a timestamp that collides with (or sorts
ambiguously relative to) one of the custom module's migrations — no
reserved timestamp range, no separate migration path. Worth evaluating:
is this a real risk (Rails errors loudly on duplicate `version` in
`schema_migrations`, so a true collision is caught, not silent) or is the
actual concern just messy/interleaved migration history that's harder to
read? If a real fix is warranted, it likely connects to the same
territory as Phase 10 (sync script) and Phase 13 (patch package
extraction) — how the custom module's migrations travel with the rest of
the patch.

Open questions for the brainstorm: final prefix decision; whether the
prefix rename is a single big migration or can be done incrementally per
table; whether migration collision is worth a dedicated mechanism (e.g. a
reserved timestamp prefix convention) or is adequately handled by Rails'
existing version-collision failure mode.
