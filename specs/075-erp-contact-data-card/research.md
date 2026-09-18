# Phase 0 Research: ERP Contact Panel Data Card

**Branch**: `075-erp-contact-data-card`
**Date**: 2026-09-18
**Spec**: [spec.md](./spec.md)

---

## Research Topics & Decisions

### 1. External ID Caching, Resolution Algorithm, and Stale Link Recovery

- **Context**: Agents viewing contacts in conversations need customer ERP data loaded automatically. Direct ID lookups are faster and lighter than searching by phone across records, but contact phone numbers or remote records can change.
- **Decision**: Implement a concrete resolution algorithm in `Erp::BaseAdapter#fetch_data(contact)` modeled on `Crm::BaseProcessorService` and `Crm::Leadsquared::ProcessorService#with_stale_lead_recovery`:
  1. Return `{ status: 'not_found' }` immediately without making remote HTTP calls if `contact.phone_number.blank?`.
  2. If `contact.additional_attributes.dig('external', "#{erp_name.downcase}_id")` exists, invoke `find_by_id(cached_id)`.
  3. If record is found by ID and `phone_matches?(contact, record)`, return `{ status: 'found', data: record, multiple_matches: false }`.
  4. If ID lookup returns `nil` (or record phone does not match), clear cached identifier (`clear_external_id(contact)`) and perform a single search by phone: `search_by_phone(contact.phone_number)`.
  5. If found by phone, store the new identifier on `contact` (`store_external_id(contact, new_id)`) and return `{ status: 'found', data: first_record, multiple_matches: multiple_count > 1 }`.
  6. If not found by phone, return `{ status: 'not_found' }`.
- **Rationale**:
  - Centralizing the caching, phone validation, and single-retry fallback logic in `Erp::BaseAdapter` ensures provider-agnostic reuse. Future ERP adapters (e.g., SAP, Totvs, Bling) only need to implement three primitive methods: `find_by_id(id)`, `search_by_phone(phone)`, and `phone_from(data)`.
  - Storing the external ID under `contact.additional_attributes['external']["#{erp_name.downcase}_id"]` conforms to existing Chatwoot conventions (e.g., `leadsquared_id` in `Crm::BaseProcessorService`).
  - Automatic invalidation and single phone search recovery prevents stale data contamination when customer records are merged, re-keyed, or phone numbers are updated.
- **Alternatives Considered**:
  - *Always search by phone*: Rejected because phone queries on external ERPs can be expensive, unindexed, or rate-limited; ID lookups are direct primary-key queries.
  - *Cache indefinitely without phone verification*: Rejected because phone numbers can be re-assigned or edited in Chatwoot or the ERP, leading to privacy and data accuracy leaks.
  - *Duplicate resolution logic inside each adapter*: Rejected because caching, fallback rules, and attribute updates are invariant across ERP providers.

---

### 2. Phone Number Comparison & Country Code Normalization

- **Context**: Contacts in Chatwoot typically store phone numbers in E.164 format (e.g., `+5541996937898` or `+5511987654321`), while the Younus ERP webhook API stores and expects unformatted digits without the country code (e.g., `41996937898` or `11987654321`).
- **Decision**: Implement `phone_matches?(contact, erp_data)` and query normalization in `Erp::BaseAdapter`:
  1. Extract digits only from both strings: `contact_digits = contact.phone_number.to_s.gsub(/\D/, '')` and `erp_digits = phone_from(erp_data).to_s.gsub(/\D/, '')`.
  2. If exact digits match (`contact_digits == erp_digits`), return `true`.
  3. If `contact_digits` starts with `55` (Brazil country code) and stripping `55` matches `erp_digits` (`contact_digits.sub(/^55/, '') == erp_digits`), return `true`.
  4. If `erp_digits` starts with `55` and stripping `55` matches `contact_digits`, return `true`.
  5. Otherwise, return `false`.
  6. When passing phone to `search_by_phone(phone)`, extract digits and strip leading `55` if length corresponds to standard Brazilian mobile/landline numbers (12-13 digits starting with 55).
- **Rationale**:
  - Prevents false-negative mismatches caused purely by international prefix formatting.
  - Keeps matching resilient against different phone formats in external records (formatted vs unformatted).
