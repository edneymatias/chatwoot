# Research: Funnel Stage Rich Description & Kanban Info Panel

**Feature**: `034-funnel-stage-description-editor` | **Date**: 2026-08-14

## R1: Root cause of the persistence bug

**Decision**: The `description` column does not exist on `ichatr_pipeline_stages` at all.

**Evidence**:
- `db/schema.rb` `create_table "ichatr_pipeline_stages"` lists `account_id, name, position,
  created_at, updated_at, requires_deal_value, total_display_mode, accent_color,
  stale_after_days` — no `description`.
- The frontend (`EditPipelineStage.vue`) already reads/writes `stage.description` and the
  backend controller (`custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`)
  already permits `:description` in `pipeline_stage_params`.
- Because there is no column, there is no `description=`/`description` accessor on the
  `PipelineStage` model for Rails to write to or read from — whatever happens at the
  ActiveRecord layer (raised `UnknownAttributeError`, a failed/rolled-back save, or a value that
  is accepted transiently but never actually stored in the database row), the end state is the
  same and matches the reported symptom exactly: the description the user typed is never present
  in the database, so reopening the edit form always shows it empty.

**Alternatives considered**: None — this is a factual gap, not a design choice. The fix is to add
the missing column, matching the exact pattern already used for `accent_color` and
`stale_after_days` (both added in later, additive migrations on the same table).

## R2: Rich-text storage format

**Decision**: Store the description as sanitized HTML in a new `text` column
(`ichatr_pipeline_stages.description`), rendered client-side with the existing
`v-dompurify-html` directive convention.

**Rationale**:
- The product already has an established convention for user-authored rich content rendered as
  HTML with client-side sanitization at render time (`v-dompurify-html`), used for company notes,
  contact notes, campaign cards, etc. (`CompanyNotesSidebar.vue`, `ContactNoteItem.vue`,
  `CampaignCard.vue`). Reusing this convention keeps the new field consistent with the rest of the
  app (Constitution Principle III — Adhere to Established Conventions) instead of introducing a
  second sanitization/rendering strategy (e.g., Markdown) just for this field.
- A rich-text-capable editor library that emits/parses HTML (Tiptap, see R3) is the natural fit
  for this storage format — no server-side Markdown transform is needed.

**Alternatives considered**:
- *Markdown*, matching the conversation composer's `MessageMarkdownTransformer`/`prosemirror-schema`
  pipeline — rejected because that pipeline has no `underline` mark available (see R3) and is
  purpose-built for conversation composition (mentions, canned responses, signatures, typing
  indicators), which is irrelevant/undesirable UI surface for a stage description field.
- *Plain text with a client-only formatting layer (no persistence of marks)* — rejected, does not
  satisfy FR-005 (formatting must persist).

## R3: Editor component choice

**Decision**: Do not reuse `WootWriter/Editor.vue` (message composer) or `WootWriter/FullEditor.vue`
(article editor). Introduce a small, dedicated rich-text input for this field using Tiptap
(`@tiptap/vue-3`, `@tiptap/starter-kit`, `@tiptap/extension-underline`) scoped to the
`pipelineStages` settings screen.

