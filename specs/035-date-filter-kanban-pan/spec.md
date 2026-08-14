# Feature Specification: Custom Date Attribute Filtering & Kanban Drag-to-Pan Navigation

**Feature Branch**: `035-date-filter-kanban-pan`

**Created**: 2026-08-14

**Status**: Draft

**Input**: User description: "quero ajustar uma situação e melhorar outra. no quadro kanban há um botão de filtro que permite combinar vários filtro para listar oportundiades, tanto no quadro, quanto na visão de lista. os filtros são criados a partir dos atributos personalizados. um dos filtros que tenho no momento é o campo data de agendamento que é do tipo data. eu tenho no meu quadro agora, duas oportunidades com data de agendamento 13/08. e se eu filtro exatamente por data de agendamento = 13/08/2026, funciona. apenas os dois cards são exibidos. porém, quando filtro por cards com data de atendimento > que 01/08/2026, esses dois cards não são exibidos. já a melhoria que quero introduzir é o arrasto horizontal do kanban com o mouse ou com o dedo se for em mobile. atualmente, ha uma barra de rolagem horiztonal na parte inferior e o usuario deve clicar nessa barra para navegar lateralmente pelo kanban. eu quero que isso seja feito a partir do clique e araste. para isso, o usúario deve clicar em qualquer área da tela que nao tenha um card ou isso provocaria a mudança de lane do card (isso já funciona)."

## Clarifications

### Session 2026-08-14

- Q: Como deve se comportar a navegação horizontal por clique e arraste no Kanban ao soltar o mouse após um movimento rápido? → A: Parada direta e imediata ao soltar o botão do mouse (controle exato e previsível sem inércia artificial).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Filter Opportunities by Custom Date Attribute Comparisons (Priority: P1)

Users filter opportunities across the Kanban board and the List view using custom date-type attributes with comparative operators (greater than `>`, greater than or equal `>=`, less than `<`, less than or equal `<=`). The system correctly evaluates the date values stored on opportunities against the selected reference date and accurately returns matching opportunities in both views.

**Why this priority**: Accurate data filtering is essential for daily sales operations and opportunity tracking. When date comparison filters fail, users miss upcoming or past scheduled opportunities.

**Independent Test**: Create opportunities with varying custom attribute date values (e.g., 2026-08-13), apply a filter query with "Date Attribute > 2026-08-01", and verify that all matching opportunities are visible in both the Kanban board and List view.

**Acceptance Scenarios**:

1. **Given** multiple opportunities with custom date attribute values (e.g., 2026-08-13), **When** the user applies a filter for "Date > 2026-08-01", **Then** the opportunities with dates after 2026-08-01 are displayed in both Kanban and List views.
2. **Given** opportunities with custom date attribute values, **When** the user applies a filter for "Date < 2026-08-15" or "Date <= 2026-08-13", **Then** only opportunities with matching dates are displayed.
3. **Given** opportunities with null or missing custom date values, **When** a date comparison filter (e.g., `>`) is applied, **Then** opportunities without dates are excluded from the positive match results.
4. **Given** an active date comparison filter combined with other filters (e.g., Pipeline, Stage, Assignee), **When** the query is evaluated, **Then** all combined filter conditions are respected simultaneously.

---

### User Story 2 - Desktop Click-and-Drag Pan Navigation on Kanban Board (Priority: P2)

On desktop browsers, users can click and hold the primary mouse button on any non-interactive surface or empty space of the Kanban board (such as the board backdrop, lane header, or lane background area not occupied by an opportunity card) and drag horizontally to smoothly pan/scroll the board left and right.

**Why this priority**: Improves usability and navigation speed when working with pipelines that have many stages/columns, removing the necessity to locate and manually drag the bottom horizontal scrollbar.

**Independent Test**: Open a Kanban board with more columns than fit the current viewport, click on an empty area of the board background or lane container, drag left and right, and verify that the board smoothly scrolls horizontally while opportunity cards remain stationary inside their respective lanes.

**Acceptance Scenarios**:

1. **Given** a Kanban board exceeding the horizontal viewport width, **When** the user clicks and drags on an empty background or empty lane area, **Then** the board scrolls horizontally in sync with the mouse movement.
2. **Given** a user clicking on an opportunity card to drag it to another stage, **When** dragging the card, **Then** the card drag-and-drop interaction is triggered and board-level panning is suppressed.
3. **Given** a user clicking an interactive element (e.g., button, link, menu trigger, search input), **When** clicking or releasing without dragging, **Then** the native click action executes normally without triggering a scroll jump.
4. **Given** a drag-to-pan in progress, **When** the user releases the mouse button, **Then** panning stops immediately and the scroll position is maintained without abrupt snapping.

---

### User Story 3 - Mobile / Touch Drag-to-Pan Navigation (Priority: P3)

