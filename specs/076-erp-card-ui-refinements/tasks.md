---
description: "Task list for ERP Contact Card UI Refinements"
---

# Tasks: ERP Contact Card UI Refinements

**Input**: Design documents from `/specs/076-erp-card-ui-refinements/`
- `spec.md` (Clarifications, User Stories US1–US4, Requirements FR-001 to FR-011, Success Criteria SC-001 to SC-006)
- `plan.md` (Architecture, Tech Stack, Constraints, Scale/Scope)
- `data-model.md` (Consolidated Address, Phone Channel State, Redesigned Appointments, Centered Footnotes)
- `research.md` (Address Composition, Phone Accordion, Clean Appointments List, Centered Footnotes, Localization)
- `contracts/erp-card-ui-contract.md` (Test IDs, Formatting Matrix, Localization Keys)
- `quickstart.md` (Verification Scenarios 1 to 5)
- `.specify/memory/constitution.md` (Principles I–IX, TDD Mandate)

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: Constitution Principle VI (Test-Driven Development, NON-NEGOTIABLE) and `plan.md` mandate test-first coverage for all behavioral changes in the Vitest component suite (`app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js`). Test tasks are MANDATORY: write tests first, prove they fail for the right reason, then implement.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `- [ ] [TaskID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`, `[US4]`; omitted for Setup, Foundational, and Polish phases)
- Include exact file paths in all descriptions
- Include verbatim constraints from `data-model.md` and `contracts/` in task descriptions

## Path Conventions

Web application frontend (Vue 3 Single File Component + Vitest):
- Component: `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`
- Component Specs: `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js`
- English Locale: `app/javascript/dashboard/i18n/locale/en/conversation.json`
- Portuguese (Brazil) Locale: `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish synchronous localization keys in English and Brazilian Portuguese before component implementation.

- [X] T001 [P] Add address and phone disclosure toggle localization keys (`FIELDS.ADDRESS`: `"Address"`, `PHONE_TOGGLE_MORE`: `"Show all phone numbers"`, `PHONE_TOGGLE_LESS`: `"Show main phone only"`) to `app/javascript/dashboard/i18n/locale/en/conversation.json`
- [X] T002 [P] Add address and phone disclosure toggle localization keys (`FIELDS.ADDRESS`: `"Endereço"`, `PHONE_TOGGLE_MORE`: `"Ver todos os telefones"`, `PHONE_TOGGLE_LESS`: `"Exibir apenas telefone principal"`) to `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data formatting helpers and reactive state primitives in `ErpDataCard.vue` required across user stories.

**⚠️ CRITICAL**: In accordance with Constitution Principle VI (TDD), tests for foundational behavior MUST be written and confirmed failing before implementation code is written.

### Tests for Foundational Components (TDD - Write First)

- [X] T003 Extend Vitest unit spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing address formatting utility helper `formatAddress` with full address (`nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa`), missing complement, city/state only, standalone CEP without leading hyphen, and null/empty field handling
- [X] T004 Extend Vitest unit spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing phone channel selection logic prioritizing cell phone (`nrTelcelpessoa` > `nrTelrespessoa` > `nrTelcompessoa`), secondary channels grouping, and multiple phones detection

### Implementation for Foundational Components

- [X] T005 Implement `formatAddress` helper in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue` composing `{logradouro}, {número}[, {complemento}], {bairro}, {cidade}/{uf} - {cep}`, applying `maskCep` to `nrCeppessoa`, and dynamically pruning empty components without stray commas or dangling hyphens
- [X] T006 Implement phone channel resolver and local reactive state `isPhonesExpanded = ref(false)` in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue` prioritizing cell over residential/commercial, computing `primaryPhone`, `secondaryPhones`, and resetting `isPhonesExpanded` on `contactId` change

**Checkpoint**: Foundation ready - user story implementation can now begin.

---

## Phase 3: User Story 1 - Single-Line Consolidated Address (Priority: P1) 🎯 MVP

**Goal**: Synthesize up to 7 discrete address fields (`nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa`) into a single "Endereço" attribute row, omitting individual address rows from the card and hiding the row when no address data exists.

**Independent Test**: Render card with full address, address lacking complement, partial address (city/state only, CEP only), and no address. Verify consolidated single-line output, formatted CEP (`00000-000`), absence of individual address rows, and absence of the address row when empty.

### Tests for User Story 1 (TDD - Write First)

- [X] T007 [US1] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing consolidated address row rendering: displays single line `{logradouro}, {número}, {complemento}, {bairro}, {cidade}/{uf} - {cep}` with masked CEP; formats cleanly without double commas when complement is absent; renders city/state only without trailing separators; renders standalone CEP without leading hyphen; omits "Endereço" row completely when all address fields are absent/empty; and strictly asserts that `nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa` do not render as separate attribute rows

### Implementation for User Story 1

