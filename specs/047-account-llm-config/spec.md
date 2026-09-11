# Feature Specification: Account-Level LLM Configuration

**Feature Branch**: `047-account-llm-config`

**Created**: 2026-08-21

**Status**: Draft

**Input**: User description: "/speckit-specify @[docs/kanban/ciclo 10/scout/06-account-llm-config/spec70.md]"

## Clarifications

### Session 2026-08-21

- Q: How should the system handle Scout creation, tools, and execution if the account has not yet configured its LLM credentials? → A: A valid and tested account-level LLM configuration is a mandatory prerequisite for creating Scouts, configuring Scout tools, and running agent operations; unconfigured accounts are gated from these features until valid credentials are saved.
- Q: How should the system test and validate the API key during the configuration process? → A: Automatic validation on save via a lightweight provider API test call; rejects invalid credentials immediately with a clear error without persisting broken keys.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure Account LLM Provider (Priority: P1)

Administrators need to configure a single LLM provider (Gemini, OpenAI, or Anthropic) for their entire account so that all Scouts in the account use the same underlying LLM API key and model.

**Why this priority**: Core functionality; without an API key configured at the account level, Scouts cannot function.

**Independent Test**: Can be fully tested by logging in as an administrator, navigating to the Scout Settings page, and successfully saving a provider, model, and API key.

**Acceptance Scenarios**:

1. **Given** I am an administrator, **When** I navigate to the Scout submenu and click "Configurações" (Settings), **Then** I see a form to select the provider, enter a model name, and provide an API key.
2. **Given** I am an administrator filling out the Scout Settings form, **When** I save the form with valid data, **Then** the configuration is saved for the whole account.
3. **Given** I am a non-administrator user, **When** I view the Scout submenu, **Then** I do not see the "Configurações" option.

---

### User Story 2 - Create or Edit a Scout (Priority: P2)

Users creating or editing a Scout should not be prompted for provider, model, or API key, as these are now inherited from the account-level configuration.

**Why this priority**: Streamlines the Scout creation process and enforces the new account-level rule.

**Independent Test**: Can be fully tested by opening the create/edit Scout dialog and verifying the absence of LLM configuration fields.

**Acceptance Scenarios**:

1. **Given** I am managing Scouts, **When** I open the dialog to create a new Scout, **Then** I am not asked for a provider, model name, or API key.
2. **Given** a Scout interacts via chat, **When** it processes a message, **Then** it uses the account-level LLM configuration instead of a per-Scout configuration.

### Edge Cases

- What happens when an account has no LLM configuration set and an agent tries to access Scout features (creation, tools)? System displays an empty/gating state guiding the administrator to complete LLM configuration first.
- What happens if an administrator tries to save the configuration with a missing provider, model, or invalid API key? System rejects the save and displays appropriate validation errors.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow administrators to configure exactly one LLM provider, model name, and API key per account.
- **FR-002**: System MUST enforce that the provider is one of: Gemini, OpenAI, or Anthropic.
- **FR-003**: System MUST securely encrypt and store the API key at the account level.
- **FR-004**: System MUST NOT allow per-Scout overrides for the LLM provider, model, or API key.
- **FR-005**: System MUST present the Scout submenu with "Agentes", "Configurações", and "Ferramentas" as sibling entries.
- **FR-006**: System MUST restrict access to the "Configurações" (Settings) page to administrators only.
- **FR-007**: System MUST use the account-level LLM configuration for all Scout chat interactions.
- **FR-008**: System MUST require a valid, tested account-level LLM configuration as a prerequisite before allowing Scout creation and Scout tool management.
- **FR-009**: System MUST gate or guide unconfigured accounts to the LLM settings page when attempting to access Scout agent creation or tools.
- **FR-010**: System MUST automatically validate provider credentials on save via a test call to the provider API, rejecting invalid credentials with a descriptive error message and preventing persistence.

### Key Entities *(include if feature involves data)*

- **ScoutAccountConfig**: Represents the account-level LLM configuration. Contains provider type, model name, and the securely stored API key.
- **Account**: The tenant to which the ScoutAccountConfig belongs (one-to-one relationship).
- **Scout**: An agent that relies entirely on the Account's ScoutAccountConfig for its LLM connection.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of newly created Scouts in an account use the same account-level API configuration without prompting the user.
- **SC-002**: Administrator users can successfully update the account LLM configuration, and changes immediately apply to all Scouts in that account.
- **SC-003**: Time taken to create a new Scout is reduced by removing provider and key configuration steps.

## Assumptions

- Existing per-Scout LLM configurations can be discarded safely (no production data exists).
- Mixed providers within one account are explicitly out of scope.
- Super-admin-provisioned credits or billing flows are out of scope.
- Both English and Portuguese translations will be updated synchronously for the new UI elements.
