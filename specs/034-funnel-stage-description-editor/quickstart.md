# Quickstart: Validate Funnel Stage Rich Description & Kanban Info Panel

**Feature**: `034-funnel-stage-description-editor`

## Prerequisites

- Stack running (`docker compose up -d`); see project `CLAUDE.md` for the full container workflow.
- An account with the `opportunities`/kanban feature enabled and at least one funnel stage.
- Logged in as an account admin/agent with access to the pipeline stage settings screen and the
  opportunities kanban board.

## 1. Confirm the persistence fix (User Story 1)

1. Apply the new migration: `docker compose exec rails bundle exec rails db:migrate`.
2. Open **Settings → Pipeline Stages** (`pipelineStages` routes), edit any stage.
3. Type a description, e.g. "Deals move here once budget is confirmed.", and save.
4. Reopen the edit form for that same stage.
5. **Expected**: the description text you typed is present, unchanged.
6. Clear the field entirely and save; reopen the form again.
7. **Expected**: the field is now empty (confirms clearing persists too, FR-003).

See [contracts/pipeline_stages_api.md](contracts/pipeline_stages_api.md) for the exact request/
response shape this relies on.

## 2. Confirm rich-text formatting (User Story 2)

1. Open the stage edit form again.
2. In the description field, type a short sentence and apply, in turn: bold, italic,
   strikethrough, underline to different words/phrases, plus one ordered list and one bulleted
   list.
3. Save, then reopen the edit form.
4. **Expected**: all applied formatting is visually restored (not shown as raw markup/tags), per
   FR-004/FR-005/SC-002.

## 3. Confirm the kanban info panel (User Story 3)

1. Navigate to the opportunities kanban board.
2. For the stage you added a description to, locate the circular info icon to the left of the
   column title.
3. Click it.
4. **Expected**: a panel expands directly below the column header, pushing the cards in that
   column down; the panel shows the description with formatting rendered (bold text actually
   bold, lists actually rendered as lists), not raw HTML tags.
5. Click the icon again.
6. **Expected**: the panel collapses and cards return to their original position.
7. Repeat on a different column that has no description saved.
8. **Expected**: the icon is still visible/clickable; clicking it shows a friendly empty-state
   message pointing the user to the funnel stage settings to add one (no link/navigation away from
   the board), per the resolved Clarifications in [spec.md](spec.md).
9. Expand two different columns' panels at once.
10. **Expected**: both stay independently expanded/collapsed (FR-009).

## Data model / contract references

- [data-model.md](data-model.md) — the new `description` column and its validation rules.
- [contracts/pipeline_stages_api.md](contracts/pipeline_stages_api.md) — request/response shape.
- [research.md](research.md) — why a dedicated editor and HTML+`v-dompurify-html` were chosen.
