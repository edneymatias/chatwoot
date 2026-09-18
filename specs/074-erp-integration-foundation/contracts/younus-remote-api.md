# Remote API Contract: Younus ERP Webhook API

**Base URL**: `https://wfh.ichatr.com.br`
**Consumer**: `Erp::Younus::Client` (`custom/app/services/erp/younus/client.rb`)
**Protocol**: HTTPS / JSON
**Network Timeout**: 5 seconds

---

## 1. Search Person by Phone Endpoint

Used for synchronous credential validation (by providing a dummy phone query like `"0"`) and for customer lookups in Phase 02.

### 1.1 Request
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
| `nrTelcelpessoa` | `string` | Yes | Phone number for lookup (digits only, e.g., `"0"` for connection test, `"11987654321"` for lookup). |

---

## 2. Responses & Translation Matrix

### 2.1 200 OK — Valid Credentials, Person Found
Returned when the token and company ID are valid, and matching person record(s) exist.

```json
{
  "sucesso": true,
  "mensagem": "Pessoa encontrada com sucesso.",
  "dados": [
    {
      "json": {
        "cd_pessoa": 98421,
        "nm_pessoa": "Maria Silva",
        "nr_cpf": "12345678900",
        "nr_telcelpessoa": "11987654321",
        "ds_email": "maria.silva@example.com"
      }
    }
  ]
}
```

- **Client Action**: Returns record hash (`dados[0]['json']`).
- **Connection Test Outcome**: Succeeded (`true`).

---

### 2.2 200 OK — Valid Credentials, Person Not Found
Returned when the token and company ID are valid, but no record matches the phone number (standard response during connection validation test with dummy phone `"0"`).

```json
{
  "sucesso": false,
  "mensagem": "Nenhuma pessoa encontrada com o telefone informado.",
  "dados": []
}
```

- **Client Action**: Returns `nil` without raising an exception.
- **Connection Test Outcome**: Succeeded (`true`) — confirms credentials were authenticated by the remote server.

---

### 2.3 401 Unauthorized / 403 Forbidden — Invalid Credentials
Returned when the `token` header is invalid, expired, or revoked.

```json
{
  "error": "Unauthorized",
  "message": "Token inválido ou não informado."
}
```

- **Client Action**: Raises `Erp::AuthenticationError`.
- **Validation Outcome**: Fails ActiveRecord validation with "Invalid credentials" error.

---

### 2.4 503 Service Unavailable / 5xx Server Error
Returned when the remote ERP is under maintenance, experiencing internal errors, or invalid company parameters.

```json
{
  "error": "Service Unavailable",
  "message": "Erro ao consultar o banco de dados do ERP."
}
```

- **Client Action**: Raises `Erp::ApiError`.
- **Validation Outcome**: Fails ActiveRecord validation with "Could not connect to ERP" error.

---

### 2.5 Request Timeout (> 5s) or Network Disconnect
The remote server fails to complete TLS handshake or respond within 5 seconds.

- **Client Exception**: `Net::OpenTimeout`, `Net::ReadTimeout`, or `Errno::ECONNREFUSED`.
- **Client Action**: Rescues and re-raises as `Erp::ApiError, 'Connection timed out'`.
- **Validation Outcome**: Fails ActiveRecord validation with "Could not connect to ERP" error.
