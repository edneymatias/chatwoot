# Data Model: ERP Contact Panel Data Card

**Branch**: `075-erp-contact-data-card`
**Date**: 2026-09-18
**Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

---

## 1. Entities and Schemas

### 1.1 Contact (Core Model Extension)
The standard Chatwoot `Contact` model stores person details. This feature utilizes its existing `phone_number` and `additional_attributes` fields without schema migrations or table modifications.

- **Attributes**:
  - `id`: `integer` (primary key)
  - `account_id`: `integer` (foreign key to `Account`)
  - `phone_number`: `string` (E.164 phone string, e.g., `"+5541996937898"`, or `nil`)
  - `additional_attributes`: `jsonb`
- **ERP Extension Structure**:
  ```json
  {
    "external": {
      "younus_id": 98421
    }
  }
  ```
  - `external`: `hash` containing external integration identifiers.
  - `#{erp_name.downcase}_id` (e.g. `younus_id`): `string` or `integer`, the unique person identifier in the target ERP.
- **Invariants**:
  - If a cached ID is present, direct lookup via `find_by_id` MUST verify that the remote record's phone matches `contact.phone_number`.
  - If phone mismatch occurs or ID lookup returns `nil`, `additional_attributes['external']['younus_id']` MUST be deleted and persisted.
  - When a phone lookup succeeds, `additional_attributes['external']['younus_id']` MUST be updated with the newly resolved person ID.

---

### 1.2 Integrations::Hook (Account Integration Hook)
The account-level hook representing the active ERP connection.

- **Attributes**:
  - `id`: `integer` (primary key)
  - `account_id`: `integer` (foreign key to `Account`)
  - `app_id`: `string` (e.g., `'younus'`)
  - `status`: `integer` (`disabled: 0`, `enabled: 1`)
  - `hook_type`: `integer` (`account: 0`, `inbox: 1` — ERP uses `account`)
  - `settings`: `jsonb`
    - `token`: `string` (API static token)
    - `id_empresa`: `string` (Company ID in Younus)
- **Scopes & Invariants**:
  - `erp_integration?`: `app_id == 'younus'` (extended per provider in `custom/app/models/custom/integrations/hook.rb`).
  - At most one enabled ERP integration hook per account is active.

---

### 1.3 ERP Customer Record (Transient Payload)
The customer record returned by the external ERP (e.g., Younus `dados[0]['json']`). It contains personal information, metadata, and structured sub-objects for appointments and finances.

#### 1.3.1 Whitelisted Business Attributes
These fields are displayed in the personal attributes list with friendly labels and formatting masks:

| Key | Friendly Label (PT-BR) | Friendly Label (EN) | Formatting / Mask Rule | Ordering / Position |
|---|---|---|---|---|
| `nmPessoa` | Nome | Name | String trimmed | #1 (Top) |
| `nrCpfcnpjpessoa` | CPF / CNPJ | CPF / CNPJ | CPF `000.000.000-00` (11d) / CNPJ `00.000.000/0000-00` (14d) | #2 |
| `nrRgpessoa` | RG | RG | String trimmed | #3 (Immediately adjacent to CPF) |
| `nmEndpessoa` | Logradouro | Street | String trimmed | #4 (Address group) |
| `nrEndpessoa` | Número | Number | String trimmed | #5 (Address group) |
| `compEndpessoa` | Complemento | Complement | String trimmed | #6 (Address group) |
| `nmBaipessoa` | Bairro | District | String trimmed | #7 (Address group) |
| `nmCidpessoa` | Cidade | City | String trimmed | #8 (Address group) |
| `ufEndpessoa` | UF | State | Uppercase 2-letter string | #9 (Address group) |
| `nrCeppessoa` | CEP | Postal Code | CEP `00000-000` (8d) | #10 (Address group) |
| `nrTelrespessoa` | Telefone residencial | Landline phone | `(00) 0000-0000` (10d) | #11 (Contact group) |
| `nrTelcelpessoa` | Celular | Mobile phone | `(00) 00000-0000` (11d) | #12 (Contact group) |
| `nrTelcompessoa` | Telefone comercial | Commercial phone | `(00) 0000-0000` / `(00) 00000-0000` | #13 (Contact group) |
| `emailPessoa` | Email | Email | String trimmed | #14 (Contact group) |
| `tpSxpessoa` | Sexo | Gender | String trimmed (`M` / `F` / custom) | #15 |
| `dtNascpessoa` | Data de nascimento | Date of birth | Localized date without time (`DD/MM/YYYY`) + Birthday highlight | #16 |
| `nmNacpessoa` | Naturalidade | Place of birth | String trimmed | #17 |
| `dsConvenio` | Convênio | Health Plan | String trimmed | #18 |
| `nrConvenio` | Carteirinha | Plan Card Number | String trimmed | #19 |
| `nrFicha` | Prontuário | Medical Record / Chart | String trimmed | #20 |
| `dsProfissao` | Profissão | Profession | String trimmed | #21 |
| `descricaoOrigem` | Origem | Referral Origin | String trimmed | #22 |