On touch-enabled mobile devices and tablets, users can swipe or touch-and-drag horizontally on any non-card area of the board to pan smoothly across the Kanban lanes.

**Why this priority**: Provides a natural, mobile-native touch navigation experience across wide pipeline boards.

**Independent Test**: Access the Kanban board on a mobile device or touch viewport emulator, touch any empty area between or within lanes, and swipe horizontally to inspect all pipeline stages.

**Acceptance Scenarios**:

1. **Given** a touch device viewing the Kanban board, **When** the user swipes horizontally on non-card areas, **Then** the viewport pans smoothly through the pipeline lanes.
2. **Given** a user initiating a long-press or direct touch-drag on an opportunity card, **When** dragging the card, **Then** lane transition handles the card movement without interfering with the horizontal pan.

---

### Edge Cases

- **Date format and timezones**: Date comparisons must evaluate calendar dates consistently regardless of time-of-day offsets or stored ISO string formatting.
- **Empty / Null date fields**: Opportunities where the custom date attribute is unset or empty must not throw errors during comparison and must be excluded from `>`, `>=`, `<`, `<=` matches.
- **Click vs Drag threshold**: Mouse down followed by mouse up within a minimal movement threshold (e.g., < 3-5 pixels) must be treated as a click, ensuring underlying click handlers (opening drawers, modals, buttons) are not blocked.
- **Dragging beyond viewport limits**: Panning beyond the leftmost (start) or rightmost (end) boundary must smoothly stop at scroll limits without breaking cursor state or jumping.
- **Combined multi-filter criteria**: Combining multiple custom attribute filters (e.g., date `>` X and date `<` Y with text attribute = Z) must return the logical intersection without filter conflict.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide appropriate date operators for custom date attributes:
  - Equal to (`=`)
  - Not equal to (`!=`)
  - Greater than (`>`)
  - Less than (`<`)
  - Present / Not present (if enabled for custom attributes)
  - Days before (`days_before` / "É X dias antes", if applicable)
- **FR-002**: Filter query execution in the backend MUST parse and evaluate date custom attributes with proper date/timestamp comparison semantics (`(custom_attributes->>:key)::date <operator> :value::date`) rather than string-only equality.
- **FR-003**: The Opportunity filter engine MUST evaluate date comparison filters accurately across both Kanban board view and Opportunities List view.
- **FR-004**: System MUST handle invalid or missing date formats gracefully without throwing database casting errors when non-date or malformed values exist.
- **FR-005**: System MUST allow users to navigate horizontally across Kanban lanes by clicking and dragging with the mouse on non-card background areas.
- **FR-006**: Board drag-to-pan MUST NOT intercept or disrupt card drag-and-drop operations when the user initiates a drag on an opportunity card.
- **FR-007**: Board drag-to-pan MUST NOT prevent click events on interactive UI controls (buttons, links, action menus, input fields) when a drag threshold is not exceeded.
- **FR-008**: System MUST support touch-based horizontal panning across the Kanban board on mobile and tablet touch devices.
- **FR-009**: While drag-to-pan is active, the cursor MUST visually reflect the grabbing state on desktop viewports.
- **FR-010**: The native horizontal scrollbar on the Kanban board container MUST be visually hidden across browsers while preserving full horizontal overflow scrollability.

### Key Entities

- **Opportunity**: Represents a deal or lead within a pipeline stage, containing standard attributes and custom attributes (including date-type attributes).
- **Custom Attribute Definition**: Metadata defining the attribute key, display label, and data type (e.g., `date`, `text`, `number`, `list`).
- **Opportunity Filter Query**: Set of criteria combining attribute keys, comparison operators (`equal_to`, `not_equal_to`, `greater_than`, `less_than`, `greater_than_or_equal_to`, `less_than_or_equal_to`), and reference values.
- **Kanban Board Container**: Viewport element managing horizontal layout, lane columns, and interactive panning gestures.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of date comparison queries (e.g., `date > reference_date`, `date < reference_date`) return all matching opportunities in both Kanban and List views.
- **SC-002**: Users can pan across the full width of a multi-lane Kanban board on desktop using click-and-drag in under 1 second without using a scrollbar.
- **SC-003**: The bottom horizontal scrollbar is completely hidden (0px visual footprint) on the Kanban board viewport across supported browsers.
- **SC-004**: Card drag-and-drop success rate and lane transition behavior remain unaffected (0% regression on card reordering or stage moving).
- **SC-005**: False positive drag detection rate is 0% for standard clicks on buttons, cards, and interactive controls.

## Assumptions

- Standard custom date attributes store date values in valid ISO-8601 / date-formatted strings (e.g., `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SSZ`).
- Existing card drag-and-drop functionality uses specific draggable card handles or card container selectors that can be isolated from board pan event listeners.
- Both English (`en`) and Portuguese (`pt-BR`) language support are maintained for any added or modified filter UI strings.
