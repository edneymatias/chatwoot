# Phase 82: Funnel Search/Filters by Campaign & Date, and Live Totals

**Status**: Design approved by the user on 2026-09-02 — ready for an implementation plan.

**Depends on**: none functionally on other backlog phases. Builds on top of
`app/finders/opportunities_filter.rb`, `custom/app/models/custom/concerns/opportunity_campaign_attribution.rb`
(campaign columns on `Opportunity`, added by `20260812010747_add_campaign_attribution_to_ichatr_opportunities.rb`),
the generic advanced-filter query builder already shared with Conversations/Contacts
(`app/javascript/dashboard/components-next/filter/`), and
`custom/app/controllers/api/v1/accounts/pipeline_stage_aggregates_controller.rb`.

## Quick Preview

Three related gaps in the Kanban funnel's top bar (search input + filter modal + totals badges),
all reported from real usage:

1. **Busca não cobre dados de campanha**: `q` (busca livre) só casa `title`/`Contact#name`. Não dá
   pra localizar uma oportunidade pelo nome da campanha, grupo de anúncio, anúncio ou plataforma que
   a originou, mesmo esses dados já existindo na `Opportunity` (Meta CTWA/Referral attribution).
2. **Filtros não cobrem campanha nem datas**: o construtor de filtro avançado (mesmo mecanismo já
   usado em Conversas/Contatos) não expõe os campos de campanha nem `created_at`/`updated_at` da
   oportunidade como atributos filtráveis.
3. **Totais do topo não reagem a busca/filtro, e ficam sem sentido em Ganhos/Perdidos**: a contagem
   e o valor em negociação exibidos no header (e o badge de cada coluna do Kanban) vêm de um
   endpoint de agregado (`PipelineStageAggregatesController`) que roda com `status: :open` fixo no
   código e é buscado **uma única vez**, no mount da tela — nunca de novo quando o operador digita
   uma busca, aplica um filtro, ou muda o status pra ver Ganhos/Perdidos.

All three fixes stay inside the existing search/filter/aggregate mechanisms — no new subsystem, no
new UI pattern.

## Part 1 — Search covers campaign attribution fields

`OpportunitiesFilter#apply_search` (`app/finders/opportunities_filter.rb:151-157`) extends its
existing `ILIKE` clause to also match `campaign_name`, `campaign_adset_name`, `campaign_ad_name`,
`campaign_platform`:

```ruby
def apply_search(relation)
  return relation if @params[:q].blank?

  query = ActiveRecord::Base.sanitize_sql_like(@params[:q])
  table = Opportunity.table_name
  relation.left_joins(:contact)
          .where(
            "#{table}.title ILIKE :q OR #{Contact.table_name}.name ILIKE :q OR " \
            "#{table}.campaign_name ILIKE :q OR #{table}.campaign_adset_name ILIKE :q OR " \
            "#{table}.campaign_ad_name ILIKE :q OR #{table}.campaign_platform ILIKE :q",
            q: "%#{query}%"
          )
end
```

### Performance: GIN trigram index

Today's search (`title`/`contacts.name`) already runs with **no text index** — it only stays cheap
because `account_id` (indexed) scopes the row set to a single tenant first. Adding four more
`ILIKE` branches on unindexed columns is the same category of cost already in production, not a new
one — but the fork already has a proven, better answer to this exact problem: `contacts` carries a
composite GIN trigram index over `name, email, phone_number, identifier`
(`db/schema.rb:811`, `pg_trgm` already enabled). New migration mirroring that pattern:

```ruby
class AddTrigramSearchIndexToIchatrOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_index :ichatr_opportunities,
               %i[title campaign_name campaign_adset_name campaign_ad_name],
               name: 'index_ichatr_opportunities_on_title_and_campaign_trgm',
               using: :gin,
               opclass: :gin_trgm_ops
  end
end
```

`campaign_platform` is intentionally excluded from the index (low-cardinality, matched via the
dropdown filter in Part 2 — see rationale there); it stays in free-text search via the plain `ILIKE`
above, just not index-accelerated (two known values, full scan is cheap regardless).

## Part 2 — Filters for campaign fields and opportunity dates

### Backend: new `contains`/`does_not_contain` operator for standard columns

