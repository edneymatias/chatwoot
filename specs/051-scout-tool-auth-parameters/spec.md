# Feature Specification: Scout Custom Tool Authentication & Visual Parameter Builder

**Feature Branch**: `051-scout-tool-auth-parameters`

**Created**: 2026-08-26

**Status**: Draft

**Input**: User description: "quero mudar algumas coisas na tela de configuração de ferramentas do scout. atualmente, ao configurar uma requisição precisamos definir os headers, o eschema json da requisição e opcionalmente o template de resposta para o agente. gostaria de implementar uma configuração de autenticação http, suportando 3 métodos: None — No authentication; Bearer Token — Sends your token in the Authorization header; Basic Auth — Sends a username and password; API Key — Sends a custom header name and value (e.g., X-API-Key). Assim podemos inclusive armazenar as credenciais de maneira segura.. a imagem de 1 a 4 está repetida e dão uma ideia do que estou tentando implementar. outra melhoria que quero fazer é quanto a forma de cadastramento do schema. atualmente preciso inserir um json. a ideia é replicar também o que vemos na imagem. nela podemos ver que escolhemos o tipo, damos um nome e, principalmente, descrevemos o significado do parâmetro, útil para o llm usando a tool. também indicamos se é um atributo requerido. a imagem 5 dá uma ideia disso."

## Clarifications

### Session 2026-08-26

- Q: When editing an existing tool configured with Bearer Token, Basic Auth, or API Key credentials, how should the existing secret values (tokens, passwords, keys) be displayed in the modal? → A: Show a masked placeholder (e.g., `••••••••`) and preserve existing credentials unless the user types a new value.
- Q: When a user types a parameter name in the visual builder that contains spaces or special characters, how should the input be handled? → A: Enforce strict validation error if the name contains spaces or characters other than alphanumeric and underscores.
- Q: Should the tool's authentication type be stored in a new dedicated database column (e.g. `auth_type`) on the Scout Tool record, or should it stay encoded inside the existing encrypted `auth_headers` payload with no schema change? → A: Add a new `auth_type` column to `ichatr_scout_tools` via migration; `auth_headers` continues to store only the encrypted credential values (not the auth type itself).
- Q: Does `auth_headers` still need to support arbitrary custom headers unrelated to authentication (e.g. `Content-Type`, a static `X-Request-ID`), or does this feature replace the free-form headers field entirely with the 4 standard auth methods? → A: Auth configuration is scoped to authentication only going forward; there is no mechanism to add new non-auth custom headers via the UI. Existing non-standard header values on legacy tools are preserved as-is when loaded/edited (per User Story 4), but cannot be extended with additional arbitrary headers.
- Q: Does the visual parameter builder fully replace raw JSON Schema editing (no way back to hand-written JSON), or should there be an "Advanced/raw JSON" fallback mode? → A: Full replacement — no raw JSON fallback mode. `Object` and `Array` remain selectable parameter types, but this feature does not support authoring their nested/inner property structure through the UI (out of scope for now).
- Q: For a legacy tool whose existing headers don't cleanly map to any single auth type, must the system preserve the original `auth_headers` payload untouched on save, or can saving force resolution into one of the 4 standard shapes? → A: Not applicable — this feature has not shipped to production yet, so there is no legacy/production data to preserve. Development is free to redefine tool data as needed; strict backward-compatibility/data-preservation safeguards for existing rows are unnecessary. User Story 4 is descoped to a best-effort convenience (auto-detecting Bearer/Basic/JSON-Schema patterns already present in dev-created tools) rather than a mandatory no-data-loss guarantee.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visual Parameter Builder for Custom Tools (Priority: P1)

An account administrator or agent configuring a custom tool for Scout defines the expected inputs through an intuitive visual parameter builder instead of manually writing raw JSON Schema syntax. For each parameter, the user specifies a name, selects a data type, provides a human-readable semantic description explaining the parameter's purpose and usage, and marks whether the parameter is required. The system automatically structures these parameters so the Scout AI agent understands how and when to extract values from user conversations.

**Why this priority**: Writing raw JSON Schema is error-prone, intimidating for non-technical business operators, and easily leads to syntax mistakes that break AI tool invocations. A visual builder makes tool parameter creation accessible, self-documenting, and reliable.

