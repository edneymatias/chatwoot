# Feature Specification: ERP Contact Panel Data Card

**Feature Branch**: `075-erp-contact-data-card`

**Created**: 2026-09-17

**Updated**: 2026-09-18

**Status**: Draft

**Input**: User description: "Fase 02 — Card de Dados do ERP no Painel do Contato (docs/kanban/ciclo 10/02-erp-contact-panel-data-card/spec95.md). No escopo da spec 075 do speckit quero alterar o painel de contato para esconder alguns campos: idPessoa, idEmpresa, pessoaTipo, tpPessoa, nmPaispessoa, idProfpessoa, idUsuario, idEspecpessoa, dtUltacesso, stTermo, stCadastro, stPessoa, idConvenio, nrFicha, nmConvenio, idPerfil, observacoes, origemPessoa, nrConselho, siglaConselho, ufConselho e indClientePadrao. A data de nascimento dtNascpessoa deve ser exibido no locale do navegador, sem o componente hora. Se hoje for aniversário da pessoa, devemos destacar essa informação. dtCadpessoa e dtUltaltpessoa são respectivamente a data de cadastro e data de atualização, essas informações devem aparecer como nota de rodapé do card do erp, em itálico, fonte menor. Para os campos que ficam, quero aplicar rótulos amigáveis: nmPessoa = nome, nrCpfcnpjpessoa = CPF, nmEndpessoa = logradouro, nrEndpessoa = número, compEndpessoa = complemento, nmBaipessoa = bairro, nmCidpessoa = cidade, ufEndpessoa = UF, nrCeppessoa = CEP, nrTelrespessoa = Telefone residencial, nrTelcelpessoa = Celular, nrTelcompessoa = Telefone comercial, emailPessoa = email, tpSxpessoa = sexo, dtNascpessoa = data nascimento, nmNacpessoa = naturalidade, nrRgpessoa = RG (mover para perto do CPF), dsConvenio = convênio, nrConvenio = carteirinha, nrFicha = prontuário, dsProfissao = profissão, descricaoOrigem = origem. Precisamos expandir os objetos atendimentos e financeiro. Atendimentos: ultimo (quando, comQuem, compareceu) e proximo (quando, comQuem, confirmado com destaque). Financeiro: devedor (destaque em caso verdadeiro), parcelaVencida (data, valor, valorCorrigido), proximaParcela, totalFinanceiro, totalRecebido, totalAberto, totalDevedor. Todas as datas devem respeitar o locale do navegador."

## Clarifications

### Session 2026-09-17

- Q: Should agents have a manual refresh button on the ERP Data card to re-fetch customer data or retry on failure without switching conversations? (FR-011) → A: Include a refresh icon button in the card header to re-fetch data on demand, plus a "Retry" button on error states.
- Q: When an ERP phone search returns multiple customer records matching the contact's phone number, how should the system select which record to display and cache? (FR-006, FR-012) → A: Select and display the first record returned, cache its identifier, and include a visual indicator/badge in the card noting that multiple ERP records match this phone.
- Q: When an agent clicks the manual refresh button on the ERP Data card, how should the system resolve the customer record against the cache? (FR-006, FR-011) → A: Standard lookup: re-fetch via the cached ID (refreshing data and re-verifying phone match); only re-search by phone if phone mismatches or ID lookup fails.
- Q: Should the "ERP Data" accordion section in the contact panel be expanded or collapsed by default when an agent opens a conversation, and where should it be positioned? (FR-010) → A: Expanded (open) by default, positioned immediately below the Chatwoot contact attributes/data section, persisting subsequent open/close toggle preferences in local UI settings.

### Session 2026-09-18 (Field Filtering, Formatting & Sub-objects)

- Q: `nrFicha` was specified both in the list of fields to hide and in the friendly labels list as 'prontuário'. Should `nrFicha` be displayed with the label 'Prontuário' or hidden from the card? (FR-015, FR-016) → A: Display `nrFicha` with the friendly label "Prontuário" in the customer attributes section.
- Q: If the ERP record contains additional fields not included in the friendly label mapping or structured sections, should they be hidden by default or displayed at the bottom with raw keys? (FR-017) → A: Strict whitelist: hide unmapped/extra fields by default so only explicitly curated business fields and structured sections are rendered.
- Q: O que representa exatamente o campo parcelaVencida no objeto financeiro? (FR-021) → A: parcelaVencida representa a parcela vencida mais antiga do cliente (o cliente pode ter múltiplas parcelas em aberto, consolidadas em totalDevedor). A interface deve rotular e exibir claramente como parcela vencida mais antiga ("Parcela vencida mais antiga").
- Q: Should document numbers and telephone fields (CPF/CNPJ, CEP, phone numbers) be formatted with standard punctuation masks or displayed as raw alphanumeric values from the ERP? (FR-016, FR-022) → A: Apply standard Brazilian punctuation masks (CPF/CNPJ, CEP, phone) when digit counts match standard formats, falling back to the raw value if irregular.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Formatted Customer ERP Data Card in Contact Panel (Priority: P1)