The advanced-filter payload already supports `equal_to`, `not_equal_to`, `is_greater_than`,
`is_less_than`, `days_before`, `is_present`, `is_not_present` on real `Opportunity` columns
(`apply_standard_column_filter`, `app/finders/opportunities_filter.rb:98-112`), but not partial-text
matching. Campaign name/ad-group/ad fields need it (values are long/free-form — requiring an exact
match isn't useful). Same operator names and ILIKE approach already used in core's `FilterService`
for conversations (`app/services/filter_service.rb:29-31`):

```ruby
def apply_standard_column_filter(relation, key, vals, operator)
  case operator
  when 'not_equal_to'
    relation.where.not(key => vals)
  when 'is_greater_than'
    relation.where("#{Opportunity.table_name}.#{key} > ?", vals.first)
  when 'is_less_than'
    relation.where("#{Opportunity.table_name}.#{key} < ?", vals.first)
  when 'days_before'
    target = Date.current - vals.first.to_i.days
    relation.where("#{Opportunity.table_name}.#{key}::date = ?", target)
  when 'contains', 'does_not_contain'
    apply_contains_filter(relation, key, vals, operator)
  else
    relation.where(key => vals)
  end
end

def apply_contains_filter(relation, key, vals, operator)
  column = "#{Opportunity.table_name}.#{key}"
  clauses = vals.map { "#{column} ILIKE ?" }.join(' OR ')
  binds = vals.map { |v| "%#{ActiveRecord::Base.sanitize_sql_like(v.to_s)}%" }
  operator == 'does_not_contain' ? relation.where.not([clauses, *binds]) : relation.where([clauses, *binds])
end
```

`created_at`/`updated_at` need **no backend change** — they're already plain `Opportunity` columns,
and `apply_standard_column_filter`'s existing `is_greater_than`/`is_less_than`/`days_before` cases
already work against any column name generically (Postgres casts the string bind against the
`timestamp` column implicitly, same as it does today for any other standard column).

### Frontend: new filter types in `opportunityProvider.js`

`useOperators()` (`app/javascript/dashboard/components-next/filter/operators.js`) already exposes
`containmentOperators` (equal/not-equal/contains/does-not-contain — used today by Contacts' city/
company/referer filters) and `dateOperators` (greater-than/less-than/days-before — used today by
Contacts' `created_at`/`last_activity_at` filters). `opportunityProvider.js` currently only
destructures `equalityOperators`/`presenceOperators`; add the other two and six new entries to
`filterTypes`:

```js
const { equalityOperators, presenceOperators, containmentOperators, dateOperators, getOperatorTypes } =
  useOperators();

// ...inside filterTypes computed, after pipeline_stage_id, before ...customFilterTypes.value:
{
  attributeKey: 'campaign_name',
  value: 'campaign_name',
  attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_NAME'),
  label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_NAME'),
  inputType: 'plainText',
  dataType: 'text',
  filterOperators: containmentOperators.value,
  attributeModel: 'standard',
},
{
  attributeKey: 'campaign_adset_name',
  value: 'campaign_adset_name',
  attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_ADSET_NAME'),
  label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_ADSET_NAME'),
  inputType: 'plainText',
  dataType: 'text',
  filterOperators: containmentOperators.value,
  attributeModel: 'standard',
},
{
  attributeKey: 'campaign_ad_name',
  value: 'campaign_ad_name',
  attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_AD_NAME'),
  label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_AD_NAME'),
  inputType: 'plainText',
  dataType: 'text',
  filterOperators: containmentOperators.value,
  attributeModel: 'standard',
},
{
  attributeKey: 'campaign_platform',
  value: 'campaign_platform',
  attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_PLATFORM'),
  label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_PLATFORM'),
  inputType: 'searchSelect',
  options: [
    { id: 'facebook', name: 'Facebook' },
    { id: 'instagram', name: 'Instagram' },
  ],
  dataType: 'text',
  filterOperators: equalityOperators.value,
  attributeModel: 'standard',
},
{
  attributeKey: 'created_at',
  value: 'created_at',
  attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CREATED_AT'),
  label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CREATED_AT'),
  inputType: 'date',
  dataType: 'text',
  filterOperators: dateOperators.value,
  attributeModel: 'standard',
},
{
  attributeKey: 'updated_at',
  value: 'updated_at',
  attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_UPDATED_AT'),
  label: t('FILTER.ATTRIBUTES.OPPORTUNITY_UPDATED_AT'),
  inputType: 'date',
  dataType: 'text',
  filterOperators: dateOperators.value,
  attributeModel: 'standard',
},
```

`campaign_platform` is a plain string column (no DB enum) but only ever populated with `'facebook'`/
`'instagram'` today (`Custom::ReferralAttributionService.extract_platform`,
`custom/app/services/custom/referral_attribution_service.rb:35-43`) — a fixed dropdown gives better
UX (no typos/case mismatches) than free text for a field this low-cardinality; `equalityOperators`
matches the same pattern already used for the `status` filter type in this same file.

### i18n

New keys under `FILTER.ATTRIBUTES` in `advancedFilters.json` (`en` and `pt_BR`, per this fork's
sync-both-locales convention — no Crowdin). Distinct from the existing `CAMPAIGN_NAME` key already
in that namespace, which belongs to Chatwoot core's unrelated Campaigns feature, not the
opportunity's referral-attribution fields:

| Key | EN | PT-BR |
|---|---|---|
| `OPPORTUNITY_CAMPAIGN_NAME` | Campaign name | Nome da campanha |
| `OPPORTUNITY_CAMPAIGN_ADSET_NAME` | Ad group | Grupo de anúncio |
| `OPPORTUNITY_CAMPAIGN_AD_NAME` | Ad | Anúncio |
| `OPPORTUNITY_CAMPAIGN_PLATFORM` | Platform | Plataforma |
| `OPPORTUNITY_CREATED_AT` | Created at | Data de criação |
| `OPPORTUNITY_UPDATED_AT` | Updated at | Data de modificação |

## Part 3 — Live totals (bug fix)

### Root cause

`PipelineStageAggregatesController#index` hardcodes `status: :open` in its query and accepts no
other params. `pipelineStages/fetchAggregates` is dispatched exactly once, from `fetchInitialData()`
in `Index.vue`, on mount — nothing re-dispatches it when the `filters` ref (search `q`, advanced
filter `payload`, status) changes. The header totals (`OpportunitiesViewBar.vue`) and each Kanban
column's own count/value badge (`KanbanColumn.vue`) both read `stage.open_count`/
`stage.open_value_sum`, which are these same stale, always-`open` numbers.

### Backend: filter-aware aggregate query

`PipelineStageAggregatesController#index` runs the same `OpportunitiesFilter` the card listing
already uses, scoped to the requested stages, instead of a hand-rolled `status: :open` query. This
makes it respect `q`, `payload` (including a `status` filter condition, or `status=all`), and
`custom_attributes` — the exact same params `Api::V1::Accounts::OpportunitiesController#index`
already accepts:

```ruby
def index
  stage_ids = params[:stage_ids]
  return render_missing_stage_ids if stage_ids.blank?

  scope = OpportunitiesFilter.new(
    Current.account.opportunities.where(pipeline_stage_id: stage_ids), params
  ).perform.reorder(nil)

  counts = scope.group(:pipeline_stage_id).count
  values = scope.group(:pipeline_stage_id).sum(:value)

  aggregates = stage_ids.map do |raw_id|
    stage_id = raw_id.to_i
    { pipeline_stage_id: stage_id, count: counts[stage_id] || 0, value_sum: values[stage_id] || 0.0 }
  end

  render json: aggregates
end

private

def render_missing_stage_ids
  render json: { error: 'stage_ids is required' }, status: :unprocessable_entity
end
```

`.reorder(nil)` strips `OpportunitiesFilter#apply_sort`'s `ORDER BY` before grouping — required,
since Postgres rejects `GROUP BY` queries ordered by a column outside the grouped/aggregated set.
`apply_status_filter`'s existing default (`open` unless `status=all` or a `status` condition is
present in `payload`) is reused as-is, so a board with no filter applied keeps today's default
behavior unchanged.

### Field rename: `open_count`/`open_value_sum` → `count`/`value_sum`

Once the endpoint can return won/lost/all totals, the `open_`-prefixed names become misleading (e.g.
`open_count` showing a count of lost opportunities). Renamed consistently across the whole chain —
five files, all direct pass-through, no logic change beyond the name:

- `pipeline_stage_aggregates_controller.rb` (above) — response keys `count`/`value_sum`.
- `app/javascript/dashboard/api/pipelineStageAggregates.js` — `get(stageIds, filters = {})`:
  appends `filters.q`, `filters.status`, `filters.payload` (when present) to the existing
  `stage_ids[]` query string, alongside the current params.
- `app/javascript/dashboard/store/modules/pipelineStages/actions.js` — `fetchAggregates({ stageIds, filters })`
  reads `agg.count`/`agg.value_sum`, commits `SET_STAGE_AGGREGATES` with `count`/`valueSum`.
- `app/javascript/dashboard/store/modules/pipelineStages/mutations.js` — `SET_STAGE_AGGREGATES`
  stores `count`/`value_sum` on the stage object (was `open_count`/`open_value_sum`).
- `KanbanColumn.vue` (`props.stage.open_count`/`open_value_sum`, lines ~111-121) and
  `OpportunitiesViewBar.vue` (`totalLeadCount`/`totalValue`, lines 82-92) — read `stage.count`/
  `stage.value_sum`.

### Frontend: re-fetch aggregates when filters change

`Index.vue` gains a watcher alongside the existing `filters` ref, re-dispatching `fetchAggregates`
with the current filters on every change — same timing as the card list itself already uses today
(no debounce exists anywhere in the opportunities/Kanban view yet, so this introduces no new
inconsistency between when cards refresh and when totals refresh):

```js
watch(
  filters,
  () => {
    const stages = store.getters['pipelineStages/stagesSortedByPosition'];
    if (stages?.length) {
      store.dispatch('pipelineStages/fetchAggregates', {
        stageIds: stages.map(s => s.id),
        filters: filters.value,
      });
    }
  },
  { deep: true }
);
```

## Out of scope

- Debouncing search-as-you-type app-wide — neither the existing card-list fetch nor this phase's
  aggregate re-fetch debounce; if it becomes a real perf issue at higher traffic, that's a separate,
  broader phase (would also touch the card-list fetch, not just aggregates).
- Any change to how `campaign_platform` values are produced (`ReferralAttributionService`) — the
  dropdown just reflects the two values the extractor already produces today; a third platform
  showing up later needs its own small follow-up to the options list, not a dynamic/derived list in
  this phase (YAGNI — no evidence of more platforms yet).
- A trigram index covering `campaign_platform` — excluded from Part 1's index by design (see
  rationale there); can be added later with zero migration risk if ever needed.
