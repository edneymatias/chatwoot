# Feature Specification: Scout V2 Identity and Style Settings

**Feature Branch**: `086-scout-v2-identity-settings`

**Created**: 2026-09-27

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 13/scoutv2/briefs/12-configuracao-do-scout-v2.md" — Fase 12 of the ScoutV2 epic, depending on Brief 04 (typed Instructions sections and the stored tone / response length / greeting settings) and required before Brief 10 (production flag), whose promotion preflight checks that Role and Scope are filled. Brief 04 left two gaps: (1) the new assistant's Identity section is fixed text — scout name, account name and a generic qualification sentence — and never learns who the assistant is or what the business does, because the new version deliberately does not read the account's legacy free-form Persona; (2) Tone, Response length and Greeting exist on the scout but can only be changed from the server console, because they were kept out of both the settings screen and the settings API. This feature adds two short, named, length-limited fields — Role and Scope — that feed the new version's Identity, and exposes those two plus Tone, Response length and Greeting on the scout settings screen and API, always visible (not gated by the new-version flag) so administrators can fill them in before an account is promoted.

**Terminology**: "The new version" is the Scout V2 engine; "the legacy version" is Scout V1, which keeps answering customers until an account is promoted. "Persona" is the existing free-form field shown today as "Persona and System Prompt", consumed only by the legacy version. "Default Identity" is the exact Identity text the new version produces today. "Style settings" means Tone, Response length and Greeting together.

## Clarifications

### Session 2026-09-27

- Q: When Role or Scope is filled, does its text replace the matching Default Identity statement or get added to the full default text? → A: Each field independently replaces only its matching statement. The introduction naming the scout and the account is always present. With Role filled, the introduction becomes neutral ("Você é {scout name}, assistente da empresa {account name}.") and is followed by the Role text; the "assistente inteligente de qualificação comercial e vendas" qualifier and the generic purpose statement ("Seu objetivo é qualificar leads…") are removed. With Scope filled, its text replaces the generic scope statement ("Você deve responder apenas sobre os produtos, serviços…"). An empty field keeps its default statement; both empty yields today's Identity byte-for-byte. Anti-hallucination and commercial-scope rules are not part of Identity: they stay in the Safety section, which is unchanged and always present.
- Q: When Role or Scope contains line breaks, does the text enter the Identity section with its line breaks as typed or collapsed into a single line? → A: As typed. The only normalization is removing leading and trailing whitespace and line breaks. Each field sits in its own block at the position of the default statement it replaces, so a list written by the administrator (e.g. "- não informa preços de tratamento" on one line and "- não agenda urgências" on the next) reaches the model as a list. The 500-character limit counts the stored text including line breaks. Greeting keeps its existing single-line collapsing. Identity tests compare text with internal line breaks preserved.
- Q: Does the Role/Scope counter on the screen show characters used or characters remaining? → A: Used over the limit, in the "123 / 500" format, from the shared text-area component the screen already uses for Persona (with its character counter enabled and a 500-character limit). The component gains no "remaining" mode. Typing stops at the limit and the counter stops at "500 / 500". "Remaining" and "reaches zero" are removed from the spec.
- Q: Does the API accept Tone and Response length only by name, or also by their internal number? → A: Only by name, as a string from the documented list (friendly, neutral, matter_of_fact, professional, humorous; concise, standard, thorough). The internal number is rejected both as an integer (1) and as a numeric string ("1"). The check happens at the request boundary, before the value reaches the scout record, because the default enum conversion silently turns the integer 1 into neutral and the record-level validation does not catch it. These values get the same invalid-request response and translated out-of-list message, and nothing is saved. API responses keep returning both fields by name. SC-006 tests include 1 and "1" among the values that must be rejected.
- Q: What does the API store and return for Role and Scope: the text exactly as sent, or with leading/trailing whitespace removed? → A: The scout record stores Role and Scope with leading/trailing whitespace and line breaks already removed, and the API returns the stored value. There is a single normalization on the scout record (Rails native `normalizes`): it strips the ends and stores null when nothing remains, so it applies to every write path (API, screen, console). A whitespace/line-break-only text is stored as empty (null), same as a never-filled field: Identity uses the default statement and Brief 10's preflight counts it as empty. Internal line breaks stay as typed. The 500-character limit is checked after normalization, so leading/trailing whitespace does not count. Identity uses the stored value without further treatment; the end-trimming from the line-breaks answer above is fulfilled by this normalization on write. API tests compare responses against the trimmed text and verify a whitespace-only text comes back as null.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The new version introduces itself with the account's own Role and Scope (Priority: P1)

