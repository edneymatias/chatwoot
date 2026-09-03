# Phase 0 Research: Funnel Search Filters and Live Totals

All unknowns from the Technical Context were resolved by reading current repo state (not assumed
from the source design doc, `docs/kanban/ciclo 11/14-funnel-search-filters-and-live-totals/spec82.md`,
which was written before this repo state was re-verified). No `[NEEDS CLARIFICATION]` markers
remain in `plan.md`'s Technical Context.

## 1. Search: expanding `OpportunitiesFilter#apply_search`

**Decision**: Add `campaign_name`, `campaign_adset_name`, `campaign_ad_name`, `campaign_platform`
to the existing `ILIKE` disjunction in `apply_search` (`app/finders/opportunities_filter.rb`),
scoped by the same `left_joins(:contact)` already in place. Back it with a new GIN trigram index
on `(title, campaign_name, campaign_adset_name, campaign_ad_name)`, excluding `campaign_platform`.

**Rationale**: Verified current `apply_search` (lines 151-157 in the design doc's line numbers;
confirmed present, unchanged, in the live file) only matches `title`/`contacts.name` with no
index — cost today is bounded solely by the `account_id` index scoping each tenant. Adding four
ILIKE branches is the same cost category. The fork already has a proven pattern for this exact
problem: `contacts` has `index_contacts_on_name_email_phone_number_identifier` (verified at
`db/schema.rb:810`, `gin`/`gin_trgm_ops`), and `pg_trgm` is already enabled. Mirroring it is the
smallest production-ready fix (Constitution II) and requires no new extension pattern.

`campaign_platform` is excluded from the index because it only ever holds two values today
(verified: `Custom::ReferralAttributionService.extract_platform`,
`custom/app/services/custom/referral_attribution_service.rb:35-43`, produces only `'facebook'`/
`'instagram'`) — a full scan over two possible values is cheap regardless of index, and it's
better served by an equality filter (see §3) than free-text.

**Alternatives considered**:
- A separate full-text search column/`tsvector`: rejected — overkill for 4 short string columns
  scoped by tenant, and inconsistent with the fork's own `contacts` precedent (which uses trigram,
  not tsvector).
- Indexing `campaign_platform` too: rejected per Out-of-scope in spec.md (YAGNI; two known values).

## 2. Filters: `contains`/`does_not_contain` operator + date attributes

**Decision**: Add a `contains`/`does_not_contain` branch to
`OpportunitiesFilter#apply_standard_column_filter`, delegating to a small `apply_contains_filter`
helper (ILIKE with `sanitize_sql_like`). No backend change needed for `created_at`/`updated_at` —
`apply_standard_column_filter`'s existing `is_greater_than`/`is_less_than`/`days_before` branches
already operate generically on any real column name, verified by reading the current
`apply_standard_column_filter` (confirmed unchanged from the design doc, lines ~91-107 live).

**Rationale**: `contains`/`does_not_contain` operator semantics and naming already exist end-to-end
in core's `FilterService` for conversations (`app/services/filter_service.rb:29-31`) — reusing the
same operator names keeps the frontend operator vocabulary (`useOperators()`) consistent across
Conversations/Contacts/Opportunities, satisfying Constitution III (established conventions) without
inventing new operator semantics.

**Alternatives considered**:
- A dedicated `LIKE ANY(array)` Postgres construct instead of `map { ILIKE } .join(' OR ')`:
  rejected — the existing `apply_custom_attribute_value_filter` in the same file already uses the
  join-OR pattern for its `IN`-style clauses; consistency with sibling code wins for a fork this
  size, and volumes here are tenant-scoped and small.

## 3. Frontend filter attribute registration

**Decision**: In `opportunityProvider.js`, additionally destructure `containmentOperators` and
`dateOperators` from `useOperators()` (already exported — verified at
`app/javascript/dashboard/components-next/filter/operators.js:170,172`) and append six new entries
to the `filterTypes` computed array: `campaign_name`, `campaign_adset_name`, `campaign_ad_name`
(all `inputType: 'plainText'`, `containmentOperators`), `campaign_platform` (`inputType:
'searchSelect'`, fixed `[facebook, instagram]` options, `equalityOperators`), `created_at`,
`updated_at` (`inputType: 'date'`, `dateOperators`).