- **Alternatives Considered**:
  - *Full libphonenumber parsing*: Unnecessary dependency overhead for national ERP lookups where digit stripping with standard country prefix fallback is 100% sufficient and fast.
  - *Exact string equality*: Rejected because `+5541996937898` would never match `"41996937898"`, breaking lookups.

---

### 3. Younus Remote Webhook API Primitives (`find_by_id` & `search_by_phone`)

- **Context**: Younus provides webhook endpoints for person queries: `GET /webhook/pessoas` (search by phone, plural) and `GET /webhook/pessoa` (search by ID, singular).
- **Decision**:
  - In `Erp::Younus::Client`:
    - Implement `find_by_id(external_id)`: Issues `GET /webhook/pessoa?idEmpresa=<id>&idPessoa=<id>` with header `token: <token>`. Parses `dados[0]['json']` on `sucesso: true`, returns `nil` on `sucesso: false`.
    - Enhance `search_by_phone(phone)`: Issues `GET /webhook/pessoas?idEmpresa=<id>&nrTelcelpessoa=<phone>` with header `token: <token>`. Returns `dados` array or `{ record: dados[0]['json'], multiple_matches: dados.length > 1 }` or supports returning records with count.
  - In `Erp::Younus::Adapter`:
    - `self.erp_name`: `'Younus'`.
    - `find_by_id(external_id)`: calls `client.find_by_id(external_id)`.
    - `search_by_phone(phone)`: calls `client.search_by_phone(sanitized_phone)`, extracts first record and multiple match flag.
    - `phone_from(data)`: extracts `data['nr_telcelpessoa'] || data['nrTelcelpessoa'] || data['telefone']`.
    - `external_id_from(data)`: extracts `data['cd_pessoa'] || data['idPessoa'] || data['id_pessoa']`.
- **Rationale**:
  - Follows Younus API specifications verified during Phase 01 (`074-erp-integration-foundation`).
  - Separates HTTP transport / response handling (`Client`) from adapter business primitives (`Adapter`).
- **Alternatives Considered**:
  - *Inline HTTP calls in Adapter*: Rejected to maintain client separation, timeout configuration, and exception mapping established in Phase 01.

---

### 4. Account-Scoped Controller & Routing

- **Context**: The frontend needs an account-scoped endpoint to fetch ERP customer data for a given contact without exposing provider-specific credentials or URLs.
- **Decision**:
  - Route: `GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`
  - Controller: `Api::V1::Accounts::Integrations::ErpController < Api::V1::Accounts::Integrations::BaseController` located in `custom/app/controllers/api/v1/accounts/integrations/erp_controller.rb`.
  - Logic:
    1. Authenticate user session (inherits from `BaseController`).
    2. Resolve active enabled ERP hook: `Current.account.hooks.enabled.find(&:erp_integration?)`. Return HTTP 404 `{ error: 'ERP integration not found or not enabled' }` if missing.
    3. Resolve contact: `Current.account.contacts.find_by(id: params[:contact_id])`. Return HTTP 404 `{ error: 'Contact not found' }` if missing.
    4. Delegate to adapter: `adapter = Erp::AdapterFactory.build(hook)`. Call `adapter.fetch_data(contact)`.
    5. Render JSON status: `{ status: 'found', data: ..., multiple_matches: ... }` or `{ status: 'not_found' }` with HTTP 200.
    6. Rescue `Erp::AuthenticationError` and `Erp::ApiError`: capture exception via `ChatwootExceptionTracker.new(e, account: Current.account).capture_exception`, return HTTP 503 `{ error: e.message }`.
- **Rationale**:
  - Provider-agnostic API contract: the frontend never knows whether Younus or another ERP is connected.
  - Structured 3-state payload (`found`, `not_found`, HTTP 503 `error`) simplifies frontend state machines and removes ambiguous `null` checks.
  - Clean placement in `custom/` preserves upstream compatibility (Principle I).
- **Alternatives Considered**:
  - *Passing provider name in query param (`?provider=younus`)*: Rejected because the account has one active ERP integration at a time; the backend resolves the configured provider automatically.
  - *Returning HTTP 404 on customer not found*: Rejected because a contact not yet existing in the ERP is a normal, successful business query (`{ status: 'not_found' }`), not an API routing or resource resolution failure.

