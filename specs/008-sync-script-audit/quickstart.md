# Quickstart: Validating Sync Script Audit Mode

## Prerequisites

- Dev stack running: `docker compose up -d` (see project `CLAUDE.md`)
- A working tree on this fork's `develop`-derived branch history

## 1. Run the audit against the known gap-producing range

```bash
bin/sync-custom-module-hooks --audit 9d769dfcd
```

**Expected outcome (before the manifest update lands)**: the 8 files listed in
`docs/kanban/ciclo 2/06-sync-script-update/spec10.md`'s "Gaps" table are printed under `gap`, and
the 7 files in "Already covered" are printed under `covered`. See
`contracts/cli-contract.md` for the exact output shape.

## 2. Confirm exclusions suppress expected noise

```bash
bin/sync-custom-module-hooks --audit 9d769dfcd
```

**Expected outcome**: `db/schema.rb`, any `spec/**`/`docs/**`/`*.md` paths, non-English locale
files, and files whose *entire* diff is annotate-gem schema-comment churn do not appear in either
bucket. If a listed annotate-candidate file (e.g. `app/models/category.rb`) has any non-annotate
change alongside the churn, it must appear under `gap`, not be silently excluded (per the
clarification in `spec.md`).

## 3. Close the gaps

Add the 8 missing entries to `MANIFEST` in `bin/sync-custom-module-hooks`, using the existing
anchor/insert shape (see `research.md`'s comma-safe JSON note for `settings.json`/`automation.json`).

## 4. Re-verify

```bash
bin/sync-custom-module-hooks --check
bin/sync-custom-module-hooks --audit 9d769dfcd
```

**Expected outcome**:
- `--check` exits `0` and reports all manifest entries (old and new) present/resolvable.
- `--audit` reports `0 gaps found.` — this is the acceptance proof for User Story 3 / SC-004.

## 5. Run the RSpec suite

```bash
docker compose exec rails bundle exec rspec spec/bin/sync_custom_module_hooks_spec.rb
```

**Expected outcome**: existing `--check`/`--apply` tests still pass, plus new audit-mode
coverage (exclusion rules, covered/gap partitioning, default `BASE_REF` behavior, non-zero exit on
an unresolvable ref) added alongside them.
