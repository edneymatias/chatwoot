# Feature Specification: Kanban Card Action Footer

**Feature Branch**: `032-kanban-card-action-footer`

**Created**: 2026-08-12

**Status**: Draft

**Input**: User description: "quero ajustar os cards de oportunidades no kanban para separa os botões que ações que eventualmente aparecem. hoje eles estao na útlima linha do card, mas gostaria que houve um separador horizontal sutil e dai uma linha de botoes de ações, claro, se houver botões no card. isso cria um espaço no rodapé do card para botões de ações. os botões são alinhados como hoje, da direita para a esquerda."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Action buttons appear in a dedicated footer row (Priority: P1)

As a user viewing the opportunity Kanban board, when an opportunity card has one or more available action buttons (e.g. "start conversation", "reopen", "edit"/"complete fields"), I want those buttons to sit in their own footer area at the bottom of the card, visually separated from the card's content above by a subtle horizontal divider, so the actions read as a distinct control area rather than overlapping the card's body content.

**Why this priority**: This is the core visual change requested — it directly addresses the current layout issue where action buttons float over the last line of card content instead of having dedicated space.

**Independent Test**: Open the Kanban board, hover/focus an opportunity card that has at least one available action button, and verify a thin horizontal divider appears above a footer row containing the button(s), with no visual overlap between the buttons and the card's text content.

**Acceptance Scenarios**:

1. **Given** an open (not-yet-closed) opportunity card with `origin_conversation_id` unset (so the "start conversation" action is available), **When** the card is hovered, **Then** a subtle horizontal divider and a footer row containing the "start conversation" button appear below the card's existing content, and the button is right-aligned within that row.
2. **Given** a closed/lost opportunity card (status other than `open`), **When** the card is hovered, **Then** the divider and footer row appear containing the "reopen" button, right-aligned.
3. **Given** an open opportunity card with unmet required fields, **When** the card is hovered, **Then** the divider and footer row appear containing the "complete fields" button, right-aligned, and if a second action button is also available on the same card, both buttons appear in that same row ordered right-to-left as they are today.

---

### User Story 2 - No footer space is reserved when a card has no actions (Priority: P2)

As a user scanning the Kanban board, I want cards that currently have no available action buttons to keep their existing compact height, so the board doesn't show empty dividers or blank space on cards where no action applies.

**Why this priority**: Prevents a regression where every card grows a footer area even when it serves no purpose, which would add visual noise across the whole board.

**Independent Test**: Find or create an opportunity card for which none of the action conditions apply (e.g. an open card whose conversation already exists and whose required fields are complete), and verify no divider or footer row is rendered, and the card's height matches its current (pre-change) height. This must be verified against the post-US1 implementation (footer row + divider markup in place but conditionally gated off), not merely observed as trivially true before US1 is built.

**Acceptance Scenarios**:

1. **Given** an opportunity card with zero available action buttons, **When** the card is rendered (hovered or not), **Then** no horizontal divider and no footer row are present in the card.

---

### Edge Cases

- What happens when a card has exactly one action button available? The footer row still renders with the divider above it, containing just that single button, right-aligned.
- How does the system handle the transition between hover states? The show/hide (opacity) behavior of the action buttons on hover remains as it is today; only their position and layout (dedicated footer row with divider vs. floating overlay) changes.
- What happens when the card is in a "closed/grayscale" visual state? The divider and footer row still follow the same conditional-rendering rule (present only if an action button applies to that status).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST render action buttons for an opportunity card inside a dedicated footer row at the bottom of the card, instead of as a floating overlay positioned over the card's body content.
- **FR-002**: The system MUST render a subtle horizontal divider between the card's main content and the action footer row, and this divider MUST only be rendered when the footer row itself is rendered. "Subtle" is defined concretely in the Assumptions section below (low-contrast token consistent with existing card border/divider styling).
- **FR-003**: The system MUST NOT render the divider or the footer row when a card has no available action buttons (preserving the card's current compact layout in that case).
- **FR-004**: Within the footer row, action buttons MUST be laid out and ordered the same way they are ordered today (right-to-left / right-aligned).
- **FR-005**: The existing conditions that determine which action buttons appear (start conversation, reopen, complete fields/edit) MUST remain unchanged by this layout change.
- **FR-006**: The existing hover-based visibility behavior of the action buttons MUST be preserved; only their structural placement within the card changes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On 100% of opportunity cards that have at least one available action button, the action button(s) are visually separated from the card's content by a divider and contained within a distinct footer row, with no visual overlap onto the text/content area above.
- **SC-002**: On 100% of opportunity cards that have no available action buttons, no divider or footer row is visible, and card height is unchanged from the current behavior.
- **SC-003**: A user can visually distinguish, without ambiguity, the card's informational content from its action controls on every card that has actions, verified across all existing action-button scenarios (start conversation, reopen, complete fields).

## Assumptions

- "Subtle" horizontal divider means a low-contrast, thin separator line consistent with the existing design system's divider/border tokens (e.g. the same weight/color family already used for card borders), not a bold or emphasized rule.
- This change is a layout/structural change only; no new action buttons, icons, or business logic conditions are introduced or removed.
- Only the `KanbanCard.vue` opportunity card (Kanban board view) is in scope; the `ContactOpportunityCard.vue` card (contact panel) is out of scope unless it shares the same action-footer pattern and the user separately requests it.
- The footer row's presence/absence should be driven by whether any action button would render for that card, following the same per-button conditions already implemented today.