---

### 5. Frontend Architecture & Contact Panel Integration

- **Context**: The contact sidebar in `ContactPanel.vue` needs an "ERP Data" accordion section placed directly below contact attributes, expanded by default on initial load, persisting subsequent toggle preferences in UI settings, and re-fetching on contact changes or manual refresh.
- **Decision**:
  - Create component `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`.
  - Create API client `app/javascript/dashboard/api/integrations/erp.js` extending `ApiClient`.
  - Add store getter `getEnabledErpIntegration` in `app/javascript/dashboard/store/modules/integrations.js` to detect whether an ERP app with `category: 'erp'` has an enabled hook.
  - Add `{ name: 'erp_data' }` to `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` in `app/javascript/dashboard/composables/useUISettings.js`, positioned immediately after `{ name: 'contact_attributes' }`.
  - Update `isContactSidebarItemOpen(key, defaultValue = false)` to support default open state (`uiSettings.value[key] ?? defaultValue`) so that `is_erp_data_open` defaults to `true`.
  - In `ContactPanel.vue`, render `<AccordionItem>` with title `$t('CONVERSATION_SIDEBAR.ACCORDION.ERP_DATA')` when `element.name === 'erp_data' && isErpIntegrationEnabled`.
  - Provide a refresh button in the accordion header slot `#button` triggering manual re-fetch, and a "Retry" button on error states.
- **Rationale**:
  - Follows existing `ShopifyOrdersList.vue` and `ContactOpportunities.vue` integration patterns in `ContactPanel.vue`.
  - Respects user accordion drag reordering while ensuring default placement immediately below contact attributes.
  - Accordion preference persists automatically via existing `toggleSidebarUIState('is_erp_data_open', value, true)`.
- **Alternatives Considered**:
  - *Hardcoding ERP section in ContactPanel outside Draggable*: Rejected because all accordion items in `ContactPanel.vue` participate in the reorderable list via `conversationSidebarItemsOrder`.
  - *Full page reload for refresh*: Rejected because agent workflow requires instant, localized refresh without interrupting the active conversation.

---

### 6. Field Whitelist, Ordering, and Friendly Labels (FR-015, FR-016, FR-017)