An administrator describes, in two short named fields, what the assistant is for (Role — e.g. "SDR for a solar-panel installer serving homeowners in São Paulo") and what it may and may not talk about (Scope — e.g. "only residential installations; never quote financing rates"). From then on, every reply the new version generates is guided by an Identity section that carries both texts alongside the fixed introduction (scout name and account name). A scout whose Role and Scope are still empty keeps producing exactly the Default Identity it produces today. Nothing written in Persona ever reaches the new version, and the legacy version keeps using Persona exactly as it does today.

**Why this priority**: Without it, promoting an account to the new version silently erases from the assistant's instructions its name, the audience it serves and what it must not do — the core of what makes the assistant belong to that business. This is also the content Brief 10's promotion preflight checks for.

**Independent Test**: Can be fully tested by setting Role and Scope on a scout (directly on the record, no screen needed), generating the new version's instructions and confirming the Identity section contains both texts; clearing them and confirming the Identity section equals the Default Identity; filling Persona with a distinctive marker and confirming the marker appears nowhere in the new version's instructions while the legacy version's instructions are unchanged.

**Acceptance Scenarios**:

1. **Given** a scout with both Role and Scope filled, **When** the new version builds its instructions, **Then** the Identity section contains the neutral introduction naming the scout and the account, followed by the Role text and the Scope text, and contains none of the default qualifier, the default purpose statement or the default scope statement.
2. **Given** a scout with both Role and Scope empty, **When** the new version builds its instructions, **Then** the Identity section is identical to the Default Identity.
3. **Given** a scout with only Role filled, **When** the new version builds its instructions, **Then** the Identity section contains the neutral introduction followed by the Role text in place of the default qualifier and purpose statement, and keeps the default scope statement.
4. **Given** a scout with only Scope filled, **When** the new version builds its instructions, **Then** the Identity section keeps the default introduction (with its qualifier) and the default purpose statement, and contains the Scope text in place of the default scope statement.
5. **Given** a scout whose Persona contains a distinctive text, **When** the new version builds its instructions, **Then** that text appears in no section of those instructions.
6. **Given** a scout with Role, Scope and style settings filled, **When** the legacy version builds its instructions, **Then** they are identical to what it produced before this feature, with Persona in the same place.

---

### User Story 2 - Administrators configure Identity and style from the scout settings screen (Priority: P2)

On the scout's general settings screen, alongside the existing name, Persona, response delay and quota fields, the administrator finds a section for the new version with Role, Scope, Tone, Response length and Greeting. Role and Scope are multi-line text fields with a counter showing characters used over the 500-character limit (e.g. "123 / 500"). Tone and Response length are picked from closed lists whose options are shown with translated labels. Greeting is a free text field whose help text advises leaving it blank when the inbox already sends its own greeting. Help texts make clear these settings apply to the new version of the Scout. The section is shown for every scout, whether or not the account already runs the new version. Saving persists all five values together with the rest of the form, and the very next reply the new version generates reflects them — no console access needed. Everything is available in English and Brazilian Portuguese.

**Why this priority**: Brief 04 made the style settings effective but left them console-only, and User Story 1 adds two more fields that are useless if an administrator cannot fill them. Showing them regardless of the flag is what lets administrators prepare an account before promotion instead of after the new version is already answering customers. It depends on User Story 1 for Role and Scope to have any effect.

**Independent Test**: Can be fully tested by opening the settings screen of a scout on an account still running the legacy version, confirming all five fields are visible with their help texts in both languages, changing each of them, saving, reloading the screen to confirm the values persisted, and then running a playground turn on the new version to confirm the Identity and Communication sections reflect the saved values.

**Acceptance Scenarios**:

1. **Given** an account not yet promoted to the new version, **When** an administrator opens a scout's general settings, **Then** Role, Scope, Tone, Response length and Greeting are visible, each with help text indicating it applies to the new version of the Scout.
2. **Given** an account already promoted to the new version, **When** an administrator opens a scout's general settings, **Then** the same five fields are visible in the same way.
3. **Given** the settings screen, **When** the administrator opens the Tone list, **Then** it offers exactly the five supported tones (friendly, neutral, matter-of-fact, professional, humorous) with translated labels, and the Response length list offers exactly the three supported lengths (concise, standard, thorough) with translated labels.
4. **Given** the administrator changed all five fields, **When** they save, **Then** the saved values are shown after reloading the screen and the next new-version reply is built from them.
5. **Given** the settings screen, **When** the administrator reads the Greeting help text, **Then** it advises leaving Greeting blank if the inbox already sends its own greeting.
6. **Given** a scout that already had values for the style settings set through the console, **When** the administrator opens the settings screen, **Then** those existing values are pre-selected / pre-filled.
7. **Given** the screen is shown in English or in Brazilian Portuguese, **When** the administrator views the section, **Then** every label, option, placeholder and help text is in that language.
8. **Given** the Role or Scope field, **When** the administrator types beyond 500 characters, **Then** the field does not accept the extra characters and the counter shows "500 / 500".

---

### User Story 3 - Invalid Identity or style values are rejected at the settings API without saving anything (Priority: P3)

Any client of the scout settings API (the screen, or an integration) can set Role, Scope, Tone, Response length and Greeting on scout creation and update. A Tone or Response length outside the supported lists, or a Role or Scope longer than 500 characters, is rejected as an invalid request with a translated message naming the problem, and nothing from that request is saved — not even the other, valid fields sent alongside it.

**Why this priority**: The screen already constrains input (User Story 2), so this guards only non-screen clients and tampering. It is still required so that malformed input never reaches the new version's instructions or produces an unhandled error, but it adds no new capability for administrators using the screen.

**Independent Test**: Can be fully tested through the settings API alone: send each of the five fields with a valid value and confirm they are stored and returned; send an unsupported Tone, an unsupported Response length, and a 501-character Role and Scope, each alongside a valid name change, and confirm every one is rejected with a translated message and the scout is unchanged.

**Acceptance Scenarios**:

1. **Given** an existing scout, **When** an update sets valid values for Role, Scope, Tone, Response length and Greeting, **Then** all five are stored and returned in the response.
2. **Given** a new scout being created, **When** the creation request includes valid values for the five fields, **Then** the scout is created with those values.
3. **Given** an existing scout, **When** an update sends a Tone or Response length that is not one of the supported names, including an internal number sent as an integer (1) or as a numeric string ("1"), **Then** the request is rejected as invalid with the translated out-of-list message and no field of the scout changes.
4. **Given** an existing scout, **When** an update sends a Role or Scope that is still longer than 500 characters after removing leading/trailing whitespace and line breaks, **Then** the request is rejected as invalid with a translated message and no field of the scout changes.
5. **Given** an existing scout, **When** an update sends a Role or Scope of exactly 500 characters after removing leading/trailing whitespace and line breaks, **Then** it is accepted and stored, even if the text as sent was longer because of those ends.
6. **Given** a scout's settings are read through the API, **When** the response is returned, **Then** it includes the current Role, Scope, Tone, Response length and Greeting.
7. **Given** an existing scout, **When** an update sends a Role or Scope with leading/trailing whitespace or line breaks, **Then** the stored and returned value has those ends removed and its internal line breaks intact; **and When** the text is only whitespace or line breaks, **Then** it is stored and returned as null.

---

### Edge Cases

- **Whitespace-only Role or Scope**: stored as empty (null) on every write path, exactly like a never-filled field; the new version falls back to the corresponding Default Identity statement and Brief 10's preflight counts it as empty.
- **Clearing a previously filled Role or Scope**: saving an empty value restores the corresponding Default Identity statement on the next reply.
- **Scout with Persona filled but Role and Scope empty** (every existing scout at rollout): the new version uses the Default Identity; Persona is neither read nor copied into Role/Scope.
- **Style settings never touched**: a scout created before or after this feature without explicit style values keeps the existing defaults (friendly tone, concise responses, no custom greeting), shown pre-selected on the screen.
- **Greeting left blank while the inbox sends no greeting**: the new version keeps its existing behavior of greeting the customer politely in its first reply.
- **Greeting filled while the inbox also greets**: no automatic suppression; the help text is the only safeguard (by decision — see Assumptions).
- **Greeting left empty on the screen**: saved as empty (null), same as a never-filled Greeting; the new version keeps greeting the customer politely in its first reply.
- **Role/Scope containing line breaks**: accepted and preserved; internal line breaks are stored and carried into the Identity section exactly as typed (only leading/trailing whitespace and line breaks are removed, when the value is stored), so an administrator's list arrives as a list. The 500-character limit counts the stored text, including internal line breaks. Greeting's existing collapsing into a single line is unchanged.
- **Request that sends only some of the five fields**: fields not sent are left unchanged.
- **Unsupported Tone or Response length combined with an otherwise valid request that also changes required custom attributes**: the whole request is rejected; nothing is saved.
- **Tone or Response length sent as its internal number** (integer 1 or string "1"), **as an empty string, or as null**: rejected at the request boundary with the same message as any out-of-list value, even when the number maps to a supported value internally; nothing is saved.
- **Rolling back an account from the new version to the legacy version**: the legacy version behaves exactly as before this feature, because it never reads Role, Scope or the style settings and Persona was never modified.