**Independent Test**: Can be fully tested by creating a new custom tool, adding multiple parameters with different types, descriptions, and required states via the UI builder, and confirming the tool is saved and provides the expected parameter descriptions to the AI model.

**Acceptance Scenarios**:

1. **Given** a user is creating or editing a custom tool, **When** they click "Add Parameter", **Then** a new parameter card appears allowing them to input the parameter name, select its type, write a description, and toggle its required status.
2. **Given** a parameter card with filled fields, **When** the user marks the parameter as "Required", **Then** the parameter is marked as mandatory for tool execution.
3. **Given** a user has added multiple parameters, **When** they click the delete icon on any parameter card, **Then** that parameter is removed from the tool configuration.
4. **Given** a tool configured with structured parameters, **When** the tool is saved, **Then** the parameters are stored with their name, type, description, and required flag, and properly exposed to the Scout AI agent for parameter extraction.

---

### User Story 2 - Standardized HTTP Authentication Methods (Priority: P1)

An account administrator configuring an external API tool selects a standard authentication method from a predefined list (None, Bearer Token, Basic Auth, API Key) and fills in the dedicated credential fields. The system securely encrypts and stores the credentials, automatically formatting and transmitting the necessary HTTP headers during tool execution without exposing sensitive tokens in plain text.

**Why this priority**: Most external business APIs (CRMs, ERPs, payment gateways) require authentication. Manually crafting JSON headers is cumbersome and risks exposing API secrets or formatting errors. Providing standard authentication types simplifies integration and ensures credentials are securely managed.

**Independent Test**: Can be fully tested by configuring a tool with each authentication type (Bearer Token, Basic Auth, API Key), executing a test request, and verifying that the correct authentication headers are sent to the external endpoint.

**Acceptance Scenarios**:

1. **Given** the user selects "None" as the Authentication Type, **When** the tool is saved or executed, **Then** no additional authentication headers are attached to the request.
2. **Given** the user selects "Bearer Token", **When** they provide an authentication token, **Then** the token is securely encrypted, and outgoing requests include the `Authorization: Bearer <token>` header.
3. **Given** the user selects "Basic Auth", **When** they provide a username and password, **Then** the credentials are securely encrypted, and outgoing requests include the `Authorization: Basic <base64(username:password)>` header.
4. **Given** the user selects "API Key", **When** they specify a custom Header Name (e.g., `X-API-Key`) and Header Value, **Then** outgoing requests include that custom header and value.
5. **Given** any configured authentication method with sensitive credentials, **When** the tool is persisted, **Then** credentials are encrypted at rest.

---

### User Story 3 - Testing Connection with Configured Authentication and Parameters (Priority: P2)

While creating or editing a custom tool, the user tests the endpoint connection directly in the configuration modal. The test runner uses the selected authentication method and dynamically generates test payload templates based on the visually configured parameters, allowing the user to verify the external API response and response template formatting before saving.

**Why this priority**: Users need immediate feedback on whether their endpoint URL, credentials, parameters, and optional response templates work against the live API, avoiding trial-and-error in live customer conversations.

**Independent Test**: Can be fully tested by opening the test connection drawer/section inside the tool modal, providing sample parameter values, clicking "Test connection", and inspecting the returned HTTP status, raw response, and formatted response.

**Acceptance Scenarios**:

1. **Given** a tool configured with Bearer, Basic, or API Key authentication, **When** the user clicks "Test connection", **Then** the test request executes using the specified authentication credentials.
2. **Given** a tool with configured parameters, **When** the user views the test payload field, **Then** a sample payload containing all defined parameters with sensible default values for their types is automatically provided.
3. **Given** an external endpoint returns a response, **When** the test finishes, **Then** the HTTP status code, raw response body, and rendered response template (if defined) are displayed clearly in the modal.

---

### User Story 4 - Best-Effort Conversion of Development-Era Tools (Priority: P3)

When a tool created during this feature's own pre-production development (raw headers or raw JSON Schema) is opened for editing, the system makes a best-effort attempt to translate the existing configuration into the new structured authentication and visual parameter formats.

