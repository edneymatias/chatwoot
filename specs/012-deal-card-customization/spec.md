# Feature Specification: Deal Card Customization

**Feature Branch**: `012-deal-card-customization`

**Created**: 2026-08-03

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 3/06-deal-card-customization/spec14.md" — Kanban deal cards today show a fixed set of info (contact, assignee, status badge, creation date, unmet-requirements state). Admins should be able to configure up to 3 additional fields (from existing deal custom attributes, plus deal value) to display as colored badges on every card, account-wide.

**Amendment (2026-08-03)**: Admins also need to set the account's currency for monetary values.
This setting is surfaced in the same "Card Fields" tab (for lack of a more general "pipeline
settings" home today), but it is account-wide infrastructure, not a card-only setting: it is
intended to govern every monetary value shown anywhere in the pipeline (cards, future pipeline
totals, future reports, etc.). Within this phase's scope, only the card badge for a currency-type
value (the "Deal Value" field, or a currency-type custom attribute) actually consumes it — other
surfaces don't exist yet and will adopt the same setting when they're built.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin configures which fields appear on cards (Priority: P1)

An account admin wants the kanban board to surface a few key deal details at a glance without opening each card, so they go to the pipeline settings and choose up to 3 fields (from the account's existing deal custom fields, or the deal's value) to show as colored badges on every card.

**Why this priority**: This is the entire feature — without the ability to configure fields, there is nothing to display. It delivers value the moment an admin can pick and save fields.

**Independent Test**: Can be fully tested by opening the pipeline settings, selecting fields with colors, saving, and confirming the selections persist on reload.

**Acceptance Scenarios**:

1. **Given** an account with no configured card fields, **When** the admin opens the "Card Fields" settings tab, **Then** they see a list of eligible deal fields (existing custom fields plus "Deal Value") with checkboxes, none selected.
2. **Given** the admin checks a field, **When** the checkbox is checked, **Then** a color picker appears for that field so the admin can assign a badge color.
3. **Given** the admin has selected 3 fields, **When** they try to check a 4th, **Then** the option is disabled and a "3/3 selected" hint is shown.
4. **Given** the admin has selected fields and colors, **When** they save, **Then** the selections and colors persist and are shown pre-filled the next time the settings page is opened.
5. **Given** the admin unchecks a previously-selected field and saves, **When** the change is saved, **Then** that field's badge no longer appears on any card.
6. **Given** the admin opens the "Card Fields" tab, **When** they look for a currency setting, **Then** they find a separate currency selector (not one of the 3 badge-field slots) showing the account's current currency, defaulting to a standard currency if never set.
7. **Given** the admin changes the currency selector and saves, **When** the change is saved, **Then** the new currency is used the next time a monetary badge value is displayed.

---

### User Story 2 - Team members see configured fields on cards (Priority: P1)

A team member browsing the kanban board wants to see the admin-configured deal details directly on each card, without opening it, so they can scan the board faster.

**Why this priority**: This is the payoff of User Story 1 — configuration is worthless if it isn't reflected on the board. Both stories are needed for a usable MVP, but this one is what users see day to day.

**Independent Test**: Can be fully tested by configuring fields as an admin (User Story 1), then viewing the board as any user and confirming the badges render correctly for deals with and without values.

**Acceptance Scenarios**:

1. **Given** an account has 1-3 configured card fields, **When** a user views the kanban board, **Then** each deal card shows a colored badge for each configured field that has a value on that deal, in the order the fields were configured.
2. **Given** a configured field has no value for a particular deal, **When** that card is rendered, **Then** no badge is shown for that field on that card (no empty placeholder).
3. **Given** every configured field is empty for a particular deal, **When** that card is rendered, **Then** the entire badge row is omitted for that card (no empty gap).
4. **Given** an account has no configured card fields, **When** a user views the kanban board, **Then** cards render exactly as they did before this feature (no new row, no visual change).
5. **Given** a configured field is a date, currency, or list-type custom attribute, **When** its badge is rendered, **Then** the value is formatted appropriately for its type (e.g., currency shown as currency, dates shown as dates).
6. **Given** the account has a configured currency, **When** a card shows a badge for the "Deal Value" field or a currency-type custom attribute, **Then** the value is formatted using that configured currency, not a hardcoded one.

---

### Edge Cases

- What happens when an admin removes/deletes a custom field that is currently used as a configured card field? The corresponding badge configuration is removed along with it, and the badge stops appearing on all cards.
- What happens if two admins edit the "Card Fields" settings concurrently? Last save wins, consistent with how other pipeline settings (e.g., closing requirements) behave today.
- What happens when a configured field's value is a very long string? Out of scope to define new truncation behavior beyond what the badge display style already handles.
- What happens if the account has never set a currency? Monetary badges use a default currency of USD until the admin explicitly changes it.
- What happens to previously-displayed monetary badges when the admin changes the currency? They immediately reformat under the new currency on next render — the deal's underlying numeric value is not converted or altered, only its display formatting changes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Admins MUST be able to select up to 3 fields, from the account's existing deal custom fields plus a fixed "Deal Value" option, to display on kanban cards.
- **FR-002**: The system MUST prevent selecting more than 3 fields, both while the admin is actively selecting (immediate feedback) and if bypassed, when the selection is saved.
- **FR-003**: Admins MUST be able to assign a free-choice color to each selected field, used to render that field's badge.
- **FR-004**: Admins MUST be able to change the color of an already-selected field and remove a previously-selected field, with changes reflected on the board immediately after saving.
- **FR-005**: The system MUST prevent selecting the "Deal Value" option more than once per account.
- **FR-006**: The system MUST prevent selecting the same custom field more than once per account.
- **FR-007**: Configuration selections MUST persist across sessions and be shared account-wide (all admins and users see the same configured fields on the board).
- **FR-008**: Every kanban card MUST display a badge for each configured field that has a non-blank value for that specific deal, ordered by the sequence in which the fields were configured.
- **FR-009**: A configured field with no value on a given deal MUST NOT render a badge (no empty/placeholder badge) for that deal.
- **FR-010**: When no fields are configured for an account, cards MUST render with no change from their current appearance (no new row).
- **FR-011**: Each field's value MUST be formatted according to its underlying type (e.g., currency, date, list, plain text/number) when shown as a badge.
- **FR-012**: Deleting a custom field that is used as a configured card field MUST remove that configuration and its badge from all cards.
- **FR-013**: The card's existing fixed information (contact, assignee, status badge, creation date, unmet-requirements state) MUST remain unchanged and is not part of this configurable set.
- **FR-014**: Admins MUST be able to set the account's currency for monetary values from a small fixed list of supported currencies, as a separate setting from the 3 badge-field selections (it does not count against the 3-field cap).
- **FR-015**: The account's configured currency MUST be used whenever a monetary value (the "Deal Value" field, or a currency-type custom attribute) is formatted for display as a card badge.
- **FR-016**: If an account has never explicitly set a currency, monetary badges MUST format using USD as the default currency rather than failing or showing an unformatted number.
- **FR-017**: The currency setting MUST persist across sessions and be shared account-wide, independent from and unaffected by changes to the 3 selected badge fields.

### Key Entities

- **Card Field Configuration**: Represents one admin-chosen field to display on cards for an account — which field (an existing custom field, or the fixed "Deal Value"), its assigned badge color, and its display order relative to other configured fields. An account has at most 3 of these.
- **Currency Setting**: Represents the account's chosen currency for monetary values. A single value per account, independent of the Card Field Configuration list. Consumed by this phase's card badges only; intended as the shared source of truth for any future pipeline surface (totals, reports) that displays monetary values.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An admin can configure or change the set of card badge fields and see the change reflected on the kanban board in under 1 minute, without a page reload beyond a normal save action.
- **SC-002**: 100% of deal cards on a board with configured fields show the correct badges for their own field values, with no badge shown for missing values.
- **SC-003**: Accounts that have not configured any card fields see zero visual change to their kanban cards.
- **SC-004**: Removing a configured field or its underlying custom field consistently removes its badge from all cards within one board refresh, with no orphaned badges.
- **SC-005**: 100% of monetary badges on a board reflect the account's currently configured currency, with no manual per-card correction needed after an admin changes it.

## Assumptions

- This configuration applies account-wide today (there is no multi-pipeline concept yet in this system); if multiple pipelines are introduced later, this configuration's scope may need to be revisited.
- Eligible fields are the same pool of deal custom fields already used elsewhere in deal configuration (e.g., required fields for stage transitions), plus the deal's built-in value field — no additional flagging step is needed to make a field eligible.
- Badge colors are freely chosen by the admin (not a fixed palette), consistent with how label colors already work elsewhere in the product.
- Badges show only the field's value, not the field's name, to keep cards compact.
- There is no manual reordering of the 3 configured fields; order follows the sequence in which fields were configured.
- The supported currency list is small and fixed (matching the currencies this fork's billing feature already supports, e.g. USD and BRL) — adding more currencies is out of scope unless requested.
- Placing the currency setting in the "Card Fields" tab is a pragmatic UI choice for this phase, since there is no dedicated general "pipeline settings" surface yet; it is understood to be broader-than-card-scoped infrastructure, not a card-specific setting, even though its current home may suggest otherwise.
- Building the pipeline-totals header or reports currency display is out of scope for this phase — this phase only introduces the shared currency setting and wires it into the card badge.
