# Feature Specification: ERP Contact Card UI Refinements

**Feature Branch**: `076-erp-card-ui-refinements`

**Created**: 2026-09-18

**Status**: Draft

**Input**: User description: "dando continuidade ao card de dados de erp, quero simplificar os dados do endereço do cliente, hoje é uma informação por linha. quero compor um endereço em uma linha no formato logradouro, número, complemento (opcional), bairro, cidade/uf - cep. o contato pode ter 3 telefones, o principal é o celular. vamos exibir apenas o celular, mas se houver mais, aparece um ... ao lado do contato. clicar nesse sinal, exibe todos os telefones disponíveis. também quero explorar outra forma de exibir os dados dos atendimentos. não gosto do design proposto: [Image #1, 268x200] . por fim, quero centralizar a data de cadastro e a data de atualização, podem ser na mesma linha, quebrando em mais linha, seperados por uma bolinha."

## Clarifications

### Session 2026-09-18

- Q: Qual direção de design deve ser adotada para a seção de atendimentos para substituir as caixas escuras empilhadas? (FR-007) → A: Opção A — Linhas chave-valor integradas (estilo lista limpa): remove completamente as caixas e fundos escuros, exibindo "Último atendimento" e "Próximo atendimento" como linhas compactas no mesmo padrão dos atributos do cliente (ex: data/hora, badge sutil de status e profissional em linha), garantindo harmonia visual e economia de espaço vertical.
- Q: Qual o comportamento visual de exibição dos telefones ao clicar em `...`? (FR-006) → A: Opção A — Expansão inline na própria lista (Accordion/Toggle): ao clicar em `...`, a linha do telefone se expande verticalmente revelando os demais telefones cadastrados (Residencial e Comercial) diretamente na lista de atributos, recolhendo ao clicar novamente.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single-Line Consolidated Address (Priority: P1)

As an Agent handling a customer conversation, when viewing the customer's ERP data card in the contact sidebar, I want to see the customer's full address composed into a single clean line rather than multiple separate attribute rows, so that I can quickly read the customer's location while saving vertical space in the sidebar.

**Why this priority**: The current address presentation consumes up to 7 vertical rows (street, number, complement, neighborhood, city, state, zip code), dominating the sidebar and pushing crucial clinical, appointment, and financial details below the fold. Consolidating address details into a single standardized line dramatically improves readability and layout economy.

**Independent Test**: Can be tested independently by loading the ERP data card for contacts with varying address completeness (full address with complement, address without complement, address with partial fields) and verifying that the address renders on a single line following the pattern "Logradouro, Número[, Complemento], Bairro, Cidade/UF - CEP" with formatted CEP and without stray separators.

**Acceptance Scenarios**:

1. **Given** a customer record with all address fields present (`logradouro`, `número`, `complemento`, `bairro`, `cidade`, `uf`, `cep`), **When** the ERP card renders, **Then** a single "Endereço" attribute row is displayed in the format: `{logradouro}, {número}, {complemento}, {bairro}, {cidade}/{uf} - {cep}` (with CEP formatted with punctuation).
2. **Given** a customer record where `complemento` is empty or null, **When** the ERP card renders, **Then** the address is formatted cleanly without double commas or dangling punctuation (`{logradouro}, {número}, {bairro}, {cidade}/{uf} - {cep}`).
3. **Given** a customer record where all address fields are empty or null, **When** the ERP card renders, **Then** the "Endereço" attribute row is omitted from the card.
4. **Given** individual address components displayed previously as separate rows (`nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa`), **When** viewing the card, **Then** none of these individual rows appear separately in the attributes list.

---

### User Story 2 - Primary Phone Display with Expansion for Additional Numbers (Priority: P1)

As an Agent conversing with a customer, I want to see the customer's primary cell phone number displayed cleanly in the personal data list, with an ellipsis indicator (`...`) whenever additional phone numbers (residential, commercial) exist, so that the main contact number is immediately visible while secondary numbers remain easily accessible on demand.