## Requirements *(mandatory)*

### Functional Requirements

**Identity (new version)**

- **FR-001**: Each scout MUST have two optional text settings, Role and Scope, each limited to 500 characters. On every write path (API, screen, console), Role and Scope MUST be stored with leading/trailing whitespace and line breaks removed and internal line breaks kept as typed; a value left empty by this removal MUST be stored as empty (null). The 500-character limit MUST be checked on the stored (normalized) value.
- **FR-002**: The new version's Identity section MUST always open with an introduction naming the scout and the account. When Role is empty, this is the Default Identity introduction, including the "assistente inteligente de qualificação comercial e vendas" qualifier; when Role is filled, it is the neutral introduction "Você é {scout name}, assistente da empresa {account name}."
- **FR-003**: When Role is filled, the Role text MUST immediately follow the introduction (FR-002), and the Identity section MUST NOT contain the default qualifier or the default purpose statement; when Role is empty, the default purpose statement of the Default Identity MUST follow the default introduction.
- **FR-004**: When Scope is filled, the new version's Identity section MUST contain the Scope text in place of the default scope statement; when Scope is empty, it MUST contain the default scope statement of the Default Identity. Anti-hallucination and commercial-scope rules are not part of Identity: the Safety section carries them, is not changed by this feature, and MUST remain present regardless of Role and Scope.
- **FR-004a**: Role and Scope MUST each appear in the Identity section as a block of their own, at the position of the default statement they replace, using the stored value as-is (internal line breaks preserved, no further treatment).
- **FR-005**: When both Role and Scope are empty, the new version's Identity section MUST be identical to the Default Identity.
- **FR-006**: The new version MUST NOT include any content from Persona in any part of its instructions.
- **FR-007**: The legacy version's instructions MUST be unchanged by this feature, including the placement and content of Persona; the legacy version MUST NOT read Role, Scope or the style settings.
- **FR-008**: Persona MUST remain stored, editable and consumed by the legacy version exactly as today; this feature MUST NOT copy, transform or migrate Persona content into Role or Scope.

**Settings API**

- **FR-009**: The scout settings API MUST accept Role, Scope, Tone, Response length and Greeting on scout creation and update, and MUST return all five when a scout is read, created or updated.
- **FR-010**: The API MUST accept Tone and Response length only as a string name from the documented lists — Tone: friendly, neutral, matter_of_fact, professional, humorous; Response length: concise, standard, thorough — and MUST reject any other value as an invalid request, including the internal number sent as an integer (e.g. 1) or as a numeric string (e.g. "1"). This check MUST happen at the request boundary, before the value reaches the scout record. API responses MUST return both fields by name.
- **FR-011**: The API MUST reject, as an invalid request, a Role or Scope that exceeds the FR-001 limit after normalization, and MUST accept one of exactly 500 characters. The API MUST return Role and Scope as stored per FR-001 (trimmed, or null when empty).
- **FR-012**: A rejected request MUST leave the scout completely unchanged, including any valid fields and required-attribute changes sent in the same request.
- **FR-013**: Rejection messages for invalid Tone, Response length, Role and Scope MUST be translated into English and Brazilian Portuguese according to the requester's language.

**Settings screen**

