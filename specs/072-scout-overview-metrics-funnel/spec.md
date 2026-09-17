# Feature Specification: Scout Overview — Summary Metrics & Funnel Distribution

**Feature Branch**: `072-scout-overview-metrics-funnel`

**Created**: 2026-09-16

**Status**: Draft

**Input**: User description: "Scout Overview page with summary metric cards (total handled, qualification rate, disqualification rate, abandonment rate, messages-per-conversation) and two funnel-distribution charts (current pipeline stage snapshot and interest-by-stage breakdown), scoped per Scout with conditional Scout selector and period selector."

## Clarifications

### Session 2026-09-16

- Q: Who is authorized to view the Scout Overview page and its data? → A: Same as Captain Overview — any account member (agent + admin) scoped to their account, no extra role gate.
- Q: Oportunidades "In Progress" entram no denominador do "total handled"? → A: Sim — "handled" = todas as oportunidades criadas no período pelo Scout, incluindo In Progress; rates = outcomes ÷ total criadas.
- Q: O que "standard connection" em SC-002 significa concretamente? → A: Localhost/LAN, dataset ≤ ~10k opportunities por conta (dataset de produção do fork).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — View Scout Performance Summary Metrics (Priority: P1)

As an operator or commercial manager, when I open Scout → Overview, I want to immediately see how many opportunities the Scout handled in the selected period and how they split across qualified, disqualified, and abandoned outcomes, so I can evaluate agent performance without scanning the Kanban opportunity by opportunity.

**Why this priority**: This is the central value of the phase — without the summary cards there is no "overview" at all. The distribution charts and interest breakdown are deeper cuts into the same numbers, not the entry point.

**Independent Test**: Can be tested in isolation by populating opportunities handled by a test Scout with all three outcomes (qualified / disqualified / abandoned) and verifying that the cards show correct counts and rates for the selected period, including the messages-per-conversation card.

**Acceptance Scenarios**:

1. **Given** a Scout with handled opportunities in the selected period covering all three outcome types, **When** the operator opens Scout → Overview, **Then** five summary cards appear: total handled, qualification rate, disqualification rate, abandonment rate, and average messages-per-conversation — all calculated for the selected period.
2. **Given** the operator changes the period selector (7 days / 30 days / this month / last month), **When** the selection changes, **Then** all summary cards recalculate for the new window without a full page reload.
3. **Given** an account with more than one Scout, **When** the operator switches the Scout selector, **Then** all cards reflect only the selected Scout's data, with no mixing of data from another agent.
4. **Given** a Scout that has no `qualified_stage_id`, `unqualified_stage_id`, or `rescue_stage_id` configured (incomplete setup), **When** the operator opens the Overview, **Then** the corresponding outcome cards display a neutral state ("—") with no error and no division-by-zero failure.
5. **Given** a Scout with no handled opportunities in the selected period, **When** the operator views the Overview, **Then** the cards show zero counts and an empty-state layout replaces the charts — no blank page or error.

---

### User Story 2 — See Where Handled Opportunities Stand in the Full Pipeline (Priority: P2)