**Why this priority**: Displaying up to three distinct phone rows (cell, residential, commercial) creates clutter when agents predominantly interact via cell phone. Showing the primary phone number with an on-demand disclosure mechanism keeps the card compact while preserving access to alternative contact channels.

**Independent Test**: Can be tested independently by viewing contacts with: (a) only a cell phone, (b) a cell phone and one or more additional phones, (c) no cell phone but having residential/commercial phones. Verify that the ellipsis appears only when multiple numbers exist, and clicking it reveals all available numbers.

**Acceptance Scenarios**:

1. **Given** a customer record with only a cell phone (`nrTelcelpessoa`), **When** rendered, **Then** the cell phone is displayed with its formatted number without any ellipsis indicator.
2. **Given** a customer record with a cell phone and at least one secondary phone (`nrTelrespessoa` or `nrTelcompessoa`), **When** rendered, **Then** the cell phone is displayed as the primary phone with an ellipsis button (`...`) adjacent to it.
3. **Given** a customer record with multiple phones displaying the ellipsis indicator, **When** the agent clicks the ellipsis button, **Then** all available phone numbers for the customer are displayed with their respective type labels.
4. **Given** a customer record with no cell phone but possessing a residential or commercial phone, **When** rendered, **Then** the first available phone number is displayed as the primary number, accompanied by the ellipsis indicator if more than one secondary number exists.
5. **Given** expanded phone numbers, **When** the agent clicks the ellipsis/close toggle again, **Then** the view collapses back to the primary phone only.

---

### User Story 3 - Redesigned Appointments Presentation (Priority: P2)

As an Agent reviewing customer appointments, I want the appointment history (last visit) and upcoming schedule (next visit) presented in an integrated, space-efficient, and visually clear format that replaces the heavy dark stacked card boxes, so that I can quickly assess appointment status and professional assignments without visual weight or awkward layout breaks.

**Why this priority**: The initial boxed cards design (two bulky dark blocks with disjointed status labels and excessive padding) feels visually disconnected from the rest of the sidebar attributes and occupies excessive vertical space. A refined, coherent layout improves visual hierarchy and agent scanning speed.

**Independent Test**: Can be tested independently by viewing contacts with: (a) both last and next appointments populated, (b) last appointment populated and next appointment null ("Nenhum agendamento futuro"), (c) no appointment history. Verify that the updated visual layout displays all required information (dates, professional, attendance, confirmation badge) harmoniously without heavy dark stacked boxes.

**Acceptance Scenarios**:

1. **Given** a customer record with appointment data, **When** the card renders, **Then** the appointments section uses an integrated, compact presentation that conveys the last appointment and next appointment clearly without heavy isolated dark container boxes.
2. **Given** a customer record with a confirmed upcoming appointment, **When** rendered, **Then** the confirmation status is highlighted with a clear status badge.
3. **Given** a customer record with no upcoming appointment, **When** rendered, **Then** a clean, subtle empty indicator is displayed without creating empty box frames.
4. **Given** a customer record with no appointment data at all, **When** rendered, **Then** the appointments section is omitted or displays a concise summary.

---

### User Story 4 - Centered and Responsive Registration Audit Timestamps (Priority: P2)

As an Agent or Supervisor auditing customer records, I want the registration date and last update date centered at the bottom of the card, displayed inline on a single line separated by a bullet dot and wrapping responsively when needed, so that record metadata is discreet, elegant, and neatly balanced at the card footer.

**Why this priority**: Currently, audit dates are left-aligned across separate lines at the bottom of the card. Centering them and combining them with a bullet separator provides a polished, balanced footer that clearly separates customer operational data from audit metadata.

**Independent Test**: Can be tested independently by inspecting the card footer for records with: (a) both registration and update dates, (b) only registration date, (c) only update date, across different sidebar widths. Verify that the timestamps are centered, separated by `•` when both are present, and wrap cleanly on narrow widths without overflowing.

