# API Contract: ERP Customer Data Proxy Endpoint

**Endpoint**: `GET /api/v1/accounts/{account_id}/integrations/erp/data`
**Controller**: `Api::V1::Accounts::Integrations::ErpController#data`
**Access**: Authenticated Account User (Administrator, Agent, Custom Role)

---

## 1. Overview
Returns customer data retrieved from the account's active ERP system for a given Chatwoot contact. The backend resolves the enabled ERP integration, manages external ID caching and resolution, and returns a clean, standardized status payload.

---

## 2. Request

### 2.1 Headers
| Header | Type | Required | Description |
|---|---|---|---|
| `api_access_token` / Cookie | `string` | Yes | Standard Chatwoot authentication token or session cookie. |
| `Content-Type` | `string` | Yes | `application/json` |

### 2.2 Path Parameters
| Parameter | Type | Required | Description |
|---|---|---|---|
| `account_id` | `integer` | Yes | Account ID. |

### 2.3 Query Parameters
| Parameter | Type | Required | Description |
|---|---|---|---|
| `contact_id` | `integer` | Yes | Contact ID for whom ERP data should be retrieved. |

---

## 3. Responses

### 3.1 200 OK — Customer Record Found (`status: 'found'`)
Returned when an ERP record matches the contact's cached identifier or phone number.

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
    "nrTelcompessoa": "4132221111",
    "emailPessoa": "maria.silva@example.com",
    "tpSxpessoa": "F",
    "dtNascpessoa": "1990-09-18",
    "nmNacpessoa": "Brasileira",
    "dsConvenio": "Unimed",
    "nrConvenio": "00293841029",
    "nrFicha": "F-48291",
    "dsProfissao": "Engenheira",
    "descricaoOrigem": "Indicação",
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
  },
  "multiple_matches": false
}
```

#### Response Fields:
- `status` (`string`): Always `'found'`.
- `data` (`object`): Dictionary of customer attributes returned by the ERP (including `atendimentos` and `financeiro`).
- `multiple_matches` (`boolean`): `true` if phone search returned more than one record; `false` otherwise.

---

### 3.2 200 OK — Multiple Matches Found (`multiple_matches: true`)
Returned when the phone search returned multiple customer records matching the contact's phone number. The first record is returned and its ID cached.

```json
{
  "status": "found",
  "data": {
    "nmPessoa": "Maria Silva (Titular)",
    "nrCpfcnpjpessoa": "12345678900",
    "nrTelcelpessoa": "41996937898"
  },
  "multiple_matches": true
}
```

---

### 3.3 200 OK — Customer Record Not Found (`status: 'not_found'`)
Returned when the contact has no phone number, or when lookup via phone search yields no matching customer in the ERP.

```json
{
  "status": "not_found"
}
```

---

### 3.4 404 Not Found — ERP Integration Not Configured or Disabled
Returned when the account has no enabled ERP hook.

```json
{
  "error": "ERP integration not found or not enabled"
}
```

---

### 3.5 404 Not Found — Contact Not Found
Returned when `contact_id` does not match any contact belonging to `Current.account`.

```json
{
  "error": "Contact not found"
}
```

---

### 3.6 503 Service Unavailable — External ERP Failure
Returned when the remote ERP is unreachable, times out, returns 5xx, or invalid credentials. The exception is logged internally via `ChatwootExceptionTracker`.

```json
{
  "error": "ERP service error: 503"
}
```