#### 1.3.2 Excluded Technical Attributes
These internal database keys and flags are **STRICTLY EXCLUDED** from display (FR-015):
- `idPessoa`
- `idEmpresa`
- `pessoaTipo`
- `tpPessoa`
- `nmPaispessoa`
- `idProfpessoa`
- `idUsuario`
- `idEspecpessoa`
- `dtUltacesso`
- `stTermo`
- `stCadastro`
- `stPessoa`
- `idConvenio`
- `nmConvenio`
- `idPerfil`
- `observacoes`
- `origemPessoa`
- `nrConselho`
- `siglaConselho`
- `ufConselho`
- `indClientePadrao`

#### 1.3.3 Audit Footnote Attributes
These attributes appear at the very bottom of the card as discreet footnotes in italics and smaller font (FR-019):
- `dtCadpessoa`: "Data de cadastro" (Registration date, formatted in browser locale `DD/MM/YYYY HH:mm`)
- `dtUltaltpessoa`: "Data de atualização" (Last update date, formatted in browser locale `DD/MM/YYYY HH:mm`)

---

### 1.4 Structured Sub-Objects

#### 1.4.1 Appointments (`atendimentos`)
Structured presentation of appointment history and upcoming visits (FR-020):

```json
{
  "atendimentos": {
    "ultimo": {
      "dataHora": "2026-08-15T14:30:00",
      "comQuem": "Dra. Paula Oliveira",
      "compareceu": true
    },
    "proximo": {
      "dataHora": "2026-09-25T10:00:00",
      "comQuem": "Dr. Fernando Costa",
      "confirmado": true
    }
  }
}
```

- **`ultimo` (Last visit)**:
  - `dataHora`: Localized date and time (`DD/MM/YYYY HH:mm`).
  - `comQuem`: Name of attending professional.
  - `compareceu`: Boolean attendance status ("Compareceu" / "Não compareceu").
  - If null: Renders friendly empty indicator ("Nenhum").
- **`proximo` (Next visit)**:
  - `dataHora`: Localized date and time (`DD/MM/YYYY HH:mm`).
  - `comQuem`: Name of scheduled professional.
  - `confirmado`: Boolean confirmation status. Prominently highlighted with a badge when `true` ("Confirmado").
  - If null: Renders friendly empty indicator ("Nenhum agendamento futuro").

#### 1.4.2 Financial (`financeiro`)
Structured presentation of customer credit and billing health (FR-021):

```json
{
  "financeiro": {
    "devedor": true,
    "parcelaVencida": {
      "dtVencimento": "2026-07-10",
      "valor": 250.00,
      "valorCorrigido": 278.45
    },
    "proximaParcela": {
      "dtVencimento": "2026-10-10",
      "valor": 250.00
    },
    "totalFinanceiro": 3000.00,
    "totalRecebido": 2000.00,
    "totalAberto": 1000.00,
    "totalDevedor": 500.00
  }
}
```

- **`devedor`**: Boolean debtor flag. Rendered with a prominent warning badge (`bg-n-ruby-3 text-n-ruby-11 border border-n-ruby-6`) whenever `true`.
- **`parcelaVencida`**: Clarified as the **oldest overdue installment** ("Parcela vencida mais antiga"):
  - `dtVencimento`: Localized due date (`DD/MM/YYYY`).
  - `valor`: Original installment value, formatted as currency (`R$ 250,00`).
  - `valorCorrigido`: Adjusted value with interest/penalty, formatted as currency (`R$ 278,45`).
  - If null: Displays friendly empty indicator ("Nenhuma").
- **`proximaParcela`**: Next scheduled installment:
  - `dtVencimento`: Localized due date (`DD/MM/YYYY`).
  - `valor`: Formatted as currency.
  - If null: Displays friendly empty indicator ("Nenhuma").
- **Summary Totals**:
  - `totalFinanceiro`: Contracted total amount, formatted as currency.
  - `totalRecebido`: Total amount paid/received, formatted as currency.
  - `totalAberto`: Total open balance, formatted as currency.
  - `totalDevedor`: Total consolidated overdue balance, formatted as currency (highlighted if > 0).

---

## 2. API Response Payload Contract

Produced by `GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`:

