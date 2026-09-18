# Feature Specification: ERP Integration Foundation & Younus Setup

**Feature Branch**: `074-erp-integration-foundation`

**Created**: 2026-09-17

**Status**: Draft

**Input**: User description: "Fase 01 — Fundação do Framework de Integração ERP e Configuração do Younus (docs/kanban/ciclo 10/01-erp-integration-foundation-and-setup/spec94.md)"

## Clarifications

### Session 2026-09-17

- Q: When the Younus integration is connected, should the API Token be concealed on the settings card so that only the Company ID is displayed? → A: The API Token is displayed masked with dots (`••••••••`), consistent with Chatwoot's standard credential masking, while the Company ID remains visible in cleartext.
- Q: What should be the network timeout for the synchronous ERP connection test during save? → A: 5 seconds, matching the established platform standard for synchronous credential validation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Account-Level ERP Integration Feature Enablement (Priority: P1)

As a Super Admin, I want to enable the ERP Integration feature flag for a specific account so that administrators of that account can view and configure ERP integrations without exposing unreleased or unpermitted capabilities to other accounts.

**Why this priority**: This is the access gateway for the entire feature. Without the account-level feature flag enabled, the ERP integration options remain hidden and inaccessible, preventing unintended exposure across client accounts.

**Independent Test**: Can be tested independently by toggling the `erp_integration` feature flag for a target account in Super Admin and verifying that the unified "ERP" integration card appears in Settings > Integrations for enabled accounts, while remaining completely hidden and inaccessible for non-enabled accounts.

**Acceptance Scenarios**:

1. **Given** an account where `erp_integration` is disabled, **When** an account administrator navigates to Settings > Integrations, **Then** no "ERP" integration card is displayed in the integrations gallery.
2. **Given** an account where `erp_integration` is disabled, **When** a user attempts to navigate directly to the ERP settings URL (`/settings/integrations/erp`), **Then** the application blocks access and redirects the user away, adhering to standard feature-gating behavior.
3. **Given** an account where `erp_integration` has been enabled by a Super Admin, **When** an administrator navigates to Settings > Integrations, **Then** a unified "ERP" integration card is visible in the integrations list.
4. **Given** an account where `erp_integration` is enabled, **When** an administrator clicks the "ERP" integration card, **Then** the application navigates to the ERP provider selection view (`/settings/integrations/erp`).

---

### User Story 2 — ERP Provider Selection and Younus Credential Setup with Live Validation (Priority: P1)

As an Account Administrator, I want to navigate into the ERP integration area, choose Younus as the ERP provider, enter the API Token and Company ID, and have the system synchronously validate the credentials upon saving, so that only authentic and operational connections are saved and enabled.

**Why this priority**: This delivers the core business capability of connecting the platform to the Younus ERP. Live validation guarantees that administrators receive immediate feedback if credentials are mistyped, revoked, or if the external service is down, eliminating silent connection failures.

**Independent Test**: Can be tested independently by navigating to the ERP provider selection page, opening the Younus configuration form, and submitting various credential payloads (blank, invalid credentials, unreachable service, and valid credentials) to verify that connection validation occurs synchronously on save and updates the connection state accurately.

**Acceptance Scenarios**:

1. **Given** the ERP provider selection page (`/settings/integrations/erp`), **When** an administrator views the page, **Then** a list of supported ERP providers is displayed, with "Younus" present as an available provider showing its current connection status (e.g., "Not Configured" or "Disconnected").
2. **Given** an administrator opens the Younus configuration form, **When** the form renders, **Then** input fields for "API Token" (`token`) and "Company ID" (`id_empresa`) are presented as required fields.
3. **Given** an administrator leaves either the API Token or Company ID blank, **When** they attempt to save, **Then** form validation blocks submission and prompts for the missing required field(s) without contacting the remote service.
4. **Given** an administrator inputs an invalid or revoked API Token, **When** they submit the form, **Then** the system synchronously contacts the Younus endpoint, detects authentication rejection (HTTP 401/403), halts the save, leaves the integration unconfigured/disabled, and displays an "Invalid credentials" error message in the form.
5. **Given** an administrator inputs valid credentials but the remote Younus service is temporarily unavailable or returning a server error (e.g., HTTP 503), **When** they submit the form, **Then** the system halts the save, leaves the integration disabled, and displays a distinct "Could not connect to ERP" error message.
6. **Given** an administrator enters a valid API Token and Company ID, **When** they submit the form, **Then** the system confirms valid authentication, persists the configuration, enables the integration, and displays the Younus provider as connected with the Company ID visible in cleartext and the API Token masked with dots (`••••••••`).