**Why this priority**: This feature has not shipped to production, so there is no production data to protect from loss or breakage. This story is a development convenience (avoid manually re-typing tools created earlier in this same development cycle), not a data-safety guarantee — strict backward compatibility and no-data-loss safeguards are explicitly not required.

**Independent Test**: Can be fully tested by loading a tool created with the pre-feature raw headers/schema fields, verifying that recognizable patterns (Bearer/Basic headers, flat JSON Schema properties) populate correctly in the new modal, and saving it successfully.

**Acceptance Scenarios**:

1. **Given** an existing tool with a standard Bearer or Basic authorization header, **When** the user opens the edit modal, **Then** the Authentication Type dropdown and corresponding credential fields are pre-populated with the existing settings.
2. **Given** an existing tool with a JSON Schema containing properties, **When** the user opens the edit modal, **Then** the parameters are automatically converted and displayed in the visual parameter builder.
3. **Given** an existing tool with custom non-standard headers that do not match any of the 4 standard auth types, **When** the tool is opened for editing, **Then** the Authentication Type defaults to "None" (best-effort; no requirement to preserve or represent the unmatched headers, since no production data depends on this).

---

### Edge Cases

- **Empty Parameter Name**: What happens if the user creates a parameter row but leaves the parameter name blank? The form validation must flag the empty field and prevent saving until all parameter names are specified.
- **Duplicate Parameter Names**: What happens if two parameters share the exact same name? Validation must prevent duplicate parameter names to avoid ambiguous LLM tool schemas.
- **Invalid Characters in Parameter Name**: What happens if parameter names contain spaces or special punctuation? The UI strictly rejects the input and displays a validation error requiring names to use only alphanumeric characters and underscores (e.g. `order_id`).
- **Empty Authentication Credentials**: What happens if "Bearer Token" is selected but the token field is left empty? Form validation must indicate that the token is required for that authentication type.
- **URL Parameter Replacement vs Query/Body Parameters**: When endpoint URLs contain liquid variables (e.g., `https://api.example.com/orders/{{ order_id }}`), parameters defined with matching names are substituted into the URL, while remaining parameters are passed as query parameters (for GET) or body payload (for POST/PUT/PATCH).
- **Special Characters in Basic Auth**: If username or password contains colons or unicode characters, the Basic Auth encoding must handle standard RFC 7617 base64 encoding correctly.
- **No Parameters Defined**: If a tool requires no parameters (e.g., a simple status ping endpoint), saving with zero parameters must be fully supported.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a dedicated "Authentication Type" dropdown in the Scout Custom Tool modal supporting 4 authentication modes:
  - `None`: No authentication header added.
  - `Bearer Token`: Sends the token in the `Authorization: Bearer <token>` header.
  - `Basic Auth`: Sends the username and password in the `Authorization: Basic <base64(user:pass)>` header.
  - `API Key`: Sends a custom header name and header value (e.g., `X-API-Key: secret_value`).
- **FR-002**: System MUST dynamically display the relevant credential input fields based on the selected Authentication Type (token field for Bearer; username and password fields for Basic Auth; header name and header value fields for API Key; none for None). The authentication configuration is scoped exclusively to these 4 modes; the UI MUST NOT expose a general-purpose free-form field for adding arbitrary non-auth custom headers.
- **FR-003**: System MUST securely encrypt all stored authentication credentials and headers at rest. When editing an existing tool with configured credentials, the UI MUST display masked placeholders (e.g., `••••••••`) for secret inputs and preserve the already configured encrypted secrets upon saving unless the user explicitly enters a new secret value.
- **FR-004**: System MUST replace the manual JSON Schema text area with an intuitive visual parameter builder interface. There is no raw JSON Schema fallback/advanced mode; the visual builder is the only way to author parameters going forward.
- **FR-005**: System MUST allow users to add, edit, reorder, and remove parameters dynamically using the visual parameter builder.
- **FR-006**: For each parameter in the visual builder, the user MUST be able to define:
  - `Name`: String identifier of the parameter (e.g., `order_id`, `serial_number`).
  - `Type`: Data type selected from `String`, `Number`, `Integer`, `Boolean`, `Array`, `Object`. For `Array`/`Object`, only the top-level type is selectable; authoring nested/inner item or property structure is not supported by the builder.
  - `Description`: Semantic description explaining the parameter's meaning and context for the LLM.
  - `Required`: Checkbox / toggle determining if the parameter is mandatory.
