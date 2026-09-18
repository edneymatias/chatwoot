# Frontend UI Contract: ERP Data Card Component

**Component**: `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`
**Integration Point**: `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`
**Type**: Vue 3 Single File Component (Composition API `<script setup>`)

---

## 1. Props & Bindings

| Prop | Type | Required | Default | Description |
|---|---|---|---|---|
| `contactId` | `Number` \| `String` | Yes | N/A | Current contact ID. Watched to trigger data re-fetching. |
| `contact` | `Object` | No | `{}` | Optional contact object containing `phone_number`. Fallback: `contacts/getContact` store getter. |

---

## 2. Public Exposed Methods (`defineExpose`)

| Method | Parameters | Returns | Description |
|---|---|---|---|
| `fetchErpData` | None | `Promise<void>` | Imperatively re-fetches ERP data for current `contactId`. Used by header refresh button. |

---

## 3. Visual States & DOM Selectors

| State | Condition | Root Test ID | Rendered Content |
|---|---|---|---|
| **Loading** | `status === 'loading'` | `erp-loading-spinner` | Spinner with `$t('CONVERSATION_SIDEBAR.ERP_DATA.LOADING')`. |
| **No Phone** | `status === 'no_phone'` | `erp-no-phone-state` | Info text `$t('CONVERSATION_SIDEBAR.ERP_DATA.NO_PHONE')`. Zero API calls made. |
| **Not Found** | `status === 'not_found'` | `erp-not-found-state` | Title and message suggesting customer registration in ERP. |
| **Error** | `status === 'error'` | `erp-error-state` | Error title, message, and "Retry" `<woot-button>` invoking `fetchErpData`. |
| **Found** | `status === 'found' && customerData` | `erp-found-data` | Curated attribute list, appointment section, financial section, footnotes. |

---

## 4. Curated Field Whitelist Display Specification

When in `found` state, personal attributes are filtered against an explicit ordered whitelist.
Unmapped keys, nulls, undefined, and empty trimmed strings are completely omitted.
Technical database IDs (`idPessoa`, `idEmpresa`, `stTermo`, etc.) are never rendered.

### 4.1 Personal Attributes Rows (`erp-attribute-row`)
Each row renders in a two-column grid aligned by `:`.

```html
<div class="grid grid-cols-[1fr_auto_1fr] items-baseline gap-2 py-1 text-xs">
  <span class="font-medium text-n-slate-11 text-right truncate" :title="label">
    {{ label }}
  </span>
  <span class="text-n-slate-10 select-none font-semibold">:</span>
  <span class="text-n-slate-12 break-all text-left">
    {{ formattedValue }}
  </span>
</div>
```

### 4.2 Formatting & Mask Rules
- **CPF/CNPJ** (`nrCpfcnpjpessoa`):
  - 11 digits: `000.000.000-00`
  - 14 digits: `00.000.000/0000-00`
  - Irregular: Raw value
- **CEP** (`nrCeppessoa`):
  - 8 digits: `00000-000`
  - Irregular: Raw value
- **Phones** (`nrTelcelpessoa`, `nrTelrespessoa`, `nrTelcompessoa`):
  - 11 digits: `(00) 00000-0000`
  - 10 digits: `(00) 0000-0000`
  - Irregular: Raw value
- **Date of Birth** (`dtNascpessoa`):
  - Formatted without time in browser locale (e.g. `18/09/1990`).
  - If today matches birthday: Displays prominent birthday badge (`erp-birthday-badge`):
    `🎂 Aniversariante hoje` / `Birthday today`.
- **Medical Chart** (`nrFicha`):
  - Labeled as "Prontuário".

- **Gender** (`tpSxpessoa`):
  - Trimmed string value (e.g. `M`, `F`, or custom string).
---

## 5. Structured Sections Specification

### 5.1 Appointments Section (`atendimentos`)
Displayed in `erp-appointments-section`:
- **Last Visit (`ultimo`)**:
  - Date & time localized.
  - Professional name (`comQuem`).
  - Attendance badge / text (`compareceu`).
  - Empty fallback: "Nenhum".
- **Next Visit (`proximo`)**:
  - Date & time localized.
  - Professional name (`comQuem`).
  - Confirmation badge (`erp-appointment-confirmed-badge`): Prominently highlighted when `confirmado === true`.
  - Empty fallback: "Nenhum agendamento futuro".

### 5.2 Financial Section (`financeiro`)
Displayed in `erp-financial-section`:
- **Debtor Warning Badge (`erp-debtor-badge`)**:
  - Displayed prominently at the top of the financial section whenever `devedor === true`.
- **Oldest Overdue Installment (`parcelaVencida`)**:
  - Labeled as "Parcela vencida mais antiga" (`erp-oldest-overdue-installment`).
  - Due date (`dtVencimento`), original `valor` (currency), `valorCorrigido` (currency).
  - Empty fallback: "Nenhuma".
- **Next Installment (`proximaParcela`)**:
  - Due date and value formatted as currency.
- **Totals Grid**:
  - `totalFinanceiro`, `totalRecebido`, `totalAberto`, `totalDevedor` formatted as currency.

### 5.3 Audit Footnotes (`dtCadpessoa` / `dtUltaltpessoa`)
Displayed in `erp-audit-footnotes` at the bottom of the card in italics and smaller font (`text-[10px] text-n-slate-10 italic`):
- `Data de cadastro`: formatted timestamp.
- `Data de atualização`: formatted timestamp.

---

## 6. Multiple Matches Indicator

When `multiple_matches === true`:
- Renders `erp-multiple-matches-badge` banner at the top of the card with an info icon and localized notice:
  `$t('CONVERSATION_SIDEBAR.ERP_DATA.MULTIPLE_MATCHES_BADGE')`.
