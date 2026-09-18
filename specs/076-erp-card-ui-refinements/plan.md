# Implementation Plan: ERP Contact Card UI Refinements

**Branch**: `076-erp-card-ui-refinements` | **Date**: 2026-09-18 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/076-erp-card-ui-refinements/spec.md`

---

## Summary

This feature refines the user interface of the ERP Contact Data Card (`ErpDataCard.vue`) located in the agent dashboard contact panel sidebar. Building upon Phase 02 (feature 075), it addresses visual density, clutter, and layout ergonomics through four targeted improvements:

1. **Consolidated Single-Line Address**: Synthesizes up to 7 separate raw address fields (`nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa`) into a single "Endereço" attribute line formatted as `{logradouro}, {número}[, {complemento}], {bairro}, {cidade}/{uf} - {cep}`, dynamically pruning missing components without stray commas or dangling hyphens, and suppressing all 7 individual rows from the card.
2. **Primary Phone Display with Inline Expansion**: Selects the customer's cell phone (`nrTelcelpessoa`) as the default primary number (falling back to residential or commercial phone if cell is absent). When multiple phone numbers exist, renders an ellipsis toggle button (`...`) adjacent to the primary number that expands an inline accordion displaying the secondary numbers with their specific channel labels directly in the attributes list.
3. **Redesigned Appointments Layout**: Replaces the bulky dark stacked box container cards with an integrated, compact key-value list styled in harmony with customer attributes, preserving all clinical details (`ultimo` with attendance status, `proximo` with confirmation badge, professional name, and localized date/times) while reducing vertical height by > 30%.
4. **Centered Registration Audit Timestamps**: Replaces left-aligned stacked audit dates with centered, subtle italic timestamps at the bottom of the card, joining them with a middle bullet dot (`•`) when both are present and allowing responsive line wrapping on narrow sidebars without overflow.
5. **Synchronous Localization**: Adds `ADDRESS`, `PHONE_TOGGLE_MORE`, and `PHONE_TOGGLE_LESS` synchronously to English (`en.json`) and Brazilian Portuguese (`pt_BR.json`).

---

## Technical Context

**Language/Version**: JavaScript (ES2022+) / Vue 3 (Composition API `<script setup>`)

**Primary Dependencies**:
- Frontend: Vue 3, Tailwind CSS, Vue-i18n, `@vue/test-utils`, Vitest (testing)

**Storage**: N/A (Frontend presentation layer; consumes existing backend proxy endpoint `GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`)

**Testing**:
- Frontend: Vitest (`app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js`)
- Commands: `docker compose exec vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js`

**Target Platform**: Modern desktop web browsers (Linux / macOS / Windows) supporting the agent dashboard

**Project Type**: Web Application UI Component (Vue 3 Single File Component)

**Performance Goals**:
- Zero additional network calls or backend latency.
- Instantaneous client-side phone expansion toggle (< 16ms, 60fps).
- Total rendered height of the appointments block reduced by at least 25% (target > 30%).
- Consolidated address reduces address vertical space by at least 70% (from up to 7 rows to 1 row).

**Constraints**:
- Container-based development only per `AGENTS.md` (`docker compose exec vite ...`).
- Strict Tailwind utility classes only: no scoped CSS, no custom CSS classes, no inline styles.
- Strict TDD discipline per Constitution Principle VI (red-green targeted test execution).
- Observability and mutation resistance per Constitution Principle VII.
- Synchronous localization in English (`en.json`) and Brazilian Portuguese (`pt_BR.json`).
- Sidebar width constraints: must display cleanly without clipping or horizontal overflow on widths between 240px and 360px.

**Scale/Scope**: 1 UI component (`ErpDataCard.vue`), 1 test suite (`ErpDataCard.spec.js`), 2 translation files (`en/conversation.json`, `pt_BR/conversation.json`).

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evaluation |
|---|---|---|
| **I. Upstream Compatibility First** | **PASS** | Modifies only `ErpDataCard.vue`, which is a fork-specific component created in feature 075 and wired via an existing tracked hook in `ContactPanel.vue`. No upstream or core Chatwoot files are altered. |
| **II. Smallest Production-Ready Change** | **PASS** | Focuses purely on the 4 visual refinements specified by the user. No changes to backend APIs, database models, or speculative abstractions. |
| **III. Adhere to Established Conventions** | **PASS** | Uses Vue 3 Composition API `<script setup>`, Tailwind utility classes only, i18n for all strings, and established Vitest patterns. |
| **IV. Safe, Reversible Change Management** | **PASS** | Purely frontend presentation adjustments. Zero risk of data loss, migration issues, or schema divergence. |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | **PASS** | The ERP Contact Card is shared across editions; no Enterprise override is required or affected. |
| **VI. Test-Driven Development (NON-NEGOTIABLE)** | **PASS** | All four refinements (address consolidation, phone priority/disclosure, appointment redesign, centered timestamps) are test-driven first via failing Vitest specs before component implementation. |
| **VII. Observable Behavior and Mutation Resistance** | **PASS** | Tests verify observable DOM state: rendered single-line text, absence of isolated address rows, phone accordion expansion on click toggle, attendance/confirmation badges, and bullet separator existence. |
| **VIII. Pragmatic Test-First by Functional Slice** | **PASS** | Implemented as a cohesive frontend UI refinement slice with its complete test matrix. Intermediate progress logs and step-diaries are forbidden. |
| **IX. Surgical Execution Scope and Decoupled Global Gates** | **PASS** | Test execution during iteration is strictly targeted to `ErpDataCard.spec.js`. Full repo suites are not run during iterative cycles. |

---

## Project Structure

### Documentation (this feature)

```text
specs/076-erp-card-ui-refinements/
├── plan.md              # Implementation plan (this document)
├── research.md          # Phase 0 decisions on address, phones, appointments, and footnotes
├── data-model.md        # Phase 1 entities, composition rules, and component state
├── quickstart.md        # Phase 1 verification scenarios and Vitest commands
├── contracts/           # Phase 1 UI contract specification
│   └── erp-card-ui-contract.md
└── checklists/
    └── requirements.md  # Requirements traceability checklist
```

### Source Code (repository root)

```text
app/javascript/dashboard/
├── components/widgets/conversation/
│   ├── ErpDataCard.vue                                        # Component receiving UI refinements
│   └── specs/
│       └── ErpDataCard.spec.js                                # Vitest specs covering all refinements
└── i18n/locale/
    ├── en/
    │   └── conversation.json                                  # English localization keys
    └── pt_BR/
        └── conversation.json                                  # Brazilian Portuguese localization keys
```

**Structure Decision**: Pure frontend refinement residing in `app/javascript/dashboard/components/widgets/conversation/` and the dashboard locale files. No backend or database directories touched.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *None* | N/A | N/A |
