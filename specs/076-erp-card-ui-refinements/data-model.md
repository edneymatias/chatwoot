# Data Model: ERP Contact Card UI Refinements

**Branch**: `076-erp-card-ui-refinements` | **Spec**: [spec.md](./spec.md)

## Overview

This feature refines the client-side presentation models in `ErpDataCard.vue`. The backend schema and HTTP proxy responses remain unchanged. The data model changes reside in how raw ERP payload fields are filtered, synthesized, grouped, and rendered in the Vue 3 component.

---

## Entities

### 1. Customer Record (Raw Inbound ERP Payload)

The structured JSON payload delivered by `GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`:

| Field | Type | Description | Handling in Card |
|---|---|---|---|
| `nmPessoa` | string | Customer full name | Rendered in attributes list |
| `nrCpfcnpjpessoa` | string | Brazilian tax ID (CPF or CNPJ) | Formatted with mask |
| `nrRgpessoa` | string | State identity document | Rendered verbatim |
| `nmEndpessoa` | string | Street name / Logradouro | Synthesized into Consolidated Address |
| `nrEndpessoa` | string | Street number | Synthesized into Consolidated Address |
| `compEndpessoa` | string | Address complement (apt, block) | Synthesized into Consolidated Address |
| `nmBaipessoa` | string | Neighborhood / Bairro | Synthesized into Consolidated Address |
| `nmCidpessoa` | string | City name | Synthesized into Consolidated Address |
| `ufEndpessoa` | string | State abbreviation (2 chars) | Synthesized into Consolidated Address |
| `nrCeppessoa` | string | Brazilian postal code (8 digits) | Synthesized into Consolidated Address with mask |
| `nrTelcelpessoa` | string | Mobile / Cell phone | Primary contact channel candidate |
| `nrTelrespessoa` | string | Home phone | Secondary contact channel candidate |
| `nrTelcompessoa` | string | Work phone | Secondary contact channel candidate |
| `emailPessoa` | string | Email address | Rendered in attributes list |
| `tpSxpessoa` | string | Gender code | Rendered in attributes list |
| `dtNascpessoa` | string | Birth date (`YYYY-MM-DD`) | Formatted date + birthday highlight |
| `nmNacpessoa` | string | Nationality | Rendered in attributes list |
| `dsConvenio` | string | Insurance provider name | Rendered in attributes list |
| `nrConvenio` | string | Insurance card number | Rendered in attributes list |
| `nrFicha` | string/number | Medical chart ID (Prontuário) | Rendered in attributes list |
| `dsProfissao` | string | Profession description | Rendered in attributes list |
| `descricaoOrigem` | string | Lead / Acquisition origin | Rendered in attributes list |
| `atendimentos` | object | Appointment schedule history | Rendered in Appointments clean list |
| `financeiro` | object | Financial summary and installments | Rendered in Financial section |
| `dtCadpessoa` | string | Registration timestamp (ISO 8601) | Synthesized into Centered Audit Footnotes |
| `dtUltaltpessoa` | string | Last update timestamp (ISO 8601) | Synthesized into Centered Audit Footnotes |

---

### 2. Consolidated Address (Synthesized Entity)

A virtual attribute row synthesized from the 7 discrete raw address components:

```typescript
interface ConsolidatedAddress {
  key: 'address';
  labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.ADDRESS';
  value: string; // Formatted single-line string
}
```

#### Composition Rules
1. **Street Segment**: `[nmEndpessoa, nrEndpessoa, compEndpessoa].filter(Boolean).join(', ')`
2. **Neighborhood Segment**: `nmBaipessoa` (if non-empty)
3. **City/State Segment**:
   - Both present: `${nmCidpessoa}/${ufEndpessoa}`
   - City only: `${nmCidpessoa}`
   - State only: `${ufEndpessoa}`
