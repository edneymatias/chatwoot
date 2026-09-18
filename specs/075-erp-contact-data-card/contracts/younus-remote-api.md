# Remote API Contract: Younus ERP Webhook API (Phase 02)

**Base URL**: `https://wfh.ichatr.com.br`
**Consumer**: `Erp::Younus::Client` (`custom/app/services/erp/younus/client.rb`)
**Protocol**: HTTPS / JSON
**Network Timeout**: 5 seconds

---

## 1. Direct Lookup by Person ID Endpoint

Used for cached identifier lookups to avoid expensive phone searches.

### 1.1 Request
`GET /webhook/pessoa`

#### Headers
| Header | Type | Required | Description |
|---|---|---|---|
| `token` | `string` | Yes | Static API token assigned to the account. |
| `Content-Type` | `string` | Yes | `application/json` |

#### Query Parameters
| Parameter | Type | Required | Description |
|---|---|---|---|
| `idEmpresa` | `string` | Yes | Younus Company ID. |
| `idPessoa` | `string` or `integer` | Yes | Younus Person ID previously cached on contact. |

---

### 1.2 Responses & Translation Matrix

#### 200 OK — Person Found
```json
{
  "sucesso": true,
  "mensagem": "Pessoa encontrada com sucesso.",
  "dados": [
    {
      "json": {
        "idPessoa": 98421,
        "cd_pessoa": 98421,
        "idEmpresa": 1,
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
      }
    }
  ]
}
```
- **Client Action**: Returns the person record hash (`dados[0]['json']`).

#### 200 OK — Person Not Found (Record Deleted or Merged in ERP)
```json
{
  "sucesso": false,
  "mensagem": "Nenhuma pessoa encontrada com o ID informado.",
  "dados": []
}
```
- **Client Action**: Returns `nil` without raising an exception. Triggers cache invalidation and fallback to phone search in the adapter.

---

## 2. Search Person by Phone Endpoint

Used for initial customer resolution or fallback recovery when cached ID fails or mismatches.

### 2.1 Request
`GET /webhook/pessoas`

#### Headers
| Header | Type | Required | Description |
|---|---|---|---|
| `token` | `string` | Yes | Static API token assigned to the account. |
| `Content-Type` | `string` | Yes | `application/json` |

#### Query Parameters
| Parameter | Type | Required | Description |
|---|---|---|---|
| `idEmpresa` | `string` | Yes | Younus Company ID. |
| `nrTelcelpessoa` | `string` | Yes | Phone number digits (e.g., `"41996937898"`). |

---

### 2.2 Responses & Translation Matrix

#### 200 OK — Single Match
```json
{
  "sucesso": true,
  "mensagem": "Pessoa encontrada com sucesso.",
  "dados": [
    {
      "json": {
        "idPessoa": 98421,
        "cd_pessoa": 98421,
        "nmPessoa": "Maria Silva",
        "nrTelcelpessoa": "41996937898"
      }
    }
  ]
}
```
- **Client Action**: Returns record hash (`dados[0]['json']`). Adapter identifies `multiple_matches: false`.

#### 200 OK — Multiple Matches
```json
{
  "sucesso": true,
  "mensagem": "Pessoas encontradas com sucesso.",
  "dados": [
    {
      "json": {
        "idPessoa": 98421,
        "cd_pessoa": 98421,
        "nmPessoa": "Maria Silva (Principal)",
        "nrTelcelpessoa": "41996937898"
      }
    },
    {
      "json": {
        "idPessoa": 98422,
        "cd_pessoa": 98422,
        "nmPessoa": "Maria Silva (Dependente)",
        "nrTelcelpessoa": "41996937898"
      }
    }
  ]
}
```
- **Client Action**: Returns first record (`dados[0]['json']`) and signals `multiple_matches: true`.

#### 200 OK — Not Found
```json
{
  "sucesso": false,
  "mensagem": "Nenhuma pessoa encontrada com o telefone informado.",
  "dados": []
}
```
- **Client Action**: Returns `nil` without raising an exception.

---

## 3. Common Error Translation

| Remote Status / Condition | Client Exception | Controller Status |
|---|---|---|
| `401 Unauthorized` / `403 Forbidden` | `Erp::AuthenticationError` | `HTTP 503 Service Unavailable` |
| `500..599 Server Error` | `Erp::ApiError` | `HTTP 503 Service Unavailable` |
| Connection Timeout (> 5s) / Connection Refused | `Erp::ApiError` | `HTTP 503 Service Unavailable` |
| Malformed JSON body | `Erp::ApiError` | `HTTP 503 Service Unavailable` |