**Rationale**: `equalityOperators`/`presenceOperators` are already the only two operator sets used
in this file today (verified: lines 17-18, current file); the containment/date sets are proven
elsewhere in the same operator module (Contacts' city/company/referer and
`created_at`/`last_activity_at` filters, per the design doc, itself consistent with the operator
module's own doc comments). No new `inputType` is introduced — `plainText`, `searchSelect`, and
`date` are all handled by the shared filter-input renderer already (used by `assignee_id` and
`pipeline_stage_id` in the same file).

**Alternatives considered**: A dynamic/derived platform option list sourced from distinct values in
the DB — rejected per spec.md's explicit Assumption (two fixed values; YAGNI, revisit only if a
third platform appears in production).

## 4. i18n key placement

**Decision**: Add six new keys under the existing `FILTER.ATTRIBUTES` object in
`app/javascript/dashboard/i18n/locale/en/advancedFilters.json` and the `pt_BR` counterpart, named
with an `OPPORTUNITY_` prefix (`OPPORTUNITY_CAMPAIGN_NAME`, `OPPORTUNITY_CAMPAIGN_ADSET_NAME`,
`OPPORTUNITY_CAMPAIGN_AD_NAME`, `OPPORTUNITY_CAMPAIGN_PLATFORM`, `OPPORTUNITY_CREATED_AT`,
`OPPORTUNITY_UPDATED_AT`), inserted after the existing `"LAST_ACTIVITY"` key (verified: `en` and
`pt_BR` versions of `advancedFilters.json` have identical structure, `ATTRIBUTES` object spans
lines 49-69, `LAST_ACTIVITY` is the last key at line 68).

**Rationale**: `FILTER.ATTRIBUTES` is a flat namespace shared across every filter-consuming feature
(Conversations, Contacts, Opportunities all resolve the same locale bundle — verified each
`locale/<lang>/index.js` merges all JSON files under that locale into one bundle). It already
contains an unrelated `CAMPAIGN_NAME` key that belongs to core's Campaigns feature (email/SMS
outreach campaigns), not this fork's ad-attribution data — the `OPPORTUNITY_` prefix avoids a
label collision that would otherwise show the wrong label on whichever feature's filter modal
renders second. Per this fork's no-Crowdin convention (CLAUDE.md, constitution
"Personalization Boundaries"), both `en` and `pt_BR` are updated in the same change.