As an Agent handling a conversation, when viewing a contact with a registered phone number in an account with an active ERP integration, I want to see an "ERP Data" card in the contact panel displaying the customer's curated data with human-friendly labels, structured sections for personal info, appointments, and financial status, and localized dates, so that I have clear, immediate business context on the customer without clutter or raw database identifiers.

**Why this priority**: This is the primary user-facing experience of Phase 02. Displaying raw database keys (`idPessoa`, `idEmpresa`) and unformatted timestamps causes cognitive overload and errors. Formatting fields with friendly labels, highlighting vital operational states (today's birthday, confirmed appointments, debtor status), and presenting appointments and financial summaries directly empowers agents during customer conversations.

**Independent Test**: Can be tested independently by opening a conversation for a contact whose phone number matches an ERP customer record, and verifying that:
1. Technical IDs and internal flags are omitted.
2. Personal details appear with friendly labels (Nome, CPF, RG adjacent to CPF, endereço, telefones, email, prontuário, etc.).
3. Date of birth displays in the browser's locale without time, with a prominent highlight if today is the contact's birthday.
4. Registration and update timestamps appear as a discreet footnote in italics and smaller font.
5. Appointments (`atendimentos`) display the last and next visits with localized dates, highlighting whether the next visit is confirmed.
6. Financial summary (`financeiro`) displays debtor status with visual highlight when true, plus localized currency amounts for overdue installments and totals.

**Acceptance Scenarios**:

1. **Given** an account with an enabled ERP integration and a contact with a matching ERP record, **When** an agent opens the conversation, **Then** the contact panel displays an "ERP Data" card positioned immediately below contact attributes, expanded by default, displaying curated customer data with friendly labels, without raw technical IDs or unformatted JSON brackets.
2. **Given** an ERP customer record with technical fields (`idPessoa`, `idEmpresa`, `pessoaTipo`, `tpPessoa`, `nmPaispessoa`, `idProfpessoa`, `idUsuario`, `idEspecpessoa`, `dtUltacesso`, `stTermo`, `stCadastro`, `stPessoa`, `idConvenio`, `nmConvenio`, `idPerfil`, `observacoes`, `origemPessoa`, `nrConselho`, `siglaConselho`, `ufConselho`, `indClientePadrao`), **When** rendered in the card, **Then** none of these technical fields appear in the interface.
3. **Given** a customer record with `nrFicha`, **When** rendered, **Then** it is displayed with the friendly label "Prontuário".
4. **Given** an ERP customer record containing unmapped or extra fields not included in the friendly label mapping or structured sections, **When** rendered in the card, **Then** these unmapped fields are omitted from display under the strict whitelist policy.
5. **Given** a customer record with `dtNascpessoa`, **When** rendered, **Then** it displays formatted according to the browser's active locale without time (e.g., `DD/MM/YYYY`), and if today's calendar date matches the contact's day and month of birth, **Then** a visible birthday indicator/badge highlights that it is their birthday today.
6. **Given** a customer record with `dtCadpessoa` and `dtUltaltpessoa`, **When** rendered, **Then** they appear at the bottom of the card as a footnote in italics and smaller font, formatted in the browser's active locale.
7. **Given** a customer record containing `nrCpfcnpjpessoa` and `nrRgpessoa`, **When** rendered in the personal data list, **Then** RG is positioned immediately adjacent to CPF, and document/phone numbers (`nrCpfcnpjpessoa`, `nrCeppessoa`, `nrTelcelpessoa`, `nrTelrespessoa`, `nrTelcompessoa`) are formatted with standard punctuation masks when matching expected digit lengths (falling back to raw values if irregular).
8. **Given** a customer record containing `atendimentos`, **When** rendered, **Then** it presents the last appointment (`ultimo`) with localized date/time, professional name (`comQuem`), and attendance (`compareceu`), and the next appointment (`proximo`) with localized date/time, professional name (`comQuem`), and a highlighted confirmation status (`confirmado`). If `proximo` is null, it displays a clear empty indicator.
9. **Given** a customer record containing `financeiro`, **When** rendered, **Then** debtor status (`devedor`) is prominently highlighted when true, the oldest overdue installment (`parcelaVencida`) is clearly labeled and displayed as the oldest overdue installment ("Parcela vencida mais antiga") with localized date and currency values, and summary totals (`totalFinanceiro`, `totalRecebido`, `totalAberto`, `totalDevedor`) display formatted as currency according to the browser's locale.
10. **Given** an account without any enabled ERP integration, **When** an agent opens any conversation, **Then** no "ERP Data" card appears in the contact panel.
11. **Given** an account with an enabled ERP integration, **When** the external ERP system is temporarily unavailable or returns an error, **Then** the card displays a localized error state with a "Retry" button.
12. **Given** an agent viewing the "ERP Data" card for a contact, **When** the agent clicks the manual refresh icon button in the card header, **Then** the card re-fetches and updates the data in place.
13. **Given** an ERP search that returns multiple customer records matching the contact's phone number, **When** the card renders, **Then** it renders the first customer record and displays an informational badge stating that multiple ERP records match this phone number.

---

### User Story 2 — Contact Link Caching and Automatic Invalidation/Recovery (Priority: P1)

As a System, once a contact is successfully matched to an external person in the ERP, I want to reuse the cached external identifier on subsequent views to perform fast direct lookups, but verify that the record's phone number still matches the contact's phone number, so that customer context is loaded quickly without risk of showing stale or mismatched data if contact details change.

**Why this priority**: Direct identifier lookups are significantly faster and lighter than phone searches. Automatic revalidation with single-retry fallback ensures both optimal performance and 100% data integrity without requiring agent intervention.

**Independent Test**: Can be tested independently by: (a) loading a contact's ERP card a second time with an unchanged phone number to verify that direct identifier lookup is used without repeating the phone search; (b) altering the contact's phone number or changing the remote record to verify that a phone mismatch invalidates the cached identifier, automatically executes a single phone search, and updates the cached link with the newly found customer record.

**Acceptance Scenarios**:

1. **Given** a contact whose ERP person identifier is already cached, **When** the agent opens the conversation and the remote record's phone number matches the contact's phone number, **Then** the system retrieves and displays the customer record using direct identifier lookup without performing a phone search.
2. **Given** a contact with a cached ERP identifier, **When** the remote record returned by identifier lookup has a different phone number than the contact, **Then** the system clears the cached identifier, executes a single phone search, updates the cached identifier with the new match, and displays the refreshed customer record.
3. **Given** a contact with a cached ERP identifier, **When** the direct identifier lookup returns no record, **Then** the system clears the cached identifier, executes a single phone search, and if found, updates the cache and displays the record.
4. **Given** a contact with a cached ERP identifier whose direct lookup fails or mismatches, **When** the fallback phone search also returns no match, **Then** the cached identifier remains cleared and the system displays the "not found" state.
5. **Given** phone number representations with different formatting, spaces, punctuation, or country codes, **When** matching phone numbers, **Then** the comparison normalizes digits and accounts for standard country code prefixes (e.g. `55` for Brazil).

---

### User Story 3 — Friendly Empty State for Contacts Not Found in ERP (Priority: P2)

As an Agent, when opening a conversation for a contact who does not exist in the ERP (or has no phone number), I want to see a clear and friendly empty state explaining that no record was found and suggesting creating the contact in the ERP, so that I understand the status immediately without confusion or seeing broken UI elements.

**Why this priority**: Not all contacts interacting with Chatwoot exist as registered customers in the ERP. A clear empty state distinguishes between an operational failure (network/server error) and a normal business condition (unregistered lead/customer), guiding the agent on appropriate next steps.

**Independent Test**: Can be tested independently by opening conversations for: (a) a contact with a phone number not registered in the ERP; (b) a contact with no phone number registered in Chatwoot. In both cases, verify that the card presents an informative empty state with actionable guidance instead of loading spinners, blank space, or error banners.

**Acceptance Scenarios**:

1. **Given** a contact with a phone number that has no matching customer record in the ERP, **When** the agent views the contact panel, **Then** the "ERP Data" card displays a friendly empty state message indicating that no ERP record was found for this phone number and suggesting registration in the ERP.
2. **Given** a contact with no phone number registered in Chatwoot, **When** the agent views the contact panel in an account with an active ERP integration, **Then** the "ERP Data" card displays an empty state indicating that a phone number is required to locate records in the ERP, without making external API calls.
3. **Given** an empty state displayed in the "ERP Data" card, **When** viewed in different user interface languages, **Then** the explanatory copy is presented in the user's active locale (English or Brazilian Portuguese).

---

### Edge Cases

- **Contact phone number missing or blank**: The system bypasses external API requests entirely and immediately displays the empty state explaining that a phone number is needed.
- **Phone number format variations**: Contacts in Chatwoot store phone numbers in E.164 format, while ERPs may return unformatted national digits. Phone comparisons strip all non-digit characters and retry after stripping country code `55` if needed.
- **Remote ERP downtime or HTTP 5xx responses**: The proxy endpoint returns HTTP 503, and the frontend renders a contained error alert with a retry button without interrupting any other panel sections.
- **Missing or null sub-objects**: If `atendimentos` or `financeiro` is null, missing, or has null nested properties (`proximo: null`, `parcelaVencida: null`, `proximaParcela: null`), the card renders clean empty indicators (e.g., "Nenhum") rather than failing or throwing render errors.
- **Invalid or non-date string in date fields**: If a date field contains an unparseable value or null, the component falls back safely to rendering a dash (`-`) or empty string without raising JavaScript exceptions.
- **Birthday check on leap day (February 29)**: Contacts born on February 29 in non-leap years celebrate their birthday on February 28th according to standard calendar convention.
- **Debtor with zero balance**: If `devedor` is true but `totalDevedor` is zero or null, the debtor warning badge is still displayed based on the boolean flag.
- **Customer with multiple overdue installments**: When a customer has multiple overdue installments, the `financeiro.parcelaVencida` object reflects the oldest overdue installment. The UI clarifies that this is the oldest overdue installment ("Parcela vencida mais antiga"), while `totalDevedor` conveys the consolidated overdue balance.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an account-scoped endpoint to retrieve customer ERP data for a given contact (`GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`).
- **FR-002**: The ERP data endpoint MUST resolve the active, enabled ERP integration hook for the account and delegate retrieval to the corresponding ERP adapter via the ERP adapter factory.
- **FR-003**: If the account has no enabled ERP integration, the ERP data endpoint MUST return a 404 Not Found response.
- **FR-004**: The ERP data endpoint MUST return explicit status responses: `{ status: 'found', data: <customer_payload>, multiple_matches: true/false }` when a record is found, `{ status: 'not_found' }` when no record matches, or HTTP 503 with `{ error: <message> }` on external service failures (logged per FR-005).
- **FR-005**: When an external ERP service fails or raises an API/authentication error, the system MUST log the exception via the platform exception tracker and return an HTTP 503 response without raising uncaught server errors.
- **FR-006**: The system MUST implement a shared resolution algorithm within the base ERP adapter contract (`fetch_data`) enforcing:
  1. Return `not_found` immediately without remote calls if the contact has no phone number.
  2. If a cached external identifier exists on the contact, execute a direct lookup by ID (`find_by_id`).
  3. If found by ID AND the returned phone matches the contact's phone, return the found record.
  4. If the ID lookup fails or phone does not match, clear the cached external identifier and perform a single search by phone (`search_by_phone`).
  5. If found by phone, store the new external identifier from the first record on the contact and return the found record with a multiple matches indicator if more than one record was returned.
  6. If not found by phone, return `not_found`.
- **FR-007**: The system MUST compare phone numbers by extracting digits only, and if an exact digit match fails, retry comparison after stripping country code prefix `55` from the contact phone number.
- **FR-008**: External person identifiers MUST be persisted in the contact's additional attributes under `additional_attributes['external']["#{erp_name.downcase}_id"]` (e.g., `younus_id`).
- **FR-009**: The Younus ERP adapter MUST implement `find_by_id`, `search_by_phone`, and `phone_from` primitives matching the Younus API contracts (`GET /webhook/pessoa` and `GET /webhook/pessoas`).
- **FR-010**: The contact panel in the agent dashboard MUST include an "ERP Data" accordion section positioned immediately below the contact attributes section, rendered only when an enabled ERP integration hook exists for the account, expanded by default upon initial load, and persisting subsequent agent toggle preferences in UI settings.
- **FR-011**: The "ERP Data" card MUST automatically fetch customer data whenever the active conversation/contact changes, and MUST provide a manual refresh icon button in the card header to re-fetch data on demand, plus a "Retry" button in error states.
- **FR-012**: The "ERP Data" card MUST support five distinct visual states: loading, no phone (immediate empty state when contact lacks phone number, bypassing API calls), found, not found, and error.
- **FR-013**: The "ERP Data" card MUST NOT provide contact creation/mutation actions or outbound writes to the ERP in this phase.
- **FR-014**: All user-facing strings, headers, labels, badges, empty state messages, and error descriptions MUST be fully localized in both English (`en.json`, `en.yml`) and Brazilian Portuguese (`pt_BR.json`, `pt_BR.yml`).
- **FR-015**: **Excluded Technical Fields**: The system MUST hide and exclude the following internal ERP technical fields and flags from display in the contact panel card: `idPessoa`, `idEmpresa`, `pessoaTipo`, `tpPessoa`, `nmPaispessoa`, `idProfpessoa`, `idUsuario`, `idEspecpessoa`, `dtUltacesso`, `stTermo`, `stCadastro`, `stPessoa`, `idConvenio`, `nmConvenio`, `idPerfil`, `observacoes`, `origemPessoa`, `nrConselho`, `siglaConselho`, `ufConselho`, and `indClientePadrao`.
- **FR-016**: **Friendly Labels & Ordering**: For remaining customer person attributes, the system MUST display human-friendly localized labels and logical ordering:
  - `nmPessoa` → "Nome"
  - `nrCpfcnpjpessoa` → "CPF"
  - `nrRgpessoa` → "RG" (positioned immediately adjacent/next to CPF)
  - `nmEndpessoa` → "Logradouro"
  - `nrEndpessoa` → "Número"
  - `compEndpessoa` → "Complemento"
  - `nmBaipessoa` → "Bairro"
  - `nmCidpessoa` → "Cidade"
  - `ufEndpessoa` → "UF"
  - `nrCeppessoa` → "CEP"
  - `nrTelrespessoa` → "Telefone residencial"
  - `nrTelcelpessoa` → "Celular"
  - `nrTelcompessoa` → "Telefone comercial"
  - `emailPessoa` → "Email"
  - `tpSxpessoa` → "Sexo" (rendered as trimmed value, e.g. "M", "F", or custom)
  - `dtNascpessoa` → "Data de nascimento"
  - `nmNacpessoa` → "Naturalidade"
  - `dsConvenio` → "Convênio"
  - `nrConvenio` → "Carteirinha"
  - `nrFicha` → "Prontuário"
  - `dsProfissao` → "Profissão"
  - `descricaoOrigem` → "Origem"
- **FR-017**: **Strict Whitelist Display Policy**: The system MUST enforce a strict whitelist display policy; any customer attributes in the ERP payload not explicitly included in the friendly label mapping or structured sub-objects (or those with null/empty values) MUST be omitted from display.
- **FR-018**: **Date of Birth & Birthday Highlight**: The system MUST format `dtNascpessoa` using the browser's active locale without time component (e.g., `DD/MM/YYYY`). When the contact's birth date (day and month) matches the current calendar date (today is their birthday), the system MUST display a prominent visual highlight/badge marking the birthday.
- **FR-019**: **Audit Footnotes**: The system MUST render `dtCadpessoa` ("Data de cadastro") and `dtUltaltpessoa` ("Data de atualização") as footnote items at the bottom of the card in italics and smaller font, formatted according to the browser's active locale.
- **FR-020**: **Appointments Sub-object (`atendimentos`)**: The system MUST render a dedicated structured section for appointments:
  - `ultimo`: localized appointment date/time, attending professional (`comQuem`), and attendance status (`compareceu`).
  - `proximo`: localized appointment date/time, scheduled professional (`comQuem`), and confirmation status (`confirmado`) with a prominent visual highlight indicating whether the patient has confirmed attendance. If null, display a friendly indicator ("Nenhum agendamento futuro").
- **FR-021**: **Financial Sub-object (`financeiro`)**: The system MUST render a dedicated structured section for financial status:
  - `devedor`: boolean indicator with a prominent visual highlight (warning badge/tag) when true.
  - `parcelaVencida`: represents the oldest overdue installment (a customer may have multiple overdue installments reflected in `totalDevedor`); if present, display labeled clearly as the oldest overdue installment ("Parcela vencida mais antiga"), showing localized due date, original value (`valor`), and corrected value (`valorCorrigido`) formatted as currency in the browser's locale; if null, display a friendly indicator ("Nenhuma").
  - `proximaParcela`: if present, localized due date and value formatted as currency; if null, display a friendly indicator ("Nenhuma").
  - Financial totals: summary values (`totalFinanceiro`, `totalRecebido`, `totalAberto`, `totalDevedor`) formatted as currency in the browser's active locale.
- **FR-022**: **Locale and Value Formatting Consistency**: ALL dates, times, and currency values across the ERP Data card MUST be formatted in accordance with the user's browser active locale. In addition, standard Brazilian punctuation masks MUST be applied to document and telephone fields (`nrCpfcnpjpessoa` as CPF `000.000.000-00` or CNPJ `00.000.000/0000-00`, `nrCeppessoa` as `00000-000`, and `nrTelcelpessoa`/`nrTelrespessoa`/`nrTelcompessoa` as `(00) 00000-0000` or `(00) 0000-0000`) whenever digit counts match standard lengths, safely falling back to raw alphanumeric strings when irregular.

### Key Entities

- **Contact**: The core conversation participant in Chatwoot whose phone number is used as the lookup key and whose additional attributes store the cached external ERP identifier.
- **ERP Integration Hook**: The account-level record identifying the enabled ERP provider and holding its authentication credentials.
- **ERP Adapter**: The provider-specific adapter executing remote API calls against the target ERP system (`find_by_id`, `search_by_phone`, `phone_from`) under the common base contract (`fetch_data`).
  - **ERP Customer Record**: The readonly customer data object returned by the ERP (Younus person record), containing personal fields, `atendimentos` sub-object, and `financeiro` sub-object (where `parcelaVencida` represents the oldest overdue installment).
- **ERP Data Card**: The frontend dashboard component in the contact sidebar responsible for requesting, curating, and presenting customer ERP data, appointments, and financial information.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Agents viewing a contact with a matching ERP record see the customer data card loaded and rendered in under 2 seconds (measured via end-to-end performance scenario with mocked remote ERP latency <= 200ms).
- **SC-002**: 100% of subsequent card views for the same contact with an unchanged phone number utilize the cached identifier lookup, eliminating redundant phone searches.
- **SC-003**: 100% of phone number changes or stale cached links automatically self-heal via single phone search fallback without manual cache clearing or agent intervention.
- **SC-004**: 0% of external ERP downtime or API errors cause contact panel crashes or conversation thread blocking.
- **SC-005**: 100% of contacts without matching ERP records or without phone numbers display an actionable empty state rather than error banners, blank cards, or broken output.
- **SC-006**: 0% of accounts without an enabled ERP integration display the ERP card or make proxy endpoint requests.
- **SC-007**: 100% of user-facing UI labels, statuses, and messages are available synchronously in English and Brazilian Portuguese.
- **SC-008**: 100% of the specified technical IDs and internal ERP flags are excluded from the card view.
- **SC-009**: 100% of contacts viewing the card on their birthday display the birthday highlight indicator.
- **SC-010**: 100% of appointment confirmation and debtor states reflect their highlighted visual indicator when true.
- **SC-011**: 100% of date fields and financial amounts render in the user's active browser locale format without raw ISO timestamp strings or unformatted floats, and 100% of valid CPF/CNPJ, CEP, and phone numbers render with standard punctuation masks.

## Assumptions

- **Read-only display for v1**: In this phase, ERP data is displayed as an organized, curated set of sections without in-place editing or outbound mutations to the ERP.
- **Single active ERP provider per account**: Each account has at most one active ERP integration enabled at any given time; the proxy endpoint resolves that active provider.
- **Search key is phone number**: Phone number is the universal customer matching key between Chatwoot contacts and ERP customer records.
- **Outbound creation is out of scope**: The empty state guides agents that the contact is not in the ERP, but creating the customer in the ERP remains an external action performed directly in the ERP system.
- **No real-time ERP push**: Changes in the external ERP do not trigger websocket pushes to Chatwoot; data is fetched on-demand upon conversation selection or manual refresh.
- **Currency formatting**: Currency formatting automatically adapts to the browser locale and ERP currency (defaulting to Brazilian Real `BRL` / `R$` for Younus ERP data).
- **Unmapped/empty fields**: Attributes that are null, undefined, or empty string in the customer record are omitted from the display to maintain a concise, clean sidebar.