- [X] T008 [US1] Remove individual address keys (`nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa`) from `WHITELIST_FIELDS` and inject consolidated "Endereço" item into `customerAttributes` computed property in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`

**Checkpoint**: User Story 1 (MVP) is fully functional and testable independently.

---

## Phase 4: User Story 2 - Primary Phone Display with Expansion for Additional Numbers (Priority: P1)

**Goal**: Display the customer's cell phone as default primary number (falling back to residential or commercial), showing an ellipsis button (`...`) only when additional phone numbers exist, and expanding/collapsing secondary phone rows inline within the attribute list on click.

**Independent Test**: Render card with only cell phone (no ellipsis), cell + residential/commercial (primary phone + ellipsis button visible), click ellipsis to verify inline secondary phone rows expand with channel labels and masks, click again to collapse, and verify fallback to residential/commercial when cell is absent.

### Tests for User Story 2 (TDD - Write First)

- [X] T009 [US2] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing primary phone display and inline expansion: renders cell phone as primary with `data-testid="erp-primary-phone-row"`; does not render ellipsis button `data-testid="erp-phone-expand-toggle"` when only one phone exists; renders ellipsis button when multiple phones exist; toggles inline secondary phone rows `data-testid="erp-secondary-phone-row"` with respective channel labels (`Telefone residencial`, `Telefone comercial`) and phone masks on click; collapses secondary rows when clicked again; falls back to residential phone as primary when cell is absent; and resets `isPhonesExpanded` to false when `contactId` changes

### Implementation for User Story 2

- [X] T010 [US2] Remove raw phone fields (`nrTelcelpessoa`, `nrTelrespessoa`, `nrTelcompessoa`) from `WHITELIST_FIELDS`, integrate resolved primary phone and expandable secondary phones into the customer attributes list with `data-testid="erp-primary-phone-row"`, `data-testid="erp-phone-expand-toggle"`, `data-testid="erp-secondary-phone-row"`, and accessible title tooltips (`PHONE_TOGGLE_MORE`, `PHONE_TOGGLE_LESS`) in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`

**Checkpoint**: User Story 2 is fully functional and testable independently alongside User Story 1.

---

## Phase 5: User Story 3 - Redesigned Appointments Presentation (Priority: P2)

**Goal**: Replace bulky dark stacked box containers in `atendimentos` section with an integrated, compact key-value clean list styled in harmony with customer attributes, preserving dates, professionals, attendance badge, and confirmation badge.

**Independent Test**: Render card with both last and next appointments populated, verify clean key-value layout with subtle status badges and absence of dark box containers; render with null next appointment, verify subtle empty indicator text without empty box frames.

### Tests for User Story 3 (TDD - Write First)

- [X] T011 [US3] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing redesigned appointments list: verifies removal of dark stacked box container classes (`bg-n-alpha-1`, `border-n-weak`); verifies last appointment row `data-testid="erp-appointment-ultimo"` displays localized date/time, attending professional (`comQuem`), and attendance status badge (`Compareceu` / `Não compareceu`); verifies next appointment row `data-testid="erp-appointment-proximo"` displays localized date/time, scheduled professional, and confirmation badge `data-testid="erp-appointment-confirmed-badge"` (`Confirmado` / `Não confirmado`); verifies clean empty indicator text when next appointment is null without empty box container; and verifies omission when `atendimentos` is null

### Implementation for User Story 3

- [X] T012 [US3] Redesign the `atendimentos` section template in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue` to use clean key-value item rows with subtle dividers (`divide-y divide-n-weak`), removing dark box containers (`p-2 mb-2 rounded bg-n-alpha-1 border border-n-weak`) and adding `data-testid="erp-appointment-ultimo"`, `data-testid="erp-appointment-proximo"`, and `data-testid="erp-appointment-confirmed-badge"`

**Checkpoint**: User Story 3 is fully functional and testable independently.

---

## Phase 6: User Story 4 - Centered and Responsive Registration Audit Timestamps (Priority: P2)

**Goal**: Center registration and update audit dates horizontally at the bottom of the card on a single line separated by `•`, wrapping gracefully on narrow sidebars without overflow, and omitting separator if only one timestamp exists.

**Independent Test**: Render card with both timestamps (verify centered alignment and bullet dot separator `•`), only registration timestamp (verify centered alignment and no separator), only update timestamp (verify centered and no separator), and neither timestamp (verify footnote block omitted).

### Tests for User Story 4 (TDD - Write First)

- [X] T013 [US4] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing centered audit footnotes (FR-008 to FR-011): verifies container has center alignment classes (`flex flex-wrap items-center justify-center text-center`); verifies both dates render with bullet dot separator `data-testid="erp-audit-separator"`; verifies single date renders without separator; and verifies footnote section is omitted completely when both timestamps are null per FR-011

### Implementation for User Story 4

- [X] T014 [US4] Update the audit footnotes template in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue` to center-align the footer using `flex flex-wrap items-center justify-center gap-x-1.5 gap-y-0.5 text-center text-[10px] text-n-slate-10 italic`, rendering `data-testid="erp-audit-created-at"`, `data-testid="erp-audit-updated-at"`, and bullet dot `data-testid="erp-audit-separator"` (`•`) when both timestamps are present