- **FR-014**: The scout general settings screen MUST show Role, Scope, Tone, Response length and Greeting for every scout, regardless of whether the account runs the new version.
- **FR-015**: Role and Scope MUST be multi-line text inputs that prevent entering more than 500 characters and show a counter of characters used over the limit (e.g. "123 / 500").
- **FR-016**: Tone and Response length MUST be selectable only from closed lists containing exactly the supported values, each shown with a translated label.
- **FR-017**: Each of the five fields MUST have help text indicating that it applies to the new version of the Scout; the Greeting help text MUST additionally advise leaving it blank when the inbox already sends its own greeting.
- **FR-018**: The screen MUST pre-fill the five fields with the scout's current values and MUST send them on save together with the other general settings.
- **FR-019**: After a successful save, the next reply generated by the new version for that scout MUST reflect the saved Role, Scope, Tone, Response length and Greeting, without any console intervention.
- **FR-020**: Persona MUST remain on the screen with its current label, placeholder and help text.
- **FR-021**: All new labels, options, placeholders and help texts MUST be available in English and Brazilian Portuguese.

### Key Entities *(include if feature involves data)*

- **Scout**: the per-account AI sales assistant. Gains **Role** (what the assistant is for — purpose, business, audience; ≤500 characters, optional) and **Scope** (what it may and may not talk about; ≤500 characters, optional). Already holds **Tone** (one of five supported tones, default friendly), **Response length** (one of three supported lengths, default concise), **Greeting** (optional free text used in the first reply) and **Persona** (legacy free-form instructions, legacy version only, untouched).
- **Identity section**: the part of the new version's instructions stating who the assistant is and what it covers; composed of the introduction naming the scout and the account (neutral when Role is filled) plus Role and Scope, each replacing only its matching Default Identity statement and falling back to it independently when empty.
- **Communication section**: the part of the new version's instructions carrying Tone, Response length and Greeting as fixed directives (unchanged by this feature; only now editable from the screen).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An administrator can set Role, Scope, Tone, Response length and Greeting for a scout from the settings screen and save in under 3 minutes, with zero console steps.
- **SC-002**: In 100% of new-version replies generated after a save, the instructions reflect the saved Role, Scope and style settings.
- **SC-003**: For a scout with both Role and Scope empty, the new version's Identity section is byte-for-byte identical to the one produced before this feature.
- **SC-004**: For every scout, the legacy version's instructions are byte-for-byte identical before and after this feature ships (given unchanged Persona and scout data).
- **SC-005**: 0 occurrences of Persona content in the new version's instructions across all tested scouts.
- **SC-006**: 100% of API requests carrying an unsupported Tone or Response length (including the internal numbers 1 and "1"), or a Role/Scope over 500 characters, are rejected with a translated message and leave the scout unchanged; none produce an unhandled error.
- **SC-007**: 100% of the new screen text is available in both English and Brazilian Portuguese.

## Assumptions

- **Default Identity decomposition** (confirmed in Clarifications, 2026-09-27): today's Identity consists of three statements: the introduction (scout name, account name and the "assistente inteligente de qualificação comercial e vendas" qualifier), a purpose statement (qualify leads, answer product questions, help the sales process) and a scope statement (answer only about the products, services and information provided). Role replaces the qualifier and the purpose statement, leaving a neutral introduction; Scope replaces the scope statement; each field falls back independently.
- **Greeting length**: no new length limit is introduced for Greeting; the 500-character limit applies only to Role and Scope, as the brief states.
- **Whitespace**: leading/trailing whitespace and line breaks in Role and Scope are removed once, when the value is stored; internal line breaks and spacing are kept as typed; whitespace-only values are stored as empty (null).
- **No automatic inbox-greeting deduplication**: the brief's decision is to rely on help text only; the new version does not inspect whether the inbox sends its own greeting.
- **Permissions**: the users who can edit a scout's general settings today are the same users who can edit the five new fields; no permission change.
- **Existing scouts**: all existing scouts start with empty Role and Scope and keep whatever style values they have (defaults unless set via console); no data migration.
- **Out of scope** (per brief): removing or renaming Persona (Brief 10 deprecation); gating fields on the new-version flag or exposing which engine an account runs (Brief 10); a migration assistant suggesting Role/Scope from Persona; a custom/free-text tone; any change to the legacy version.
- **Dependencies**: Brief 04 (Identity/Communication sections and stored Tone/Response length/Greeting) is delivered. Brief 10's promotion preflight will consume Role/Scope emptiness but is not part of this feature.