---

### User Story 3 — Extensible ERP Provider Framework for Future Providers (Priority: P2)

As a Platform Developer or Administrator expanding integrations, I want the ERP subsystem to adhere to a standardized, pluggable provider architecture with a shared contract and factory, so that new ERP providers can be added in the future without modifying the provider selection UI, the generic configuration form, or core integration management logic.

**Why this priority**: The organization plans to support multiple ERP systems (such as Simples Dental) across different accounts. Establishing a clean provider contract in this initial phase ensures that adding future providers requires only registering metadata and creating an isolated provider adapter, preventing code duplication and architectural drift.

**Independent Test**: Can be tested independently by verifying that the ERP provider factory resolves known provider identifiers to their respective adapters, raises explicit errors when encountering an unregistered provider, and enforces that all provider adapters satisfy the required base contract methods (such as connection verification).

**Acceptance Scenarios**:

1. **Given** an integration configuration with the provider identifier `younus`, **When** the system resolves the provider adapter, **Then** an instance of the Younus provider adapter is returned conforming to the standard ERP base contract.
2. **Given** an integration configuration with an unknown or unregistered provider identifier, **When** the system attempts to resolve the adapter, **Then** an explicit error is raised rather than failing silently or returning an empty reference.
3. **Given** any provider adapter implementing the base ERP contract, **When** a required contract method is invoked on a subclass that failed to implement it, **Then** the system raises a clear capability error naming the missing contract method.

---

### Edge Cases

- **Remote service timeout**: The synchronous validation request enforces a 5-second network timeout. When the external ERP API takes longer than 5 seconds to respond, the system treats the attempt as a connection failure and displays the "Could not connect to ERP" error message.
- **Trailing or leading whitespace in credentials**: If an administrator accidentally pastes an API token or Company ID with surrounding whitespace, the system should sanitize the values prior to validation and storage to avoid false-negative authentication errors.
- **Simultaneous or multiple ERP configurations**: In the event that multiple ERP providers are configured or available, each provider operates as an independent account-level integration; switching active providers follows the standard operational procedure of disabling one provider before enabling another.
- **Special characters in identifiers**: Company IDs or tokens containing hyphens, underscores, or alphanumeric strings are preserved accurately without unexpected truncation or character-encoding corruption.
- **Revocation of account feature flag**: If a Super Admin revokes the `erp_integration` feature flag for an account that already has an enabled Younus integration, the integration remains safely stored in the database but the UI access points and settings views become inaccessible to account administrators until re-enabled.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an account-level feature flag named `erp_integration`, disabled by default and manageable by Super Administrators.
- **FR-002**: When `erp_integration` is disabled for an account, the system MUST hide the "ERP" integration card from Settings > Integrations and restrict access to `/settings/integrations/erp`.
- **FR-003**: When `erp_integration` is enabled for an account, the system MUST display a unified "ERP" card within the Settings > Integrations gallery.
- **FR-004**: Clicking the "ERP" integration card MUST route the administrator to a dedicated ERP Provider Selection view (`/settings/integrations/erp`).
- **FR-005**: The ERP Provider Selection view MUST list all active integrations classified under the `erp` category, displaying "Younus" as an available provider with its current connection state.
- **FR-006**: Selecting "Younus" from the provider selection view MUST open the standard integration configuration form for Younus.
- **FR-007**: The Younus integration configuration schema MUST define two mandatory fields: API Token (`token`) and Company Identifier (`id_empresa`).
- **FR-008**: The system MUST perform synchronous connection validation upon saving the Younus integration record before persisting or activating the configuration.
- **FR-009**: When synchronous validation encounters an authentication failure (HTTP 401 Unauthorized or HTTP 403 Forbidden), the system MUST reject the save and present the user with a localized "Invalid credentials" error message.
- **FR-010**: When synchronous validation encounters a remote server error, service unavailability (e.g., HTTP 503), network failure, or exceeds the 5-second network timeout, the system MUST reject the save and present a distinct localized "Could not connect to ERP" error message.
- **FR-011**: When synchronous validation confirms that the Younus API accepted the credentials, the system MUST persist the integration record in an `enabled` state and display the Company ID in cleartext while masking the API Token with dots (`••••••••`) on connected integration views.
- **FR-012**: The system MUST implement a base ERP adapter contract defining required provider operations, including connection verification (`test_connection`).
- **FR-013**: The system MUST provide an ERP adapter factory that maps provider identifiers to their corresponding adapter classes, raising an explicit error for unknown provider identifiers.
- **FR-014**: Base contract methods MUST raise an explicit capability error if an adapter subclass fails to implement them.
- **FR-015**: The addition of the ERP integration framework MUST NOT alter the behavior, display, or configuration flow of existing integration types (such as Slack, Notion, Shopify, or LeadSquared CRM).
- **FR-016**: All user-facing text, field labels, status badges, and error messages MUST be available synchronously in English (`en.json`, `en.yml`) and Brazilian Portuguese (`pt_BR.json`, `pt_BR.yml`).