**Checkpoint**: All 4 user stories are fully functional and integrated.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Linting, comprehensive component verification, and end-to-end quickstart validation across all user stories.

- [X] T015 Run frontend ESLint on modified files via `docker compose exec vite pnpm eslint app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` ensuring 0 errors
- [X] T016 Run full Vitest suite for `ErpDataCard.spec.js` via `docker compose exec vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` ensuring all 4 user stories and legacy regression tests pass 100%
- [X] T017 Validate all 5 manual verification scenarios in `specs/076-erp-card-ui-refinements/quickstart.md` (Consolidated Address, Primary Phone & Expansion, Redesigned Appointments, Centered Footnotes, and Localization Parity)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - BLOCKS user stories.
- **User Story 1 (Phase 3 - P1)**: Depends on Foundational (Phase 2).
- **User Story 2 (Phase 4 - P1)**: Depends on Foundational (Phase 2). Can execute in parallel with US1 or sequentially.
- **User Story 3 (Phase 5 - P2)**: Depends on Foundational (Phase 2). Modifies template `atendimentos` section.
- **User Story 4 (Phase 6 - P2)**: Depends on Foundational (Phase 2). Modifies template `footnotes` section.
- **Polish (Phase 7)**: Depends on all user stories (Phases 3–6) complete.

```
Phase 1: Setup (T001 [P], T002 [P])
   │
   ▼
Phase 2: Foundational (T003, T004 -> T005, T006)
   │
   ▼
Phase 3: US1 - P1 MVP (T007 -> T008)
   │
   ▼
Phase 4: US2 - P1 (T009 -> T010)
   │
   ▼
Phase 5: US3 - P2 (T011 -> T012)
   │
   ▼
Phase 6: US4 - P2 (T013 -> T014)
   │
   ▼
Phase 7: Polish (T015 -> T016 -> T017)
```

### User Story Dependencies

- **User Story 1 (P1)**: Core MVP delivery. Operates on `customerAttributes` and address fields.
- **User Story 2 (P1)**: Operates on phone fields in `customerAttributes` and phone expansion toggle.
- **User Story 3 (P2)**: Operates on `atendimentos` template section. Independent from US1/US2.
- **User Story 4 (P2)**: Operates on footnotes template section. Independent from US1/US2/US3.

### Within Each Phase (TDD Discipline)

- Test tasks MUST be written and confirmed failing before implementation tasks.
- Foundational tests (T003, T004) run before foundational implementation (T005, T006).
- US1 test (T007) runs and fails before US1 implementation (T008).
- US2 test (T009) runs and fails before US2 implementation (T010).
- US3 test (T011) runs and fails before US3 implementation (T012).
- US4 test (T013) runs and fails before US4 implementation (T014).

### Parallel Opportunities

- **Phase 1 (Setup)**: T001 and T002 touch distinct localization files (`en/conversation.json` and `pt_BR/conversation.json`) and run in parallel without file conflicts.
- **Phases 2–6 (Functional Slices)**: Because all test tasks target a single test file (`ErpDataCard.spec.js`) and all implementation tasks target a single component file (`ErpDataCard.vue`), phases execute sequentially by functional slice per Constitution Principle VIII to prevent write conflicts and maintain strict red-green TDD integrity.
- **Phase 7 (Polish)**: Verification and linting run sequentially to ensure total quality gate pass.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001, T002)
2. Complete Phase 2: Foundational (T003, T004 -> T005, T006)
3. Complete Phase 3: User Story 1 (T007 -> T008)
4. **STOP and VALIDATE**: Verify User Story 1 independently in Vitest and browser (address renders on single line, CEP masked, no double commas, individual address rows removed, empty address omitted).

### Incremental Delivery

1. Setup + Foundational -> Foundation ready and tested.
2. User Story 1 -> Deliver MVP consolidated single-line address.
3. User Story 2 -> Add primary cell phone display with inline ellipsis expansion toggle.
4. User Story 3 -> Redesign appointments into integrated key-value clean list.
5. User Story 4 -> Center registration audit timestamps with middle bullet separator.
6. Polish -> Linting, full suite run, and quickstart scenario validation.

---

## Notes

- Every task strictly follows `- [ ] [TaskID] [P?] [Story?] Description with file path`.
- Pure frontend refinement; no backend routes, services, or database migrations modified.
- All strings are synchronized across English (`en/conversation.json`) and Brazilian Portuguese (`pt_BR/conversation.json`).
- Container command per `AGENTS.md`: `docker compose exec vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js`.
