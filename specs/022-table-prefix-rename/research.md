# Research: Table Prefix Rename & Migration Namespace Policy

## Migration Wrapper (`bin/ichatr-migration`)
- **Decision**: Implement as a Ruby script (`#!/usr/bin/env ruby`).
- **Rationale**: The script needs to run `bundle exec rails generate migration "$@"` (via system call), capture the output to extract the generated `db/migrate/...` filename, parse the 14-digit timestamp prefix (`YYYYMMDDHHMMSS`), add 100 to the `YYYY` portion, and `mv` the file to the new timestamped name. Ruby is already available and provides more robust string/regex manipulation than raw Bash, ensuring we don't accidentally rename the wrong files.
- **Alternatives considered**: Bash script with `sed` and `awk` (rejected due to fragility across OS implementations of sed/awk and regex dialects).

## Existing Custom Migrations
- **Decision**: Modify the 13 identified `db/migrate/*_matias_*.rb` files directly.
- **Rationale**: We identified exactly 13 custom migration files using the `matias_` prefix. We will run a script (or manual task execution step) to mathematically add `100` to the year part of their timestamps, rename the files, and globally replace `matias` with `ichatr` inside their contents and class names (`Matias` -> `Ichatr`).
- **Alternatives considered**: None, this is strictly mandated by the specification `FR-002` and `FR-005`.

## Data Model & ORM Updates
- **Decision**: Update `self.table_name = 'ichatr_...'` in 7 models, plus the raw SQL in `OpportunityPolicy`.
- **Rationale**: The specification explicitly lists the 7 models and the 1 policy file.
- **Alternatives considered**: Relying on Rails implicit table names (rejected because custom prefix `ichatr_` differs from model names like `Opportunity`).