**Rationale**:
- Both existing Chatwoot rich editors are built on the shared, externally-published
  `@chatwoot/prosemirror-schema` npm package. Inspecting that package's mark set (`strong`, `em`,
  `code`, `link`, `strike` across all configured channel/article formatting profiles) confirms it
  has **no `underline` mark**, which the spec explicitly requires (FR-004). Adding one would mean
  patching an external, upstream-maintained package — a large, shared blast radius directly
  contradicting Constitution Principle I (Upstream Compatibility First: prefer additive, isolated
  changes; don't fork shared files) and Principle II (smallest production-ready change).
  Chatwoot's article editor also has an easier way to hit any embed/image-upload feature that
  is undesired scope creep for a short lane-header blurb.
- `WootWriter/Editor.vue` additionally ships conversation-specific chrome (mentions, canned
  responses, variables, signature toggles, Captain/Copilot actions, typing indicators) that is
  irrelevant and confusing for a stage description field, and `FullEditor.vue` ships article
  concerns (image upload, video embeds, slash commands) that are likewise out of scope.
  Configuring either down to just 6 marks/nodes is not realistically supported by their prop
  surface (`enabledMenuOptions` maps to the shared schema's marks, which still lacks underline).
- Tiptap is a well-known, actively maintained, small rich-text toolkit with first-class Vue 3
  bindings, first-class `StarterKit` support for bold/italic/strike/bulletList/orderedList, and a
  standalone `Underline` extension — exactly the six marks/nodes the spec asks for, no more. It
  has no dependency on `@chatwoot/prosemirror-schema`, so it cannot regress or conflict with the
  conversation composer or article editor during upstream syncs (Constitution Principle I).
- This mirrors the fork's established practice of isolating new, fork-specific UI in its own
  scoped implementation (Constitution Personalization Boundaries: "New, fork-specific features
  MUST live in an isolated, clearly delimited location... even when the isolated approach takes
  more engineering effort than a direct edit would").

**Alternatives considered**:
- Reuse `WootWriter/Editor.vue` — rejected, no underline mark and irrelevant composer-specific UI.
- Reuse `WootWriter/FullEditor.vue` — rejected, no underline mark and irrelevant article-editor UI
  (image upload, embeds).
- Patch `@chatwoot/prosemirror-schema` to add an underline mark — rejected, violates Upstream
  Compatibility First (shared, externally-published package) and is a disproportionate change for
  one field.
- Native `contenteditable` + `document.execCommand` — rejected, `execCommand` is deprecated,
  inconsistent across browsers, and much harder to serialize/sanitize reliably than a structured
  editor's HTML output.

## R3a: Detecting an "empty" rich-text description

**Decision**: Blank/empty detection MUST use the editor's own structural emptiness check
(Tiptap's `editor.isEmpty` getter), not a raw string/whitespace check on the serialized HTML.

**Rationale**: Tiptap (like other structured rich-text editors) does not serialize an "empty"
document as an empty string — an untouched or fully-cleared editor typically emits `<p></p>`,
which is non-blank by a naive `description.trim().length === 0` check even though it contains no
visible content. Both FR-003 (clearing the description must persist as empty) and FR-011 (the
kanban info panel must show the empty state when there is "no description") depend on correctly
recognizing this case; a naive string check would silently fail both. Concretely:
- **On save** (`StageDescriptionEditor.vue` / `EditPipelineStage.vue`): before dispatching
  `pipelineStages/update`, check the editor's `isEmpty` state and send `null`/`''` for
  `description` when it is empty, rather than sending `<p></p>`.
- **On render** (`KanbanColumn.vue`): treat `description` as blank for the purposes of FR-011
  when it is `null`/`''`/whitespace-only **or** consists only of empty block markup with no
  visible text (in practice, guaranteed by the save-time normalization above, so the render-time
  check can safely stay a simple blank/whitespace check on the stored value).

**Alternatives considered**: Stripping HTML tags and checking the remaining text for blankness at
render time — rejected as redundant/riskier than simply normalizing at save time, and it would
require a second, independent "strip HTML" implementation just for this check.

## R4: Rendering the formatted description on the kanban board

**Decision**: Render the sanitized HTML with the existing `v-dompurify-html` directive inside the
new expandable panel in `KanbanColumn.vue`, matching the pattern already used for other
user-authored rich content in the dashboard (e.g. `CompanyNotesSidebar.vue`).

**Rationale**: Keeps sanitization logic in exactly one, already-audited place (the global
`v-dompurify-html` directive) rather than introducing a new one, satisfying Principle III.

**Alternatives considered**: Server-side sanitization on write (e.g. Rails `Loofah`/
`Rails::Html::Sanitizer`) — not rejected outright as a defense-in-depth option, but not required
to satisfy the spec since the existing convention already sanitizes at render time everywhere else
in the dashboard; adding a second sanitization layer here (and not to the other,
already-shipped rich-text fields) would be an inconsistent, un-requested scope expansion. Kept out
of this feature; noted only as a possible follow-up, not part of this plan.

## R5: Persistence fix shape

**Decision**: Add an additive migration `add_column :ichatr_pipeline_stages, :description, :text`,
following the exact pattern of the two prior additive migrations on this table
(`add_accent_color...`, `add_stale_after_days...`). No changes needed to the controller's
`pipeline_stage_params` (already permits `:description`) or to `EditPipelineStage.vue`'s payload
(already sends `description`) — both were already correct and only lacked a column to write to.

**Rationale**: Matches Constitution's explicit allowance for additive migrations under
`db/migrate/` and Principle II (smallest change — the bug's actual root cause is a single missing
column, not a broader design flaw).

**Alternatives considered**: None; this is the minimal fix once the root cause is confirmed.

## Summary of decisions

| Area | Decision |
|---|---|
| Root cause | Missing `description` column on `ichatr_pipeline_stages` |
| Fix | Additive migration adding a `text` column, no other backend changes needed |
| Storage format | Sanitized HTML |
| Editor | New, isolated Tiptap-based rich-text input (`@tiptap/vue-3` + `starter-kit` + `underline`) |
| Rendering | Existing `v-dompurify-html` directive convention |
| Kanban panel | New expandable section in `KanbanColumn.vue`, per-column local state |