**Alternatives considered**: Renaming or reusing the existing generic `CREATED_AT`/`LAST_ACTIVITY`
keys for the opportunity date filters — rejected; those keys are already bound to conversation
semantics ("Last activity" reads oddly for an opportunity's `updated_at`), and reusing them risks
an unrelated future wording change to conversations silently relabeling the opportunity filter.

## 5. Live totals: filter-aware, status-aware aggregation

**Decision**: Rewrite `PipelineStageAggregatesController#index` to run
`OpportunitiesFilter.new(Current.account.opportunities.where(pipeline_stage_id: stage_ids),
params).perform.reorder(nil)`, then `group(:pipeline_stage_id).count` /
`group(:pipeline_stage_id).sum(:value)`. Rename response keys `open_count`/`open_value_sum` →
`count`/`value_sum`. Propagate the rename through `pipelineStageAggregates.js` (extend `get()` to
accept and serialize `filters`), the `fetchAggregates` Vuex action (accept `{ stageIds, filters }`,
read `agg.count`/`agg.value_sum`), the `SET_STAGE_AGGREGATES` mutation (store `count`/`value_sum`),
and both consumers (`KanbanColumn.vue`, `OpportunitiesViewBar.vue`).

**Rationale**: Root cause (verified directly, not just from the design doc) is threefold and all
three pieces were confirmed live in the repo during Phase 0:
- `custom/app/controllers/api/v1/accounts/pipeline_stage_aggregates_controller.rb:13-14` hardcodes
  `status: :open` and reads no other params.
- `pipelineStageAggregates.js`'s `get(stageIds = [])` only ever serializes `stage_ids[]` — there is
  no path today to pass `q`/`payload`/`status` through even if the controller understood them.
- `Index.vue`'s `fetchInitialData()` (lines 15-32) dispatches `fetchAggregates` exactly once, with
  no `watch(filters, ...)` anywhere in the file — confirmed the only existing `watch` targets
  `viewMode` (line 62), and a stale code comment at lines 56-58 incorrectly claims columns already
  watch `filters`.

Reusing `OpportunitiesFilter` (rather than hand-rolling equivalent WHERE clauses in the aggregates
controller) means every filter this feature's Parts 1-2 add to the card list is automatically
also honored by totals — one shared filter path, satisfying Constitution II (smallest change:
no parallel filter-building logic to maintain).

`.reorder(nil)` is required because `OpportunitiesFilter#apply_sort` always applies an `ORDER BY`
(default `created_at DESC`), and Postgres rejects `GROUP BY` queries ordered by a column outside
the grouped/aggregated set.

**Alternatives considered**:
- Keeping `open_count`/`open_value_sum` names and just changing their *meaning* per status:
  rejected — once the endpoint can return won/lost/all totals, `open_count` showing e.g. a lost-only
  count is actively misleading; a rename is a one-time, mechanical, five-file change (all direct
  pass-through, confirmed no other consumer exists via repo-wide search for `open_count`/
  `open_value_sum`).
- Debouncing the new `watch(filters, ...)` in `Index.vue`: rejected per spec.md's explicit
  Assumption — no debounce exists anywhere in this view today (search-as-you-type included), so
  adding one only to the aggregate refresh would introduce a new inconsistency between when the
  card list updates and when totals update, not remove one.

## 6. Migration timestamp / naming convention

**Decision**: New migration file named
`db/migrate/21260902000000_add_trigram_search_index_to_ichatr_opportunities.rb`, following this
fork's existing (year-2126-prefixed) timestamp convention for its own migrations (verified against
the 15 most recent files in `db/migrate/`, e.g. `21260817140000_create_ichatr_opportunity_activities.rb`).

**Rationale**: Matches existing sequential-timestamp convention exactly (must sort after the latest
existing migration); using `ActiveRecord::Migration[7.1]` matches the version already used by
sibling migrations in the same directory.

## 7. Test file locations

**Decision**: New backend specs go to `spec/finders/opportunities_filter_spec.rb` and
`spec/requests/api/v1/accounts/pipeline_stage_aggregates_controller_spec.rb` — both under the core
`spec/` tree, not `custom/spec/`, even though the controller implementation itself lives under
`custom/app/controllers/...`.

**Rationale**: Verified by direct inspection: the sibling controller `pipeline_stages_controller.rb`
(also under `custom/app/controllers/api/v1/accounts/`) has its spec at
`spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb` (referenced directly in this
fork's own `CLAUDE.md` test commands) — not under `custom/spec/requests/`. `custom/spec/requests/`
does exist and holds specs for some `custom/app/controllers` files (e.g.
`pipeline_stage_required_fields_controller_spec.rb`), so both locations are technically live in
this repo; matching the closer sibling (`pipeline_stages_controller_spec.rb`, same directory,
same resource family) is the more consistent choice. `opportunities_filter_spec.rb` has no
existing sibling to match (the finder itself lives in core `app/finders/`, unlike the controllers),
so it follows the plain `spec/finders/` convention already used for e.g. `conversation_finder_spec.rb`.

## Deferred / explicitly out of scope (not researched further)

- The pre-existing duplicated route block in `config/routes.rb` (lines 142-158 and 159-174 both
  declare `pipeline_stage_aggregates`, `opportunities`, etc.) — a real repo issue found during
  research, but unrelated to this feature and not touched by this plan; worth flagging to the user
  as a separate cleanup candidate.
- Debouncing search-as-you-type or the new aggregate watcher app-wide (spec.md Out of scope).
- Backfilling/computing historical aggregate trends (spec.md Out of scope; belongs to a separate
  backlog phase, `08-campaign-performance-funnel-reports`).
