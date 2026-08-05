# Data Contract: `conversion_funnel` (within the Opportunity Funnel Report API response)

**Status note**: The `GET /api/v1/accounts/:account_id/opportunity_funnel_reports` endpoint and
its backing service, `Reports::OpportunityFunnelBuilder` (`custom/app/services/reports/opportunity_funnel_builder.rb`),
already exist and already ship `labels`/`count_data`/`won_rate_pct` (see `research.md`, Decision
2 — corrected from an earlier, mistaken "no backend exists" finding). This document specifies
that existing contract plus the one additive `counts` field this feature adds (FR-008).

## Shape

```jsonc
{
  "conversion_funnel": {
    "labels": ["Lead", "Qualified", "Proposal", "Won"],  // existing — stage names, in PipelineStage#position order
    "count_data": [100, 42, 18, 9],                      // existing — percentage (0-100) of period total reaching each stage
    "won_rate_pct": 9,                                   // existing — overall first-stage-to-won conversion rate
    "counts": [2895099, 264277, 74828, 7917]              // NEW (additive) — raw opportunity count per stage
  }
}
```

## Field notes

- `labels`, `count_data`, `won_rate_pct`: **unchanged** — already consumed by
  `OpportunityFunnelReport.vue` today; this feature does not alter their meaning or calculation.
- `counts` (**new**, this feature — FR-008): raw opportunity count per stage, same array
  length/order as `labels`, computed by `Reports::OpportunityFunnelBuilder#conversion_funnel`
  from data it already has in memory (see `data-model.md`). Additive only — no existing field is
  renamed, removed, or reinterpreted, and it ships atomically with the backend change (not a
  field the frontend needs to treat as optional).

## Frontend consumer mapping

`OpportunityFunnelReport.vue` builds the `FunnelPoint[]` passed to `<FunnelChart :points="…">`
by zipping these arrays with the existing `stageColorByName` lookup:

```js
const funnelPoints = computed(() => {
  const d = reportData.value?.conversion_funnel;
  if (!d) return [];
  return d.labels.map((label, i) => ({
    label,
    percentage: d.count_data[i],
    count: d.counts[i],
    color: stageColorByName.value[label] || DEFAULT_BAR_COLOR,
  }));
});
```

This replaces the existing `conversionFunnelData` computed (built for `BarChart`'s
`{ labels, datasets }` shape), which is removed once `FunnelChart` replaces `BarChart` in this
section.