- **Context**: The raw ERP customer payload contains technical identifiers, database keys, and flags (`idPessoa`, `idEmpresa`, `stTermo`, etc.) that cause cognitive noise for agents. Furthermore, the clarification sessions specified a strict whitelist policy where unmapped or extra fields must be hidden by default.
- **Decision**:
  - Define an explicit ordered whitelist of customer attributes with their i18n label keys:
    1. `nmPessoa`: "Nome" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_PESSOA`)
    2. `nrCpfcnpjpessoa`: "CPF" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_CPFCNPJPESSOA`)
    3. `nrRgpessoa`: "RG" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_RGPESSOA`) — positioned immediately adjacent to CPF
    4. `nmEndpessoa`: "Logradouro" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_ENDPESSOA`)
    5. `nrEndpessoa`: "Número" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_ENDPESSOA`)
    6. `compEndpessoa`: "Complemento" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.COMP_ENDPESSOA`)
    7. `nmBaipessoa`: "Bairro" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_BAIPESSOA`)
    8. `nmCidpessoa`: "Cidade" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_CIDPESSOA`)
    9. `ufEndpessoa`: "UF" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.UF_ENDPESSOA`)
    10. `nrCeppessoa`: "CEP" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_CEPPESSOA`)
    11. `nrTelrespessoa`: "Telefone residencial" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELRESPESSOA`)
    12. `nrTelcelpessoa`: "Celular" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELCELPESSOA`)
    13. `nrTelcompessoa`: "Telefone comercial" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELCOMPESSOA`)
    14. `emailPessoa`: "Email" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.EMAIL_PESSOA`)
    15. `tpSxpessoa`: "Sexo" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.TP_SXPESSOA`)
    16. `dtNascpessoa`: "Data de nascimento" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.DT_NASCPESSOA`)
    17. `nmNacpessoa`: "Naturalidade" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_NACPESSOA`)
    18. `dsConvenio`: "Convênio" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.DS_CONVENIO`)
    19. `nrConvenio`: "Carteirinha" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_CONVENIO`)
    20. `nrFicha`: "Prontuário" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_FICHA`) — clarified: displayed as Prontuário, NOT hidden
    21. `dsProfissao`: "Profissão" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.DS_PROFISSAO`)
    22. `descricaoOrigem`: "Origem" (`CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.DESCRICAO_ORIGEM`)
  - Enforce explicit exclusion of technical keys: `idPessoa`, `idEmpresa`, `pessoaTipo`, `tpPessoa`, `nmPaispessoa`, `idProfpessoa`, `idUsuario`, `idEspecpessoa`, `dtUltacesso`, `stTermo`, `stCadastro`, `stPessoa`, `idConvenio`, `nmConvenio`, `idPerfil`, `observacoes`, `origemPessoa`, `nrConselho`, `siglaConselho`, `ufConselho`, `indClientePadrao`.
  - Filter logic: iterate strictly over the defined whitelist order; for each key, if the key exists in `customerData` and its value is non-empty / non-null (excluding whitespace strings), render the row with the localized label and formatted value. Any unmapped keys in `customerData` (or structured sub-objects handled in dedicated sections) are ignored.
- **Rationale**:
  - Directly fulfills FR-015, FR-016, and FR-017.
  - Strict whitelist guarantees that unexpected raw backend database fields or future API additions never leak unformatted into the agent interface.
  - Logical ordering groups identification (Name, CPF, RG), address (Street, Number, Complement, District, City, UF, CEP), contact methods (Phones, Email), and medical/convenio details (`nrFicha`, `dsConvenio`, `nrConvenio`).
- **Alternatives Considered**:
  - *Blacklist-only filter*: Rejected because new or unmapped ERP fields would still leak through with raw keys.
  - *Dynamic key-value rendering with regex formatting*: Rejected in favor of curated domain labels.

---

### 7. Date of Birth & Birthday Highlight Logic (FR-018)

- **Context**: `dtNascpessoa` represents the customer's birth date. Agents need to know if today is the customer's birthday to provide personalized relationship building.
- **Decision**:
  - Date parsing & formatting:
    - Parse `dtNascpessoa` (typically ISO string `YYYY-MM-DD` or `YYYY-MM-DDTHH:mm:ss`).
    - Extract year, month, day. Formatted display: localized date string without time component (`Intl.DateTimeFormat(locale, { day: '2-digit', month: '2-digit', year: 'numeric' })` or `toLocaleDateString()`). Fall back to raw string or `-` if unparseable.
  - Birthday calculation:
    - Get today's local date (month `0-11` and day `1-31`).
    - If `birthMonth === todayMonth && birthDay === todayDay`, `isBirthdayToday` is `true`.
    - Leap day handling: if birth date is February 29 and the current year is not a leap year, match on March 1st (or February 28th per convention).
  - Visual highlight:
    - When `isBirthdayToday` is `true`, render a prominent birthday badge alongside the birth date or at the top of the personal data section (e.g. `🎂 Aniversariante hoje` / `Birthday today` with `bg-n-brand/10 text-n-brand border border-n-brand/20 rounded-full px-2 py-0.5 text-xs font-semibold`).
- **Rationale**:
  - Meets FR-018 and SC-009.
  - Avoids time zone shifts (UTC vs local) by extracting date components directly or using local calendar date.
- **Alternatives Considered**:
  - *Showing birthday only as an attribute value*: A distinct badge provides immediate visual recognition for agents during fast-paced calls/chats.

---

### 8. Brazilian Document and Telephone Punctuation Masking (FR-022)

- **Context**: Brazilian documents (CPF, CNPJ, CEP) and phone numbers are easier for agents to read and verify when formatted with standard punctuation masks.
- **Decision**:
  - Implement reusable masking helpers:
    - **CPF/CNPJ** (`nrCpfcnpjpessoa`):
      - Strip non-digits.
      - If 11 digits: apply CPF mask `###.###.###-##` (`digits.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4')`).
      - If 14 digits: apply CNPJ mask `##.###.###/####-##` (`digits.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, '$1.$2.$3/$4-$5')`).
      - Otherwise: return raw value.
    - **CEP** (`nrCeppessoa`):
      - Strip non-digits.
      - If 8 digits: apply CEP mask `#####-###` (`digits.replace(/(\d{5})(\d{3})/, '$1-$2')`).
      - Otherwise: return raw value.
    - **Phone Numbers** (`nrTelcelpessoa`, `nrTelrespessoa`, `nrTelcompessoa`):
      - Strip non-digits. If begins with `55` and length is 12-13 digits, optionally strip `55` for national display:
      - If 11 digits (mobile with 9): `(##) #####-####` (`digits.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3')`).
      - If 10 digits (landline): `(##) ####-####` (`digits.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3')`).
      - Otherwise: return raw value.
