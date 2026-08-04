# Quickstart: Deal Card Customization

Verify inside the `rails`/`vite` containers per this repo's standard dev workflow
(`docker compose up -d`, then `docker compose exec rails ...` / `docker compose exec vite ...`).

## Prerequisites

- The stack is running with at least one account that has:
  - A few `opportunity_attribute` custom attributes already defined (Settings → Custom Attributes,
    or seeded via `Seeders::AccountSeeder`)
  - Some kanban deals (opportunities) with values set on some of those custom attributes, and some
    left blank
- Logged in as an account administrator

## 1. Configure card fields

1. Go to Settings → Pipeline Stages → **Card Fields** tab (shown first, before "Pipeline Stages"
   and "Closing Requirements").
2. Check 2-3 fields (a mix of existing custom attributes and "Deal Value"), assigning a color to
   each via the inline color picker.
3. Try checking a 4th field — confirm the checkbox is disabled and a "3/3 selected" hint is shown.
4. Save.

**Expected**: no error; reloading the tab shows the same 3 selections and colors pre-filled.

## 2. Verify badges on the board

1. Open the kanban board for the same account.
2. For a deal that has values for all 3 configured fields: confirm 3 colored badges render, each
   showing only the value (no field-name label), ordered by configuration order.
3. For a deal missing a value on one configured field: confirm only 1-2 badges render (the missing
   one is skipped, no empty placeholder).
4. For a deal with none of the 3 fields populated: confirm the entire badge row is absent (no
   empty gap on the card).

## 3. Verify removal cascade

1. Back in Card Fields settings, uncheck one configured field and save.
2. Reload the board — confirm that field's badge no longer appears on any card.
3. Delete one of the other configured custom attribute definitions entirely (Settings → Custom
   Attributes).
4. Reload Card Fields settings and the board — confirm that field's config is gone from settings
   and its badge is gone from all cards, with no error.

## 4. Verify no-config baseline

1. On a different account with zero configured card fields, open the kanban board.
2. Confirm cards render exactly as before this feature (no new row, no visual change).

## Contract reference

See [contracts/pipeline-card-field-configs-api.md](contracts/pipeline-card-field-configs-api.md)
for the exact request/response shapes exercised by the above.

## Lint gate

`docker compose exec vite pnpm eslint` and `docker compose exec rails bundle exec rubocop` must
pass for all touched files.