**Acceptance Scenarios**:

1. **Given** a customer record with both registration date (`dtCadpessoa`) and update date (`dtUltaltpessoa`), **When** rendered, **Then** both timestamps appear centered at the bottom of the card on the same line, separated by a bullet dot (`•`), using localized date/time formatting and italicized subtle styling.
2. **Given** a narrow sidebar width where both timestamps cannot fit on a single horizontal line, **When** rendered, **Then** the items wrap to multiple lines while maintaining center alignment.
3. **Given** a customer record where only one of the audit timestamps is present, **When** rendered, **Then** that single timestamp is centered without the bullet dot separator.
4. **Given** a customer record where neither audit timestamp is present, **When** rendered, **Then** the audit footnote section is omitted.

---

### Edge Cases

- **Partial address information**: If only some address fields exist (e.g., only neighborhood and city, or only street and number without neighborhood or zip code), the formatter must join the non-empty components cleanly with commas, omitting empty segments without double commas (`, ,`), leading commas, or dangling hyphens.
- **Address with only CEP**: If only the CEP is present, display it formatted as `00000-000` without a leading hyphen or prefix.
- **Multiple phones with identical numbers**: If the ERP record contains identical phone numbers across different fields (e.g. cell and commercial have the same digits), the system distinguishes them by channel type label (Telefone residencial, Telefone comercial) rather than discarding them, ensuring all configured channels remain identifiable.
- **Phone expansion toggle state**: The expanded/collapsed state of additional phones should remain local to the current card session or conversation view, defaulting to collapsed when switching contacts.
- **Missing professional (`comQuem`) in appointments**: If the attending or scheduled professional is not provided, the appointment line displays date/time and attendance/confirmation status cleanly without awkward "Com: -" labels.
- **Extreme viewport widths**: Centered audit timestamps must handle narrow sidebar resizing without horizontal scrolling or text clipping, wrapping into two centered lines naturally.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: **Consolidated Single-Line Address**: The system MUST combine customer address fields (`nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa`) into a single "Endereço" attribute entry instead of displaying them as separate rows.
- **FR-002**: **Address Formatting Pattern**: The consolidated address MUST follow the pattern: `{logradouro}, {número}, {complemento}, {bairro}, {cidade}/{uf} - {cep}`, dynamically omitting missing/empty components so no extra commas, redundant spaces, or dangling hyphens appear.
- **FR-003**: **Address Punctuation Mask**: Standard CEP punctuation masking (`00000-000`) MUST be applied to `nrCeppessoa` within the consolidated address string when matching an 8-digit pattern.
- **FR-004**: **Primary Phone Selection**: In the customer personal attributes section, the system MUST display the cell phone (`nrTelcelpessoa`) as the primary contact number by default. If `nrTelcelpessoa` is empty or not provided, the system MUST fall back to the first available secondary phone (`nrTelrespessoa` or `nrTelcompessoa`).
- **FR-005**: **Additional Phones Indicator**: When more than one phone number is present across `nrTelcelpessoa`, `nrTelrespessoa`, and `nrTelcompessoa`, the system MUST render an ellipsis indicator button (`...`) adjacent to the displayed primary phone number.
- **FR-006**: **Phone Numbers Inline Disclosure (Accordion/Toggle)**: The system MUST implement an inline accordion/toggle on the customer attributes list: clicking `...` vertically expands the phone entry to reveal secondary phone lines (labeled respectively as Telefone residencial, Telefone comercial) directly within the attribute list, with standard phone masks applied. Clicking `...` again collapses the view back to the primary phone only.
- **FR-007**: **Redesigned Appointments Layout (Integrated Key-Value Clean List)**: The system MUST replace the dark stacked box container design in the appointments (`atendimentos`) section with an integrated clean key-value list matching the visual styling of customer attributes per `contracts/erp-card-ui-contract.md`, rendering:
  - `ultimo`: localized appointment date/time, attending professional (`comQuem`), and subtle attendance status badge (`Compareceu` / `Não compareceu`) formatted on compact inline rows without dark box frames.
  - `proximo`: localized appointment date/time, scheduled professional (`comQuem`), and a subtle confirmation status badge (`Confirmado` / `Não confirmado`), or a clean empty indicator text ("Nenhum agendamento futuro") if null, without empty container cards.
