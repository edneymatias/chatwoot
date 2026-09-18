# UI Contract: ERP Contact Card Refinements

**Branch**: `076-erp-card-ui-refinements` | **Spec**: [spec.md](../spec.md)

## 1. Component Specification

**File**: `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`

### Props
| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `contactId` | `Number` \| `String` | `true` | — | Current contact identifier |
| `contact` | `Object` | `false` | `() => ({})` | Contact object containing phone number |

---

## 2. DOM & Test ID Contract

The component MUST provide stable, queryable test IDs for automated verification:

| Target Element | Selector / Test ID | Conditions / Behavior |
|---|---|---|
| Card Container | `[data-testid="erp-found-data"]` | Visible when customer record loaded |
| Attribute Row | `[data-testid="erp-attribute-row"]` | Standard personal attribute row |
| Address Row | `[data-testid="erp-attribute-row"]` with label "Endereço" / "Address" (canonical) or `[data-testid="erp-address-row"]` | Rendered only when at least 1 address field is present |
| Primary Phone Row | `[data-testid="erp-primary-phone-row"]` | Rendered when any phone is available |
| Phone Expand Toggle | `[data-testid="erp-phone-expand-toggle"]` | Present ONLY when > 1 phone number exists |
| Secondary Phone Row | `[data-testid="erp-secondary-phone-row"]` | Present ONLY when `isPhonesExpanded === true` |
| Appointments Section | `[data-testid="erp-appointments-section"]` | Rendered when `customerData.atendimentos` exists |
| Last Appointment Row | `[data-testid="erp-appointment-ultimo"]` | Displays past appointment or empty state |
| Next Appointment Row | `[data-testid="erp-appointment-proximo"]` | Displays next appointment or empty indicator |
| Confirmed Badge | `[data-testid="erp-appointment-confirmed-badge"]` | Visible on next appointment when `confirmado: true` |
| Audit Footnotes | `[data-testid="erp-audit-footnotes"]` | Centered footer with registration / update dates |
| Created At Footnote | `[data-testid="erp-audit-created-at"]` | Present when `dtCadpessoa` is populated |
| Updated At Footnote | `[data-testid="erp-audit-updated-at"]` | Present when `dtUltaltpessoa` is populated |
| Audit Separator | `[data-testid="erp-audit-separator"]` | Bullet dot `•` present ONLY when BOTH dates are populated |

---

## 3. Formatting Contract Matrix

### Address Composition
| Raw Fields Input | Expected Formatted Address Output |
|---|---|
| Logradouro: "Rua XV", Número: "100", Complemento: "Sl 4", Bairro: "Centro", Cidade: "Curitiba", UF: "PR", CEP: "80000000" | `"Rua XV, 100, Sl 4, Centro, Curitiba/PR - 80000-000"` |
| Logradouro: "Rua XV", Número: "100", Complemento: null, Bairro: "Centro", Cidade: "Curitiba", UF: "PR", CEP: "80000000" | `"Rua XV, 100, Centro, Curitiba/PR - 80000-000"` |
| Logradouro: "Av Brasil", Número: null, Bairro: "Jardins", Cidade: "São Paulo", UF: "SP", CEP: null | `"Av Brasil, Jardins, São Paulo/SP"` |
| Cidade: "Santos", UF: "SP" | `"Santos/SP"` |
| Cidade: "Santos", UF: null | `"Santos"` |
| CEP: "80000000" (no other fields) | `"80000-000"` |
| All address fields null/empty | Row omitted completely |

### Phone Channel Selection & Disclosure
| Input Phone Fields | Primary Displayed | Ellipsis Button? | Expanded Rows (on click) |
|---|---|---|---|
| Celular: "11987654321" | Celular: "(11) 98765-4321" | No | None |
| Celular: "11987654321", Residencial: "1134567890" | Celular: "(11) 98765-4321" | Yes | Telefone residencial: "(11) 3456-7890" |
| Celular: "11987654321", Residencial: "1134567890", Comercial: "1133334444" | Celular: "(11) 98765-4321" | Yes | Telefone residencial: "(11) 3456-7890"<br>Telefone comercial: "(11) 3333-4444" |
| Celular: null, Residencial: "1134567890", Comercial: "1133334444" | Telefone residencial: "(11) 3456-7890" | Yes | Telefone comercial: "(11) 3333-4444" |
| All phone fields null/empty | No phone row displayed | No | None |

### Appointments Section (Clean List Layout)
- Visual Style: Clean key-value item rows with subtle dividers (`divide-y divide-n-weak`), NO dark box containers (`bg-n-alpha-1 border border-n-weak`).
- `ultimo`:
  - Label: `CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.LAST_VISIT`
  - When populated: Date/time (`formatDateTime`), Attendance badge (`Compareceu` / `Não compareceu`), and attending professional (`comQuem`).
  - When null: Localized empty label (`NO_PAST_APPOINTMENTS`: "Nenhum").
- `proximo`:
  - Label: `CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NEXT_VISIT`
  - When populated: Date/time (`formatDateTime`), Confirmation badge (`Confirmado` / `Não confirmado`), and scheduled professional (`comQuem`).
  - When null: Localized subtle empty text (`NO_FUTURE_APPOINTMENTS`: "Nenhum agendamento futuro"), no empty box.

### Centered Audit Footnotes
- Layout: Single continuous inline sentence centered horizontally (`text-center text-[10px] text-n-slate-10 italic leading-normal`) that wraps naturally across column width.
- When both `dtCadpessoa` and `dtUltaltpessoa` present:
  `{CREATED_AT}: {date} • {UPDATED_AT}: {date}`
- When only `dtCadpessoa` present:
  `{CREATED_AT}: {date}` (no separator)
- When neither present: block omitted.

---

## 4. Localization Contract

The following keys MUST exist synchronously in both locale files:

| Key Path | English (`en/conversation.json`) | Brazilian Portuguese (`pt_BR/conversation.json`) |
|---|---|---|
| `CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.ADDRESS` | `"Address"` | `"Endereço"` |
| `CONVERSATION_SIDEBAR.ERP_DATA.PHONE_TOGGLE_MORE` | `"Show all phone numbers"` | `"Ver todos os telefones"` |
| `CONVERSATION_SIDEBAR.ERP_DATA.PHONE_TOGGLE_LESS` | `"Show main phone only"` | `"Exibir apenas telefone principal"` |