### Key Entities

- **ERP Feature Flag**: An account-level setting (`erp_integration`) determining whether the account has access to ERP integrations.
- **ERP Integration Hook**: The persistent account-level integration record storing the provider identifier (`younus`), secure settings (`token`, `id_empresa`), and operational status (`enabled` or `disabled`).
- **ERP Provider Definition**: Metadata identifying an ERP system, including its unique ID, display name, category (`erp`), feature flag dependency, and configuration form schema.
- **ERP Base Adapter**: The abstract contract class establishing the interface and behavioral expectations for all concrete ERP provider adapters.
- **Younus ERP Adapter**: The concrete provider implementation that executes connection verification and communication against the Younus API.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An administrator can complete Younus ERP setup and receive connection confirmation in under 60 seconds when valid credentials are provided (operational usability metric; technical request timeout enforced at 5 seconds per FR-010).
- **SC-002**: 100% of invalid credential attempts (revoked or mistyped tokens/company IDs) are prevented from enabling the integration and display an "Invalid credentials" error.
- **SC-003**: 100% of connection failures caused by remote service downtime or parameter errors (e.g., HTTP 503) produce a distinct "Could not connect to ERP" error message.
- **SC-004**: 0% of accounts without the `erp_integration` flag enabled can access the ERP integration card or provider configuration routes.
- **SC-005**: 100% of existing integrations (Slack, Notion, Shopify, CRM) continue to operate with zero regressions or visual layout breaks.
- **SC-006**: 100% of user-facing strings and error messages are fully localized in both English and Brazilian Portuguese.

## Assumptions

- **Read-only ERP data direction in v1**: Inbound data retrieval from ERP to Chatwoot is the focus of this integration; outbound writes from Chatwoot into the ERP are out of scope for this version.
- **Contact panel visualization deferred to Phase 02**: Presenting customer data retrieved from the ERP inside the contact panel and conversation views is scoped separately for Phase 02 (Feature 075 / spec95) and depends on the hook configured here.
- **Younus API behavior**: The Younus API utilizes a static token provided via request headers, requires a company ID (`id_empresa`), and provides person search via telephone query where a valid token returns an HTTP 200 response with a body status indicator.
- **Synchronous validation on save**: Connection verification is triggered automatically when the administrator saves the configuration form (analogous to the platform's existing OpenAI API key validation pattern), eliminating the need for a separate pre-save test button.
- **Single active ERP provider per account**: Standard operational usage assumes one active ERP provider per account at a time; if an account migrates to a different ERP provider in the future, the operator disables the previous integration before configuring the new one.
