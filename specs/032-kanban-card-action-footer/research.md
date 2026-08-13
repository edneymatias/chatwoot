# Phase 0 Research: Kanban Card Action Footer

No `NEEDS CLARIFICATION` markers remain in the Technical Context — this feature is a scoped
template/markup change to one existing Vue component, so research is limited to confirming the
concrete implementation approach against existing conventions in the codebase.

## Decision: Divider styling

**Decision**: Use `border-t border-n-slate-3` (a top border on the footer row) as the "subtle
horizontal divider," matching the divider token already used for row separators in the sibling
component `ContactOpportunityCard.vue` (`border-b border-n-slate-3` between list rows).

**Rationale**: Reusing an existing divider token (`n-slate-3`) keeps the change consistent with
established design-system usage elsewhere in the same component family (Principle III —
established conventions), and `n-slate-3` is already a low-contrast/subtle tone appropriate for a
non-emphasized separator.

**Alternatives considered**:
- A dedicated `<hr>`-style element — rejected, adds markup without benefit over a utility border
  class on the existing footer wrapper.
- `border-n-weak` (used for the card's own outer border) — rejected in favor of `n-slate-3` to
  keep the divider visually lighter than the card's outer boundary, per "subtle" in the spec.

## Decision: Conditional rendering of footer + divider

**Decision**: Compute a single boolean (e.g. `hasActions`) in the `<script setup>` block from the
same three conditions that already gate each button
(`!opportunity.origin_conversation_id`, `opportunity.status !== 'open'`,
`opportunity.status === 'open'` for complete-fields/edit), and use it as the `v-if` on the footer
wrapper `<div>` that contains both the divider border and the button row.

**Rationale**: A single derived flag avoids duplicating the three button conditions in two
places (once for the divider, once for the row) and keeps the "no footer when no actions"
requirement (FR-003) enforced in one spot. This is the smallest change that satisfies FR-002/FR-003
without introducing a new component or prop.

**Alternatives considered**:
- Applying `v-if` independently to the divider and to the button row using duplicated conditions
  — rejected, duplicates business logic conditions and risks the two getting out of sync.
- Always rendering the footer wrapper but toggling visibility via CSS (`hidden`) — rejected,
  would still reserve layout space in some cases and contradicts FR-003 ("no footer space when a
  card has no actions").

## Decision: Layout mechanics (flow vs. overlay)

**Decision**: Replace the `absolute bottom-2 right-2` overlay wrapper with a normal-flow `<div>`
placed after the existing content sections, using `flex items-center justify-end gap-1` for
right-to-left button alignment (same alignment behavior as today, achieved via flow order +
`justify-end` instead of absolute positioning).

**Rationale**: Moving to normal document flow is what creates the dedicated footer space
described in the spec (buttons no longer float over the last content row); `justify-end` combined
with the buttons' existing DOM order preserves the current right-to-left visual ordering without
needing to reverse the button markup.

**Alternatives considered**:
- Keeping `absolute` positioning but adding bottom padding to the card to "make room" — rejected,
  the buttons would still visually float over content rather than sit in a clearly separated row,
  which doesn't satisfy the spec's core requirement (FR-001).

## Decision: Hover-triggered visibility

**Decision**: Keep the existing `opacity-0 group-hover:opacity-100 transition-opacity` classes on
the footer wrapper, unchanged.

**Rationale**: FR-006 explicitly requires preserving current hover-based visibility; only the
structural placement changes, not the interaction behavior.

**Alternatives considered**: None — this is a direct carry-over per requirement, not a design
choice needing evaluation.
