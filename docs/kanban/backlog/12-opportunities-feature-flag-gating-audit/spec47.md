# Phase 47: Opportunities Feature Flag — Full Gating Audit

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 1 (backend core — defines the `opportunities` Super Admin feature flag, `config/features.yml:271-274`); every subsequent phase that added a new opportunities-touching surface (routes, settings screens, automation integration, Contact Panel, reports).

## Quick Preview

Manual test: disabling the `opportunities` feature flag in Super Admin does not fully hide the
feature. Confirmed so far by reading the code (not yet a full audit):

- **Correctly gated**: `dashboard.routes.js` — the `opportunities_index` (Kanban) route meta
  already checks `FEATURE_FLAGS.OPPORTUNITIES`. `ContactPanel.vue`'s "previous_opportunities"
  section already checks `isOpportunitiesFeatureEnabled` too.
- **Not gated (confirmed gaps)**:
  - `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/pipelineStages.routes.js`
    (Pipeline Stage settings) — no feature-flag check found; stays reachable/visible with the flag
    off.
  - The `create_opportunity` automation action (`AutomationActionInput.vue`,
    `useAutomationValues.js`, `settings/automation/constants.js`) — no feature-flag check found;
    the action stays offered in the automation rule builder with the flag off.
  - The two opportunity report routes (`opportunity_funnel_reports`, `opportunity_attribute_reports`
    in `reports.routes.js`) are gated by `FEATURE_FLAGS.REPORTS`, not `FEATURE_FLAGS.OPPORTUNITIES`
    — they stay visible whenever Reports is enabled, regardless of the Opportunities flag.

This phase needs a full, systematic audit (not just the spots found above) of every
opportunities-touching surface — frontend routes/menu entries/settings screens/automation
condition+action pickers/report entries, and backend API endpoints (should a disabled account's
Opportunities API reject requests outright, not just have its UI hidden, for defense in depth?) —
then add the missing checks consistently.

Open questions for the brainstorm:
- Frontend-only (hide) vs. also backend-enforced (403/404 the API when the flag is off) — the
  current gaps are all frontend visibility gaps, but should this phase also close the backend gap
  as a security/consistency matter?
- Is there a case for centralizing the check (a shared composable/directive/route-meta convention)
  instead of repeating `isOpportunitiesFeatureEnabled` per component, to prevent this same drift
  from recurring as new surfaces get added?
- Full inventory pass needed before implementation: walk every route, sidebar entry, settings
  screen, and automation picker that references opportunities to confirm the complete gap list
  beyond the three found above.
