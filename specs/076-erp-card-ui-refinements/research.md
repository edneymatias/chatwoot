# Research: ERP Contact Card UI Refinements

**Branch**: `076-erp-card-ui-refinements` | **Spec**: [spec.md](./spec.md)

## Summary of Decisions

This document captures the architectural and design decisions for refining the frontend ERP Contact Card (`ErpDataCard.vue`) in the agent conversation sidebar.

---

## 1. Consolidated Single-Line Address Composition

### Decision
Implement a pure presentation helper/computed property `formatAddress(customerData)` that composes the discrete ERP address fields (`nmEndpessoa`, `nrEndpessoa`, `compEndpessoa`, `nmBaipessoa`, `nmCidpessoa`, `ufEndpessoa`, `nrCeppessoa`) into a single "Endereço" attribute entry following the pattern:
`{logradouro}, {número}[, {complemento}], {bairro}, {cidade}/{uf} - {cep}`

The individual fields are excluded from `WHITELIST_FIELDS` so they never render as separate rows. When all address fields are absent or whitespace-only, the "Endereço" attribute row is completely omitted.

### Rationale
- **Vertical economy**: Reduces up to 7 separate rows down to 1 consolidated line, freeing ~70% vertical space in the narrow 280px–360px sidebar.
- **Syntactic safety**: Missing components (such as complement, number, or neighborhood) are pruned dynamically using array filtering so that leading commas, double commas (`, ,`), or dangling hyphens (`- `) are impossible.
- **Standardized masking**: Standard Brazilian CEP masking (`00000-000`) is applied to `nrCeppessoa` when formatted.
- **Standalone CEP handling**: If only the CEP is present without any preceding street or city elements, the hyphen prefix is omitted, rendering just the formatted CEP.

### Alternatives Considered
- *Multi-line grouped address block*: Keeping address fields in a dedicated card box. Rejected because the user explicit requirement is to condense the address into a single line to save vertical space.
- *Backend-side address concatenation*: Concatenating address in Rails or Younus adapter. Rejected because upstream API contract remains raw/canonical and other clients or future export features may require discrete fields. Presentation formatting belongs in the UI layer.

---

## 2. Primary Phone Selection and Inline Disclosure Accordion

### Decision
Synthesize a single primary phone row from `nrTelcelpessoa` (Celular), `nrTelrespessoa` (Residencial), and `nrTelcompessoa` (Comercial) based on priority:
1. `nrTelcelpessoa` (Celular / Mobile phone) is the default primary channel.
2. If absent, fall back to `nrTelrespessoa` (Residencial), then `nrTelcompessoa` (Comercial).
3. If more than one phone exists across the 3 fields, render an inline ellipsis toggle button (`...`) adjacent to the primary phone number.
4. Clicking `...` toggles an inline accordion/expansion that renders the secondary phone rows directly within the customer attributes list with their respective type labels and phone masks.
5. Clicking `...` again collapses back to the primary phone.
6. The expansion state is local reactive state (`isPhonesExpanded = ref(false)`), resetting to `false` when switching contacts.

### Rationale
- **Prioritizes cell phones**: Agents interact with contacts predominantly via cell phone/WhatsApp. Displaying home and work phones on every load wastes vertical space.
- **Zero data loss**: Secondary numbers remain immediately accessible in 1 click without leaving the conversation view or opening a modal.
- **Inline harmony**: Expanding directly within the attributes list maintains key-value column alignment without awkward popup overlays or floating menus that can overflow the sidebar.

### Alternatives Considered
- *Hover tooltip / popover for secondary phones*: Hover does not work on touch devices and popovers clip on narrow sidebars or require absolute z-index layering.
- *Modal dialog for all phones*: Modals disrupt agent conversational workflow for reading a simple alternate phone number.
- *Leaving 3 separate rows*: Wastes 2 full rows on contacts with secondary phones, causing clutter.

---

## 3. Integrated Appointments Presentation (Clean List)

### Decision
Replace the dark stacked container boxes (`p-2 mb-2 rounded bg-n-alpha-1 border border-n-weak`) in the `atendimentos` section with an integrated, clean key-value list styled identically to customer attributes.
- **Último atendimento**:
  - Displays localized date/time (`formatDateTime`), attending professional (`comQuem`) if present, and a subtle status badge (`Compareceu` / `Não compareceu`).
  - If null, displays subtle empty indicator text (`NO_PAST_APPOINTMENTS`).
- **Próximo atendimento**:
  - Displays localized date/time (`formatDateTime`), scheduled professional (`comQuem`) if present, and a subtle confirmation badge (`Confirmado` / `Não confirmado`).
  - If null, displays subtle empty text (`NO_FUTURE_APPOINTMENTS`: "Nenhum agendamento futuro") without empty container boxes.

### Rationale
- **Eliminates visual heaviness**: Dark stacked boxes with dark borders broke the visual rhythm of the sidebar, looking like disconnected widgets rather than cohesive customer record data.
- **Height reduction**: Compact list formatting reduces the vertical height of the appointments block by > 30%, satisfying SC-004.
- **Information fidelity**: Retains 100% of the crucial operational information (dates, professional names, attendance, confirmation status).

### Alternatives Considered
- *Table layout*: A `<table>` structure is too wide for 280px sidebars and creates horizontal scrollbars or aggressive text truncation.
- *Collapsible accordion for appointments*: Adds unnecessary clicks for agents trying to quickly check if a customer has an upcoming appointment.

---

## 4. Centered and Responsive Registration Audit Timestamps

### Decision
Reformat the card footer audit timestamps (`dtCadpessoa` and `dtUltaltpessoa`):
- Centered horizontally at the bottom of the card (`flex flex-wrap items-center justify-center gap-x-1.5 gap-y-0.5 text-center`).
- Subtle italic typography (`text-[10px] text-n-slate-10 italic`).
- When both timestamps are present, render inline on the same row separated by a middle bullet dot (`•`).
- Allow responsive wrapping (`flex-wrap`) so that narrow sidebars gracefully break into two centered lines without clipping or horizontal overflow.
- If only one timestamp is present, center it without the bullet dot separator.
- If neither timestamp is present, omit the footnote block completely.

### Rationale
- **Visual balance**: A centered footer provides a distinct boundary between operational customer data and internal ERP metadata.
- **Responsive resilience**: Flex wrap with center alignment guarantees zero horizontal scrollbars even on sidebars down to 240px width.

### Alternatives Considered
- *Left-aligned stacked rows*: The previous layout consumed 2 vertical lines unconditionally and felt unpolished.
- *Placing audit dates in the attribute list*: Clutters the high-priority contact information with low-priority database timestamps.

---

## 5. Localization and String Architecture

### Decision
Synchronously update `app/javascript/dashboard/i18n/locale/en/conversation.json` and `pt_BR/conversation.json`:
- Add `FIELDS.ADDRESS`: `"Address"` (en) / `"Endereço"` (pt-BR).
- Add `PHONE_TOGGLE_MORE`: `"Show all phone numbers"` (en) / `"Ver todos os telefones"` (pt-BR).
- Add `PHONE_TOGGLE_LESS`: `"Show main phone only"` (en) / `"Exibir apenas telefone principal"` (pt-BR).
- Retain existing `FIELDS.NR_TELCELPESSOA`, `FIELDS.NR_TELRESPESSOA`, `FIELDS.NR_TELCOMPESSOA` for phone row type labels.
- Retain existing `APPOINTMENTS.*` and `FOOTNOTES.*` keys.

### Rationale
Strict adherence to Constitution Principle III, Section Personalization Boundaries (synchronous EN/pt-BR localization) and SC-006.