- **Rationale**:
  - Fulfills FR-022 and SC-011.
  - Safe fallback preserves irregular foreign documents or non-standard inputs without breaking or throwing.
- **Alternatives Considered**:
  - *External masking library*: Hand-crafted regex masks are lightweight, require no external npm dependency, and handle all specified Brazilian formats with zero bundle overhead.

---

### 9. Appointments Sub-object (`atendimentos`) Presentation (FR-020)

- **Context**: The ERP payload includes an `atendimentos` sub-object containing `ultimo` (last visit) and `proximo` (next visit).
- **Decision**:
  - Create a dedicated structured section within the card with header: `$t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.TITLE')` ("Atendimentos").
  - **`ultimo` (Last Appointment)**:
    - Date & Time: formatted with browser locale (`DD/MM/YYYY HH:mm`).
    - Attending Professional (`comQuem`): displayed with label "Com" or "Profissional".
    - Attendance status (`compareceu`): badge or text indicator (e.g. "Compareceu" / "Não compareceu" or boolean label).
    - If null or empty: display `$t('CONVERSATION_SIDEBAR.ERP_DATA.EMPTY_VALUE')` ("Nenhum").
  - **`proximo` (Next Appointment)**:
    - Date & Time: formatted with browser locale (`DD/MM/YYYY HH:mm`).
    - Scheduled Professional (`comQuem`).
    - Confirmation status (`confirmado`):
      - When `confirmado === true` (or truthy): render prominent confirmation badge (`bg-n-teal-3 text-n-teal-11 border border-n-teal-6 rounded px-1.5 py-0.5 text-xs font-medium`).
      - When false: render unconfirmed badge/indicator (`bg-n-slate-3 text-n-slate-11 rounded px-1.5 py-0.5 text-xs`).
    - If null or empty: display friendly empty indicator ("Nenhum agendamento futuro" / "Nenhum").
- **Rationale**:
  - Fulfills FR-020 and SC-010.
  - Clearly differentiates operational history (past visit) from actionable future events (confirmed/unconfirmed next appointment).
- **Alternatives Considered**:
  - *Listing as raw key-value lines*: Rejected because nested appointment objects require contextual grouping and status highlights.

---

### 10. Financial Sub-object (`financeiro`) Presentation (FR-021)

- **Context**: The ERP payload includes a `financeiro` sub-object with debtor status (`devedor`), oldest overdue installment (`parcelaVencida`), next installment (`proximaParcela`), and summary totals (`totalFinanceiro`, `totalRecebido`, `totalAberto`, `totalDevedor`).
- **Decision**:
  - Create a dedicated structured section with header: `$t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.TITLE')` ("Financeiro").
  - **Debtor Status (`devedor`)**:
    - When `true`: prominent warning badge at the top of the financial section (`bg-n-ruby-3 text-n-ruby-11 border border-n-ruby-6 rounded px-2 py-0.5 text-xs font-semibold flex items-center gap-1`).
    - Even if `totalDevedor` is 0 or null, badge displays if `devedor === true` (per edge case in spec).
  - **Oldest Overdue Installment (`parcelaVencida`)**:
    - Per clarification session: `parcelaVencida` represents the *oldest overdue installment* ("Parcela vencida mais antiga").
    - Display label: `$t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.OLDEST_OVERDUE_INSTALLMENT')` ("Parcela vencida mais antiga").
    - Display due date (`dtVencimento`), original amount (`valor`), and corrected amount (`valorCorrigido` with penalties/interest if present), formatted as currency in the browser locale (e.g. `Intl.NumberFormat(locale, { style: 'currency', currency: 'BRL' })`).
    - If null: display friendly empty indicator ("Nenhuma").
  - **Next Installment (`proximaParcela`)**:
    - Display due date and value formatted as currency.
    - If null: display friendly indicator ("Nenhuma").
  - **Financial Summary Totals**:
    - Compact grid or list displaying summary metrics:
      - `totalFinanceiro`: "Total contratado / financeiro"
      - `totalRecebido`: "Total recebido"
      - `totalAberto`: "Total em aberto"
      - `totalDevedor`: "Total devedor / vencido" (highlighted if > 0)
    - All formatted via `Intl.NumberFormat` with browser locale and currency code (defaulting to `BRL`).