- **FR-007**: System MUST automatically compile the visual parameter list into a valid JSON Schema object format (`type: 'object'`, `properties`, `required`) for LLM tool invocation and validation.
- **FR-008**: System SHOULD make a best-effort attempt to parse existing (pre-feature, development-era) JSON Schema definitions when editing a tool and populate the visual parameter builder; this is a development convenience, not a guaranteed no-data-loss migration, since no production data exists yet for this feature.
- **FR-009**: System MUST generate an intelligent default test payload in the "Test connection" section based on the defined visual parameters and their types.
- **FR-010**: System MUST execute test connection requests with the selected Authentication Type headers and values applied.
- **FR-011**: System MUST provide bilingual localization (English `en` and Portuguese `pt-BR`) for all new labels, placeholders, helper texts, and validation messages across both frontend and backend.
- **FR-012**: System MUST validate that required authentication fields and parameter names are non-empty before allowing the user to save the tool. System MUST strictly validate parameter names to ensure they contain only alphanumeric characters and underscores (no spaces or special symbols), displaying an inline validation error if invalid. System MUST reject saving a tool that has two or more parameters sharing the exact same name, displaying an inline validation error identifying the duplicate.

### Key Entities *(include if feature involves data)*

- **Scout Tool (`ScoutTool`)**: Represents an external API tool that Scout can invoke.
  - `name`: Human-readable name of the tool.
  - `description`: Overview of what the tool does (used by the AI agent to determine when to call it).
  - `endpoint_url`: Target URL of the external REST API (supports template variables like `{{ order_id }}`).
  - `http_method`: HTTP verb (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`).
  - `auth_type`: The authentication method (`none`, `bearer`, `basic`, `api_key`), stored in a dedicated, non-encrypted database column (added via migration) so it can be read without decryption.
  - `auth_headers`: Securely encrypted credentials / headers hash for the request (holds only credential values, not the auth type).
  - `parameter_schema`: JSON schema specifying the expected properties, descriptions, types, and required fields.
  - `response_template`: Optional liquid template to shape the response for the LLM.
  - `enabled`: Boolean toggle to enable or disable the tool.
- **Tool Parameter Definition**: Visual configuration element representing one parameter:
  - `name`: Identifier of the parameter.
  - `type`: Data type (`string`, `number`, `integer`, `boolean`, `array`, `object`).
  - `description`: Contextual explanation for the LLM on what this value represents and how to obtain it.
  - `required`: Boolean indicating whether the parameter must be provided.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can configure and save a fully authenticated custom tool with multiple parameters without having to write raw JSON Schema or raw JSON header structures.
- **SC-002**: 100% of outgoing requests (both live and test calls) for tools using Bearer Token, Basic Auth, or API Key attach the correct formatted authentication headers.
- **SC-003**: 100% of parameters created in the visual builder are accurately passed to the LLM tool definition with type, description, and required constraints.
- **SC-004**: 100% of user-facing UI labels, placeholders, and error messages are available in both English and Portuguese.
- **SC-005**: Development-era tools with recognizable Bearer/Basic headers or flat JSON Schema properties load into the new modal with those settings pre-populated on a best-effort basis (not a strict no-regression guarantee, since this feature has no production data to protect).

## Assumptions

- The external HTTP tool execution infrastructure (`HttpRequestExecutor` and `SafeFetch`) already exists and supports arbitrary headers and URL interpolation; this feature streamlines and structures the configuration layer and ensures standard auth types are automatically formatted.
- Sensitive credentials (tokens, passwords, API keys) will continue to be encrypted using Rails ActiveRecord encryption (`encrypts :auth_headers`).
- The visual parameter builder covers single-level properties which represent the vast majority of tool calling parameters for LLMs. `Array`/`Object` remain selectable as top-level types, but authoring their nested inner structure is out of scope for this feature (no raw JSON fallback mode exists).
- Form validation occurs on the client before submission, with backend model validation as a safeguard.
- Translation follows the repository's bilingual convention (English and Brazilian Portuguese synchronously updated).