### 2.1 Record Found (`status: 'found'`)
```json
{
  "status": "found",
  "data": {
    "nmPessoa": "Maria Silva",
    "nrCpfcnpjpessoa": "12345678900",
    "nrRgpessoa": "123456789",
    "nmEndpessoa": "Rua das Flores",
    "nrEndpessoa": "123",
    "compEndpessoa": "Apto 4B",
    "nmBaipessoa": "Centro",
    "nmCidpessoa": "Curitiba",
    "ufEndpessoa": "PR",
    "nrCeppessoa": "80010000",
    "nrTelcelpessoa": "41996937898",
    "nrTelrespessoa": "4133334444",
    "emailPessoa": "maria.silva@example.com",
    "tpSxpessoa": "F",
    "dtNascpessoa": "1990-09-18",
    "nrFicha": "F-48291",
    "dsConvenio": "Unimed",
    "nrConvenio": "00293841029",
    "dtCadpessoa": "2024-01-10T09:00:00",
    "dtUltaltpessoa": "2026-09-01T14:20:00",
    "atendimentos": {
      "ultimo": {
        "dataHora": "2026-08-15T14:30:00",
        "comQuem": "Dra. Paula Oliveira",
        "compareceu": true
      },
      "proximo": {
        "dataHora": "2026-09-25T10:00:00",
        "comQuem": "Dr. Fernando Costa",
        "confirmado": true
      }
    },
    "financeiro": {
      "devedor": false,
      "parcelaVencida": null,
      "proximaParcela": {
        "dtVencimento": "2026-10-10",
        "valor": 250.00
      },
      "totalFinanceiro": 3000.00,
      "totalRecebido": 2750.00,
      "totalAberto": 250.00,
      "totalDevedor": 0.00
    }
  },
  "multiple_matches": false
}
```

### 2.2 Record Not Found (`status: 'not_found'`)
```json
{
  "status": "not_found"
}
```

### 2.3 Service Error (`HTTP 503 Service Unavailable`)
```json
{
  "error": "ERP service error: 503"
}
```

---

## 3. UI State Transitions & Component Flow

```
                             ┌─────────────────────────────────┐
                             │ Contact selected / card loaded  │
                             └────────────────┬────────────────┘
                                              │
                                              ▼
                             ┌─────────────────────────────────┐
                             │ Contact has phone number?       │
                             └────────┬───────────────┬────────┘
                                      │ No            │ Yes
                                      ▼               ▼
                            ┌──────────────────┐ ┌─────────────────────────────────┐
                            │ status =         │ │ status = 'loading'              │
                            │ 'no_phone'       │ │ Issue GET /erp/data             │
                            │ (no API call)    │ └────────────────┬────────────────┘
                            └──────────────────┘                  │
                                              ┌───────────────────┴───────────────────┐
                                              │                                       │
                                    HTTP 200 (found)                        HTTP 200 (not_found)
                                              │                                       │
                                              ▼                                       ▼
                                ┌───────────────────────────┐           ┌───────────────────────────┐
                                │ status = 'found'          │           │ status = 'not_found'      │
                                │ Apply strict whitelist    │           │ Display registration hint │
                                │ Apply Brazilian masks     │           └───────────────────────────┘
                                │ Check birthday match      │
                                │ Render appointments       │                       HTTP 503 (error)
                                │ Render finance & debtor   │                              │
                                │ Render audit footnotes    │                              ▼
                                └───────────────────────────┘           ┌───────────────────────────┐
                                                                        │ status = 'error'          │
                                                                        │ Display retry button      │
                                                                        └───────────────────────────┘
```

---

## 4. Business Validation & Presentation Invariants

1. **Strict Whitelist Policy**:
   - Only attributes present in the 22-item whitelist are rendered in the attributes list.
   - Any raw database keys (`idPessoa`, `idEmpresa`, `stTermo`, etc.) or unexpected extra fields are suppressed.
   - Attributes with `null`, `undefined`, or empty strings after trimming are omitted.
2. **Date of Birth & Birthday Highlight**:
   - `dtNascpessoa` formatted without time in the user's browser locale.
   - If `birthMonth === currentMonth && birthDay === currentDay`, a prominent birthday badge is displayed.
3. **Oldest Overdue Installment Distinction**:
   - `financeiro.parcelaVencida` MUST be explicitly labeled as the "Parcela vencida mais antiga" (oldest overdue installment).
   - Consolidated overdue balance is displayed in `totalDevedor`.
4. **Punctuation Masking Consistency**:
   - Document masks: CPF (11 digits `###.###.###-##`), CNPJ (14 digits `##.###.###/####-##`), CEP (8 digits `#####-###`).
   - Phone masks: Mobile (11 digits `(##) #####-####`), Landline (10 digits `(##) ####-####`).
   - Irregular lengths safely fall back to the raw unmasked string.