- Backfilling/computing per-account aggregate history — this phase is only about the *current*
  filtered/searched view's totals, not trends over time (that's `08-campaign-performance-funnel-reports`,
  a separate backlog phase).
- Any change to `OpportunityListView.vue`'s own row count — it already reads
  `store.state.opportunities.pagination.all.totalCount`, populated by `opportunities/fetchAll`
  (which already receives `filters`), so it isn't affected by this bug and needs no change here.
- Full-text search ranking/relevance ordering — search stays a simple `ILIKE` match, same as today,
  just over more columns.

## Acceptance criteria

- Typing a campaign name, ad group name, ad name, or platform (`facebook`/`instagram`) into the
  Kanban search box returns matching opportunities, in addition to existing title/contact-name
  matches.
- The new GIN trigram index exists on `ichatr_opportunities` covering `title` and the three campaign
  text columns; `EXPLAIN` on a representative search query shows a bitmap index scan using it rather
  than a sequential scan.
- The filter modal offers campaign name/ad group/ad (contains/does-not-contain), platform (dropdown,
  equal/not-equal), and created-at/updated-at (date, same operators as Contacts' date filters) as
  new filterable attributes, in both `en` and `pt_BR`.
- Applying a "contains" filter on any campaign text field returns opportunities with a partial match,
  not just exact matches.
- Applying a date filter (`is_greater_than`/`is_less_than`/`days_before`) on `created_at` or
  `updated_at` returns the expected subset, matching the same operator semantics already used
  elsewhere in this filter (e.g. on custom attributes).
- Typing in the search box or applying/clearing any filter updates both the header totals (count +
  value) and every visible Kanban column's own badge, without a page reload.
- Setting the status filter to `won` or `lost` (or `all`) updates totals to reflect that status —
  no longer stuck showing (or silently ignoring) open-only numbers.
- With no filter applied, totals match exactly what they showed before this phase (open-only) — no
  regression to the default view.
- Full spec/lint suite (RuboCop, ESLint, RSpec, Jest) passes, including new/updated specs for
  `OpportunitiesFilter` (search + `contains`/`does_not_contain` + date operators on `created_at`/
  `updated_at`) and `PipelineStageAggregatesController` (status-aware, filter-aware aggregation).