- **Rationale**:
  - Fulfills FR-021 and clarification session decisions regarding `parcelaVencida` representing the oldest overdue installment while `totalDevedor` reflects consolidated debt.
  - Formatted currency eliminates raw float formatting issues (e.g. `150.5` -> `R$ 150,50`).
- **Alternatives Considered**:
  - *Full table of all installments*: Out of scope for Phase 02; summarized view with oldest overdue installment gives agents instant risk assessment.

---

### 11. Audit Footnotes (`dtCadpessoa` and `dtUltaltpessoa`) (FR-019)

- **Context**: `dtCadpessoa` ("Data de cadastro") and `dtUltaltpessoa` ("Data de atualização") are metadata fields indicating when the customer was created and last updated in the ERP.
- **Decision**:
  - Omit `dtCadpessoa` and `dtUltaltpessoa` from the main attribute list.
  - Render them at the very bottom of the card as a subtle footnote in italics and smaller font (`text-[10px] text-n-slate-10 italic flex flex-col gap-0.5 pt-2 border-t border-n-weak`).
  - Format timestamps in the browser's active locale (e.g. `DD/MM/YYYY HH:mm` or localized format).
- **Rationale**:
  - Fulfills FR-019.
  - Keeps operational audit data accessible without taking prime visual space in the customer details section.
- **Alternatives Considered**:
  - *Hiding audit dates completely*: Audit dates help agents know if customer data is up to date or legacy.

---

### 12. TDD Strategy and Verification Framework

- **Context**: Constitution Principle VI mandates that every behavior change is driven by a test that failed first.
- **Decision**:
  - **Backend (RSpec)**:
    1. Unit tests for `Erp::BaseAdapter#fetch_data` covering all 6 resolution paths:
       - Contact without phone number -> `{ status: 'not_found' }`.
       - Valid cached ID with matching phone -> direct lookup used, no phone search.
       - Cached ID phone mismatch -> cache cleared, phone search invoked, new ID stored.
       - Cached ID returns not found -> cache cleared, phone search invoked.
       - Phone search finds multiple records -> first record returned, `multiple_matches: true`, new ID stored.
       - Phone search finds nothing -> `{ status: 'not_found' }`.
    2. Phone normalization tests for `Erp::BaseAdapter#phone_matches?` (E.164, local digits, Brazilian 55 prefix).
    3. Unit tests for `Erp::Younus::Client` and `Erp::Younus::Adapter`.
    4. Request spec for `Api::V1::Accounts::Integrations::ErpController#data` (authentication, hook resolution, contact resolution, success found, multiple matches, not found, 503 service unavailable).
  - **Frontend (Vitest)**:
    1. Unit tests for `integrations.js` store getter `getEnabledErpIntegration`.
    2. Unit tests for `useUISettings.js` default order and default open state.
    3. Comprehensive component tests for `ErpDataCard.vue`:
       - Loading, No Phone, Not Found, Error states.
       - Whitelist filtering: technical fields excluded, unmapped fields excluded, whitelisted fields rendered with friendly labels.
       - Punctuation masks: CPF, CNPJ, CEP, phone numbers formatted.
       - Date of birth formatting and birthday highlight badge.
       - Audit footnotes at card bottom in italics.
       - Appointments sub-object: last appointment, next appointment, confirmation badge, empty indicator.
       - Financial sub-object: debtor highlight badge, oldest overdue installment (`parcelaVencida`) labeled and formatted, next installment, financial totals formatted as currency.
       - Multiple matches badge when `multiple_matches: true`.
       - Manual refresh and retry actions.
- **Rationale**:
  - Complete alignment with Constitution Principles VI, VII, VIII, and IX.
  - Ensures robust mutation resistance across every user scenario in `spec.md`.
