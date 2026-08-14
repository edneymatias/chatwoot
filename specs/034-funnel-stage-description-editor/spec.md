# Feature Specification: Funnel Stage Rich Description & Kanban Info Panel

**Feature Branch**: `034-funnel-stage-description-editor`

**Created**: 2026-08-14

**Status**: Draft

**Input**: User description: "quero corrigir um bug na tela de edição de stage em funnel stages onde ao editar e adicionar uma description ao stage e salvar, o conteudo não é salvo. ou não está sendo carregado do banco. pois ao editar novamente, o campo esta vazio. além disso, quero suportar formatação simples nesse campo, talvez com um editor visual (negrito, itálico, taxado, sublinhado, lista numerada e lista numérica). além disso, quero colocar um ícone circular a esquerda do título do stage no quadro kanban com a letra/ícone I de informação. esse ícone deve ser clicável. ao clicar quero expandir de cima para baixo, empurrando os cards para baixo, uma seção logo abaixo do header da coluna com o conteudo da description do stage. essa seção deve renderizar o texto formatado cadastrado na description."

## Clarifications

### Session 2026-08-14

- Q: Quando um stage não tem description salva, o ícone de informação no kanban deve ficar desabilitado/oculto, ou continuar clicável mostrando um painel vazio com texto placeholder? → A: O ícone permanece sempre visível e clicável; ao clicar sem description, o painel expande mostrando um empty state que orienta o usuário sobre onde cadastrar a descrição.
- Q: O empty state deve apenas indicar em texto onde cadastrar a description, ou deve incluir um atalho clicável que abra diretamente a tela de edição do stage? → A: Apenas texto orientativo e amigável (ex.: "Adicione uma descrição na configuração dos estágios do funil"), sem link/navegação para fora do board.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stage description is actually saved (Priority: P1)

A pipeline manager edits a funnel stage, types a description explaining how that stage should be used, and saves the stage. When they reopen the edit screen later, the description they wrote is still there.

**Why this priority**: This is a data-loss bug. Users believe they've documented stage usage guidance, but it silently disappears, undermining trust in the settings screen and losing the information entirely. Nothing else in this feature is useful until the underlying persistence is fixed.

**Independent Test**: Can be fully tested by editing a stage, entering a description, saving, reloading the pipeline stages list (or reopening the edit modal), and confirming the same description text is present.

**Acceptance Scenarios**:

1. **Given** a stage with no description, **When** the user opens the edit form, types a description, and saves, **Then** the stage's description is persisted and visible the next time the edit form is opened for that stage.
2. **Given** a stage with an existing description, **When** the user changes the text and saves, **Then** the updated text (not the old text) is what loads on next edit.
3. **Given** a stage with an existing description, **When** the user clears the field entirely and saves, **Then** the stage's description is stored as empty on reload.

---

### User Story 2 - Simple rich-text formatting for the description (Priority: P2)

A pipeline manager writes stage usage guidance and wants to emphasize key points using bold, italic, strikethrough, underline, and lists, similar to formatting available elsewhere in the product's text editors.

**Why this priority**: Formatting makes stage guidance easier to scan and follow (e.g., a numbered checklist of what must happen before a deal can move to this stage). It builds directly on top of Story 1 — formatting is worthless if the content isn't saved — but is not required for the persistence bug fix to ship value.

**Independent Test**: Can be fully tested by opening the stage edit form, applying each formatting option (bold, italic, strikethrough, underline, ordered list, bulleted list) to sample text, saving, and reopening the form to confirm both the text and its formatting are preserved.

**Acceptance Scenarios**:

1. **Given** the stage edit form is open, **When** the user selects text and applies bold, italic, strikethrough, or underline, **Then** the selected text visibly reflects that formatting in the editor.
2. **Given** the stage edit form is open, **When** the user creates an ordered (numbered) list and a bulleted list, **Then** both list types render correctly in the editor.
3. **Given** a stage was saved with formatted description text, **When** the user reopens the edit form, **Then** the formatting (bold/italic/strikethrough/underline/lists) is restored exactly as it was saved, not shown as plain/raw text.

---

### User Story 3 - Expandable stage info panel on the kanban board (Priority: P3)

A user viewing the kanban board wants a quick reminder of what a given stage means without leaving the board or opening stage settings. They click a small circular "i" (information) icon next to the stage's column title and see the stage's description appear in a panel under the column header.

**Why this priority**: This surfaces the documented guidance from Stories 1 and 2 at the point of use (the board), which is where it delivers the most day-to-day value, but it is an enhancement layered on top of description data that must already exist and be readable.

**Independent Test**: Can be fully tested by opening the kanban board for a stage that has a saved description, clicking the info icon in that column's header, and confirming a panel appears below the header showing the formatted description; clicking again hides it.

**Acceptance Scenarios**:

1. **Given** a kanban column for a stage with a saved description, **When** the board loads, **Then** a circular info icon is visible to the left of the stage title in that column's header.
2. **Given** the info icon is visible, **When** the user clicks it, **Then** a panel expands directly below the column header, pushing the column's cards further down, and displays the stage's description with its formatting (bold, italic, strikethrough, underline, lists) rendered rather than shown as raw markup.
3. **Given** the info panel is expanded, **When** the user clicks the info icon again, **Then** the panel collapses and the cards return to their original position below the header.
4. **Given** a stage with no description saved, **When** the user clicks the info icon for that column, **Then** the panel expands showing a friendly empty-state message guiding the user to add a description in the funnel stage settings (e.g., "Add a description in the funnel stage settings to see it here"), with no link or navigation away from the board.

---

### Edge Cases

- What happens when a description contains only whitespace? It should be treated as empty (no description) for both persistence and the info-panel empty state.
- What happens when a very long description is entered? The edit field should remain usable (scrollable), and the kanban info panel should not grow unboundedly tall — it should be scrollable/constrained rather than pushing cards off-screen indefinitely.
- What happens if two stage columns both have their info panels expanded at once? Each column expands and collapses independently.
- What happens when the description is edited while the info panel is currently expanded on the board (e.g., another browser tab)? The panel should reflect the latest saved description next time the board data is refreshed, consistent with how other stage attributes (name, color) already refresh.
- What happens on narrow/mobile board layouts where column width is constrained? The info icon and panel must remain usable without overlapping the title or the add-card control.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST persist the stage description entered in the edit form so that it is retrievable after saving, including on subsequent page loads/sessions.
- **FR-002**: System MUST return the currently saved description whenever stage data is loaded (board fetch, edit form open), reflecting the most recent successful save.
- **FR-003**: System MUST allow the description to be cleared (set to empty) and persist that empty state.
- **FR-004**: The stage edit form MUST provide a visual formatting toolbar/controls for the description field supporting: bold, italic, strikethrough, underline, ordered (numbered) lists, and bulleted lists.
- **FR-005**: System MUST persist the formatting applied to the description (not just the plain text) so that it is restored with the same formatting the next time the description is edited or displayed.
- **FR-006**: The kanban board MUST display a circular information icon to the left of the stage title in each column's header.
- **FR-007**: Clicking the information icon MUST toggle an expandable section directly below that column's header, showing the stage's description rendered with its formatting.
- **FR-008**: Expanding the info section MUST push that column's cards downward (the panel occupies space above the card list) rather than overlapping them.
- **FR-009**: Each column's info panel state (expanded/collapsed) MUST be independent of other columns.
- **FR-010**: Clicking the information icon again MUST collapse the panel and restore the cards to their prior position.
- **FR-011**: When a stage has no description, the information icon MUST remain visible and clickable, and clicking it MUST expand the panel showing a friendly, guiding empty-state message (informing the user that a description can be added in the funnel stage settings) rather than an empty or broken panel; the empty state MUST NOT include a link or navigation shortcut away from the board.
- **FR-012**: The rendered description (in both the edit form preview/editing surface and the kanban info panel) MUST NOT expose raw formatting markup to the user — formatting must be shown visually (e.g., actually bold text), not as literal syntax characters.

### Key Entities

- **Pipeline Stage (Funnel Stage)**: Represents a column/step in the sales funnel; already has attributes like name, position, accent color. This feature adds/fixes a `description` attribute capable of storing formatted (rich) text, associated 1:1 with a stage.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of stage descriptions saved by users remain present and unchanged when the edit form is reopened, across sessions.
- **SC-002**: Users can apply and later see restored all six formatting options (bold, italic, strikethrough, underline, numbered list, bulleted list) on a saved description with no loss of formatting.
- **SC-003**: From the kanban board, a user can view a stage's description in under 2 clicks (open board, click info icon) without navigating away from the board.
- **SC-004**: Toggling the info panel open or closed visibly repositions the column's cards within 1 interaction, with no layout breakage (overlap, clipping) across supported column widths.

## Assumptions

- "Lista numerada e lista numérica" in the request is interpreted as ordered (numbered) list and unordered (bulleted) list — the two common list types — rather than two variants of the same numbered list.
- The rich-text formatting surface should follow the same visual/interaction conventions as the product's existing rich-text editor used elsewhere in the dashboard, rather than introducing a new distinct editor design.
- The description field's formatted content applies only to the stage-level description shown in the edit form and the board info panel; it does not affect any other text field (e.g., stage name) which remains plain text.
- The information icon and panel are additive to the current column header design; the existing controls (add-card button, lane total badge, drag handle) keep their current position and behavior aside from the new icon being inserted to the left of the title.
- Existing stages with no description continue to function normally (no forced migration of content); the empty state defined in FR-011 covers them.
