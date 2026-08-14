# Implementation Plan: Funnel Stage Rich Description & Kanban Info Panel

**Branch**: `034-funnel-stage-description-editor` | **Date**: 2026-08-14 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/034-funnel-stage-description-editor/spec.md`

## Summary

The pipeline stage `description` field is already wired through the edit form and the
controller's strong params, but the underlying database column was never created — so every save
silently fails to persist. The fix is a single additive migration adding a `text description`
column to `ichatr_pipeline_stages`. On top of that fix, the stage edit form gets a small,
dedicated rich-text input (bold/italic/strike/underline/ordered+bulleted lists) built with Tiptap
rather than reusing Chatwoot's shared conversation/article prosemirror editors (which lack an
underline mark and carry irrelevant composer/article chrome). The kanban board's `KanbanColumn.vue`
gains a per-column, independently toggleable info panel that renders the sanitized description
using the app's existing `v-dompurify-html` convention.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.1), JavaScript/Vue 3.5 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails (ActiveRecord, existing `PipelineStage` model/controller), Vuex
(`pipelineStages` store module), new: `@tiptap/vue-3`, `@tiptap/starter-kit`,
`@tiptap/extension-underline` (frontend-only); existing `vue-dompurify-html` for render-time
sanitization

**Storage**: PostgreSQL — new nullable `text` column `description` on `ichatr_pipeline_stages`

**Testing**: RSpec (`bundle exec rspec`) for the model/request specs; `pnpm test` (Vitest) for any
new Vue component specs, following existing conventions in `spec/models/pipeline_stage_spec.rb`,
`spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb`

**Target Platform**: Existing Chatwoot dashboard (web), account-scoped settings + kanban board

**Project Type**: Web application (Rails backend + Vue frontend, single repo)

**Performance Goals**: N/A beyond existing settings/board interaction responsiveness — no new
performance-sensitive path (single small text field, client-side toggle)

**Constraints**: Must not modify the shared, externally-published `@chatwoot/prosemirror-schema`
package or the conversation composer (`WootWriter/Editor.vue`)/article editor
(`WootWriter/FullEditor.vue`); must stay within the fork's `custom/` backend tree and existing
`pipelineStages` frontend module without altering upstream file shapes (Constitution Principle I)

**Scale/Scope**: One new DB column, one new frontend dependency (Tiptap + 2 extensions), edits to
2 existing Vue components (`EditPipelineStage.vue`, `KanbanColumn.vue`), no new backend
endpoints/controllers

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. The migration lives under `db/migrate/` (the
  explicitly allowed shared-location exception) and is purely additive to a fork-owned,
  `ichatr_`-prefixed table. The new rich-text editor is intentionally isolated from the shared
  `@chatwoot/prosemirror-schema` package and from `WootWriter/Editor.vue`/`FullEditor.vue` — see
  [research.md](./research.md) R3 — so it cannot conflict with upstream changes to the message
  composer or article editor. The controller and backend model already live in `custom/`.
- **II. Smallest Production-Ready Change**: PASS. The persistence fix is the minimal one-line
  migration; no controller/store changes are needed since both already pass `description` through
  correctly. The new editor is scoped to exactly the six marks/nodes requested — no speculative
  toolbar options.
- **III. Adhere to Established Conventions**: PASS. Rendering uses the existing
  `v-dompurify-html` directive convention already used for other rich/user-authored content
  (company notes, contact notes, campaign cards). RuboCop/ESLint/Tailwind-only/Composition API
  conventions apply to all new code as usual.
- **IV. Safe, Reversible Change Management**: PASS. The migration is additive and reversible
  (`remove_column` in a down migration/rollback); no destructive operations involved.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. `PipelineStage`,
  `PipelineStagesController`, and the kanban Vue components live entirely in the fork's `custom/`
  tree / fork-specific frontend module (not core OSS), and this feature has no Enterprise
  counterpart to keep in sync — verified no `enterprise/` files reference `PipelineStage` or the
  kanban board.

No violations to record in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/034-funnel-stage-description-editor/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── pipeline_stages_api.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
└── <timestamp>_add_description_to_ichatr_pipeline_stages.rb   # new, additive migration

custom/app/
├── models/pipeline_stage.rb                                    # unchanged (description works once column exists)
├── controllers/api/v1/accounts/pipeline_stages_controller.rb    # unchanged (already permits :description)

app/javascript/dashboard/
├── routes/dashboard/settings/pipelineStages/
│   └── EditPipelineStage.vue          # replace plain <textarea> with new rich-text input
├── components-next/Opportunities/
│   └── KanbanColumn.vue               # add info icon + expandable description panel
└── components-next/Opportunities/StageDescriptionEditor.vue    # new, isolated Tiptap-based input (name indicative)

spec/
├── models/pipeline_stage_spec.rb                                   # extend: description persists
└── requests/api/v1/accounts/pipeline_stages_controller_spec.rb      # extend: update persists/clears description
```

**Structure Decision**: Existing Rails + Vue single-repo layout is unchanged. Backend changes are
confined to one additive migration under `db/migrate/` (the fork's documented shared-location
exception); no other backend files change. Frontend changes are confined to the existing
`pipelineStages` settings route and the existing `components-next/Opportunities` kanban module,
plus one new, self-contained editor component in that same module — no new top-level directories,
no changes outside the areas the feature actually touches.

## Complexity Tracking

*No Constitution violations — this section intentionally left without entries.*