As an operator, I want to see a chart showing which pipeline stage every opportunity the Scout has ever handled is in **right now** (across the full account pipeline, not just the Scout's own stages), so I can understand how far leads progress beyond initial qualification into the human team's hands.

**Why this priority**: Deepens the P1 summary with per-stage granularity; shares the same aggregation endpoint but answers a second question operators ask after viewing the totals — it does not block the core value.

**Independent Test**: Can be tested in isolation by creating opportunities handled by the Scout at varying pipeline stages (including stages beyond Scout's own, such as a human-managed "Negotiation" stage) and verifying that the chart reflects the correct per-stage count as a current snapshot — independent of the period selector.

**Acceptance Scenarios**:

1. **Given** opportunities handled by the Scout distributed across multiple pipeline stages (including stages managed by humans after qualification), **When** the operator views the distribution chart, **Then** each stage shows the correct count of Scout-handled opportunities currently there.
2. **Given** the operator changes the period selector, **When** the selection changes, **Then** the pipeline-stage distribution chart remains unchanged — it is a current snapshot, not filtered by period.

---

### User Story 3 — See Interest Distribution Across Pipeline Stages (Priority: P3)

As an operator with the interest field configured on the Scout, I want to see how different interests (e.g. products or services) are distributed across pipeline stages, so I can identify which interests advance furthest and which stagnate.

**Why this priority**: The most specific and optional metric — only meaningful when the interest field is configured, and even then it is a refinement over User Story 2, not an MVP blocker.

**Independent Test**: Can be tested in isolation by configuring `interest_attribute_definition` on a test Scout, assigning different interest values to opportunities in different stages, and verifying the distribution in the chart; and separately testing a Scout without the field configured to confirm the call-to-action state appears.

**Acceptance Scenarios**:

1. **Given** a Scout with `interest_attribute_definition` configured and handled opportunities with different interest values spread across pipeline stages, **When** the operator views the interest-by-stage card, **Then** each stage shows the breakdown by interest value.
2. **Given** a Scout **without** `interest_attribute_definition` configured, **When** the operator views the Overview, **Then** the interest card remains visible with an explanatory message and a button that navigates to the interest field configuration in the Scout's Funnel tab (`scout_funnel` route) — the card does not disappear.

---

### Edge Cases

- Account with a single Scout: Scout selector does not appear (avoids a dropdown with one useless option).
- Account or Scout with no handled opportunities in the period: empty state reuses the `EmptyStateLayout` component already used in other Scout screens — not a blank page.
- Opportunity handled by the Scout whose `origin_conversation` inbox was later unlinked from the Scout (`ScoutInbox` removed): continues counting normally — attribution is fixed at opportunity-creation time, not recalculated retroactively.
- Scout with `enabled: false` but historical opportunity data: the Overview remains accessible and shows historical data — disabling is not the same as archiving or deleting.
- All three outcome stages configured to the same `PipelineStage` (misconfiguration): stages are counted independently by their configured role; no crash or duplicated counting.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a dedicated Scout Overview page accessible as the first child of the Scout navigation section in the sidebar, consistent with the Captain Overview placement pattern.
- **FR-002**: The page MUST display a Scout selector at the top **only when the account has more than one Scout**; with a single Scout the selector is hidden and that Scout's data is shown by default.
- **FR-003**: The page MUST display a period selector with at least four options: last 7 days, last 30 days, current month, previous month.
- **FR-004**: The system MUST display five summary metric cards: total opportunities handled by the Scout in the period, qualification rate, disqualification rate, abandonment rate, and average messages-per-conversation (counting both lead and Scout messages in each conversation).
- **FR-005**: Qualification rate, disqualification rate, and abandonment rate MUST each be computed as: count of opportunities that reached the respective outcome stage ÷ total handled opportunities in the period. "Total handled" includes all opportunities created in the period by the Scout — including those still In Progress — so that rates reflect the full scope of the Scout's work, not only resolved cases.
- **FR-006**: When a Scout has no outcome stage configured (`qualified_stage_id`, `unqualified_stage_id`, or `rescue_stage_id` is null), the corresponding rate card MUST show a neutral placeholder ("—") without producing an error or a division-by-zero failure.
- **FR-007**: Changing the period selector or Scout selector MUST update all summary metric cards without a full page reload.
- **FR-008**: The system MUST display a pipeline-stage distribution chart showing, for each stage in the account's full pipeline, the count of opportunities handled by the selected Scout that are currently in that stage — as a current snapshot unaffected by the period selector.
- **FR-009**: The system MUST display an interest-by-stage breakdown card showing how opportunities' interest values are distributed across pipeline stages.
- **FR-010**: When the selected Scout has no `interest_attribute_definition` configured, the interest-by-stage card MUST remain visible in a "not configured" state with a call-to-action button that navigates to the Scout Funnel configuration screen (`scout_funnel` route).
- **FR-011**: An "opportunity handled by the selected Scout" is defined as any `Opportunity` whose `origin_conversation` belongs to an inbox with the selected Scout enabled (`inbox.scout_id == selected scout id`), created within the selected period — regardless of its current outcome state (Qualified, Disqualified, Abandoned, or In Progress). In Progress opportunities are included in the total and in the denominator of all rate cards.
- **FR-012**: The abandonment outcome is defined by the opportunity reaching `rescue_stage_id` (inactivity rescue, from Phase 22) — it is distinct from disqualification and MUST be counted separately.
- **FR-013**: All aggregations MUST be computed on demand at request time — no pre-aggregation tables, background jobs, or caches are required by this feature.
- **FR-014**: When no opportunities match the current Scout + period combination, the page MUST show an empty-state layout consistent with other Scout screens rather than a blank or error state.
- **FR-015**: Access to the Scout Overview page and its aggregation API endpoint MUST follow the same authorization model as the Captain Overview — any authenticated account member (agent or administrator) within the account may access it; no additional role gate is introduced.

### Key Entities

- **Scout**: The AI agent scoped to one or more inboxes; has configurable `qualified_stage_id`, `unqualified_stage_id`, `rescue_stage_id`, and optional `interest_attribute_definition`.
- **Opportunity**: A sales opportunity with an `origin_conversation` that determines which Scout handled it; carries a current `pipeline_stage` and optional interest attribute value.
- **PipelineStage**: An ordered stage in the account's full pipeline; may or may not be one of the Scout's own outcome stages.
- **Period**: A time window (7 days / 30 days / current month / previous month) used to filter which opportunities are counted as "handled" in the summary cards.
- **Outcome**: One of four states for a Scout-handled opportunity — Qualified (reached `qualified_stage`), Disqualified (reached `unqualified_stage`), Abandoned (reached `rescue_stage`), or In Progress (none of the above, conversation still pending).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can determine how many opportunities the Scout handled, qualified, disqualified, and abandoned in a chosen period in under 30 seconds, without opening the Kanban.
- **SC-002**: Switching the period selector or Scout selector updates all metric cards within 2 seconds, measured on a localhost or LAN connection against a dataset of up to ~10 000 opportunities per account (representative of this fork's production volume), without a full page reload.
- **SC-003**: The pipeline-stage distribution chart accurately reflects the current funnel state for all Scout-handled opportunities, including stages managed by the human team after qualification.
- **SC-004**: The interest-by-stage card never disappears or produces an error when the Scout has no interest field configured — it always guides the operator to configure the field.
- **SC-005**: Switching Scout or period never mixes data from different scopes in any metric card.
- **SC-006**: The Overview page renders a useful empty state (not a blank or crashed page) when no opportunities match the selected Scout + period combination.

## Assumptions

- `qualified_stage_id`, `unqualified_stage_id`, and `rescue_stage_id` are already persisted on the Scout model (from Phase 09 and Phase 22 respectively); this feature reads them but does not manage them.
- The `interest_attribute_definition` field on the Scout is already persisted (from Phase 26); this feature reads it but does not manage it.
- `Opportunity.origin_conversation` and the inbox-to-Scout linkage (`ScoutInbox`) are already part of the data model; attributing an opportunity to a Scout is purely a read of that existing association.
- All aggregations run acceptably fast on demand at the data volumes expected in this fork's production environment; background pre-aggregation is explicitly out of scope and may be revisited as a future optimization without changing the API or UI contract.
- The period selector reuses the `RangeSelector` component already used by the Captain Overview — no new date-range component is introduced.
- Existing pipeline stages are not modified or reordered by this feature; the distribution chart reads them as-is from the account's current configuration.
- The messages-per-conversation count includes all messages in the `origin_conversation` (lead and Scout), not just Scout-generated responses, consistent with measuring real conversation size rather than model output volume.
- A Scout disabled at the inbox level (`enabled: false`) still has historical data that must remain queryable; disabling does not archive or delete opportunities.
- The Scout Overview route is the first item in the Scout submenu, consistent with the Captain Overview placement.
- Both English (`en.json`) and Portuguese (`pt_BR.json`) translations are delivered synchronously with the feature, as required by this fork's translation policy.
- The Scout Overview authorization model mirrors the Captain Overview: any authenticated account member can view any Scout's Overview within their account, consistent with how Captain Overview exposes Captain-level data to all agents.