4. **Location Prefix**: `[streetSegment, neighborhoodSegment, cityStateSegment].filter(Boolean).join(', ')`
5. **Postal Code Segment**: `maskCep(nrCeppessoa)` (formatted as `00000-000` when 8 digits)
6. **Final String**:
   - Location prefix + Postal code: `${locationPrefix} - ${postalCodeSegment}`
   - Location prefix only: `${locationPrefix}`
   - Postal code only: `${postalCodeSegment}`
   - If all components are empty: `null` (row omitted from display)

---

### 3. Phone Channel Set & Expansion State

Represents the customer's available telephone channels and their interactive disclosure state:

```typescript
interface PhoneChannel {
  key: 'nrTelcelpessoa' | 'nrTelrespessoa' | 'nrTelcompessoa';
  labelKey: string;
  rawValue: string;
  formattedValue: string;
}

interface CustomerPhoneState {
  primaryPhone: PhoneChannel | null;
  secondaryPhones: PhoneChannel[];
  hasMultiplePhones: boolean;
  isPhonesExpanded: boolean; // Local reactive toggle state
}
```

#### Selection & Priority Rules
1. **Priority Order**: `nrTelcelpessoa` > `nrTelrespessoa` > `nrTelcompessoa`.
2. **Primary Assignment**: The first available channel with non-empty digits becomes `primaryPhone`.
3. **Secondary Assignment**: All remaining non-empty channels become `secondaryPhones`.
4. **Multiple Phones Flag**: `secondaryPhones.length > 0`.
5. **Expansion Toggle**:
   - When `isPhonesExpanded === false`: only `primaryPhone` is visible. If `hasMultiplePhones === true`, an ellipsis toggle button (`...`) is displayed next to the phone value.
   - When `isPhonesExpanded === true`: `primaryPhone` remains visible, and `secondaryPhones` are rendered sequentially below it in the attributes list.
   - When switching contacts, `isPhonesExpanded` resets to `false`.

---

### 4. Redesigned Appointments Schedule

Structured presentation entity for past and future clinical/service appointments:

```typescript
interface AppointmentDetail {
  dataHora: string; // ISO 8601 timestamp
  formattedDate: string; // Localized date/time
  comQuem?: string; // Attending or scheduled professional name
  compareceu?: boolean; // Last visit: attendance flag
  confirmado?: boolean; // Next visit: confirmation flag
}

interface AppointmentsSectionState {
  ultimo: AppointmentDetail | null;
  proximo: AppointmentDetail | null;
  hasAppointmentsData: boolean;
}
```

#### Visual State Mapping
- **`ultimo` (Last Visit)**:
  - Present: Displays localized date/time, optional professional (`Com: {name}`), and subtle attendance badge (`Compareceu` [subtle slate/green] or `Não compareceu` [subtle slate/amber]).
  - Null/Empty: Displays localized empty text (`CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NO_PAST_APPOINTMENTS`: "Nenhum").
- **`proximo` (Next Visit)**:
  - Present: Displays localized date/time, optional professional (`Com: {name}`), and subtle confirmation badge (`Confirmado` [teal pill badge] or `Não confirmado` [subtle slate pill badge]).
  - Null/Empty: Displays localized empty indicator text (`CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NO_FUTURE_APPOINTMENTS`: "Nenhum agendamento futuro") styled subtly in italic slate text without any empty box frame.

---

### 5. Centered Registration Audit Timestamps

Discreet audit metadata centered at the bottom of the card:

```typescript
interface AuditFootnotesState {
  createdAtFormatted: string | null;
  updatedAtFormatted: string | null;
  hasBoth: boolean;
  hasAny: boolean;
}
```

#### Formatting & Display Rules
- If neither timestamp is present: section is omitted.
- If both timestamps are present: rendered centered on a single line separated by `•`, with responsive wrapping (`flex flex-wrap items-center justify-center gap-x-1.5 gap-y-0.5 text-center`).
- If only one timestamp is present: rendered centered without the bullet separator.
