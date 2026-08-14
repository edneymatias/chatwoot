# Quickstart Validation Guide: Custom Date Attribute Filtering & Kanban Drag-to-Pan Navigation

## Overview
This guide provides step-by-step procedures to validate custom date attribute filtering and Kanban drag-to-pan navigation locally.

## Prerequisites
- Local development stack running (`docker compose up -d`).
- At least one active Account with Pipeline stages and custom attribute of type `date` (e.g., `data_agendamento`).

## Validation Scenarios

### Scenario 1: Automated Specs (Backend & Frontend)

1. Run Ruby controller and filter specs:
   ```bash
   docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec spec/controllers/api/v1/accounts/opportunities_controller_spec.rb
   ```

2. Run Vue/JS unit tests:
   ```bash
   docker compose exec vite pnpm test app/javascript/dashboard/components-next/Opportunities/specs/KanbanBoard.spec.js
   docker compose exec vite pnpm test app/javascript/dashboard/components-next/filter/specs/operators.spec.js
   ```

### Scenario 2: Manual Verification in Browser

1. **Date Attribute Comparison Filters**:
   - Open the Opportunities Kanban board or List view.
   - Click "Filtrar oportunidades" (Filter button).
   - Select a date custom attribute (e.g. `data_agendamento`).
   - Verify the operator dropdown shows: `=`, `!=`, `>`, `<`, `É X dias antes`, `Está presente`, `Não está presente`.
   - Apply filter: `data_agendamento > 01/08/2026`.
   - Verify opportunities with dates like `13/08/2026` are correctly returned and visible.
   - Apply filter: `data_agendamento < 10/08/2026`.
   - Verify opportunities with `13/08/2026` are excluded.

2. **Kanban Drag-to-Pan Navigation**:
   - On desktop, view a pipeline with enough stages to exceed viewport width.
   - Verify the bottom horizontal scrollbar is hidden.
   - Click and hold with mouse on empty board area or lane header and drag left/right.
   - Verify smooth horizontal scrolling following mouse movement.
   - Release mouse: verify board stops scrolling immediately at current position.
   - Click and drag a card: verify card moves between stages without triggering board pan.
   - Test on mobile/touch screen or responsive emulator: swipe horizontally across lanes.