- **FR-008**: **Centered Audit Footnote**: The system MUST render registration date (`dtCadpessoa`) and update date (`dtUltaltpessoa`) centered horizontally at the bottom of the card in subtle italicized text per `contracts/erp-card-ui-contract.md`.
- **FR-009**: **Inline Bullet-Separated Audit Dates**: When both `dtCadpessoa` and `dtUltaltpessoa` are present, they MUST be displayed on the same horizontal line separated by a bullet dot (`•`), wrapping gracefully into multiple centered lines on narrow viewports.
- **FR-010**: **Single Audit Timestamp Fallback**: When only one audit timestamp is available, it MUST be centered without the bullet dot separator.
- **FR-011**: **Audit Footnote Omission**: When neither `dtCadpessoa` nor `dtUltaltpessoa` is present, the audit footnote block MUST be omitted completely from the card.
- **FR-012**: **Synchronous Localization**: All new and modified labels, tooltips, and accessibility strings MUST be provided synchronously in English (`en.json`) and Brazilian Portuguese (`pt_BR.json`).

### Key Entities

- **Customer Record**: The customer entity returned by the ERP integration containing personal attributes (`nmPessoa`, `nrCpfcnpjpessoa`, address fields, phone fields), appointment history/schedule (`atendimentos`), and audit timestamps (`dtCadpessoa`, `dtUltaltpessoa`).
- **Consolidated Address**: A virtual formatted string synthesized from the distinct raw address components (`nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa`).
- **Phone Channel Set**: The set of available customer contact numbers (`nrTelcelpessoa`, `nrTelrespessoa`, `nrTelcompessoa`) categorized by channel type, supporting primary display and expanded disclosure.
- **Appointments Schedule**: Structured representation of historical (`ultimo`) and future (`proximo`) customer visits with professional, date/time, and attendance/confirmation statuses.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Sidebar vertical space consumed by address data is reduced by at least 70% (from up to 7 distinct lines down to 1 consolidated line).
- **SC-002**: 100% of customer records with multiple phone numbers display the primary phone number initially with the ellipsis indicator, preventing visual clutter while maintaining 100% discoverability of secondary numbers.
- **SC-003**: 100% of addresses with missing optional components (such as complement) render with correct grammatical punctuation (0 instances of double commas `,,` or dangling hyphens `- `).
- **SC-004**: 100% of appointment data (date/time, professional, confirmation status) remains visible and legible in the redesigned layout while reducing the vertical height of the appointments section by at least 25% compared to the boxed card design (verified visually in browser QA via Quickstart Scenario 3; unit test suite verifies structural removal of container box classes and layout token presence).
- **SC-005**: 100% of audit timestamp footers are centered across all supported sidebar widths without text clipping or horizontal overflow.
- **SC-006**: 100% of user-facing strings are localized synchronously in English and Brazilian Portuguese.

## Assumptions

- **Address component source**: The raw address fields continue to originate from `nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, and `nrCeppessoa` as delivered by the ERP API.
- **Primary phone priority**: Cell phone (`nrTelcelpessoa`) is always considered the primary contact channel in modern messaging workflows. Residential (`nrTelrespessoa`) and commercial (`nrTelcompessoa`) numbers serve as secondary fallbacks.
- **Appointment data contract**: The backend API and remote ERP contract for `atendimentos` (`ultimo` and `proximo` with `dataHora`, `comQuem`, `compareceu`, `confirmado`) remains unchanged; only the visual presentation in the frontend card is modified.
- **Sidebar width constraints**: The contact sidebar is typically 280px–360px wide; all layout refinements must be optimized for this compact width.
