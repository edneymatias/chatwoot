# Feature Specification: Scout Tool "Test" Uses Real Saved Credential, Not the Masked Placeholder

**Feature Branch**: `080-scout-tool-test-secret`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/36-scout-tool-test-uses-masked-secret/spec-preview.md" — the "Test" action in the External Tool editor always sends the masked secret placeholder (`••••••••`) to the external API instead of the real, previously saved credential, causing the test to fail with 401/403 even when the tool's saved credential is correct.

## Clarifications

### Session 2026-09-23

- Q: When a "Test" request names a saved tool by ID, but that ID doesn't resolve to a real tool the requesting account can access (deleted, mistyped, or belonging to a different account), what should the system do? → A: Treat it as if there's no saved tool to fall back to — proceed using exactly the submitted value, same as testing a brand-new unsaved tool (no substitution, no distinct error).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Testing an already-configured tool without retyping the credential (Priority: P1)

An operator opens an existing external tool in the tool editor to verify it still works (e.g. after the account admin fixed the credential directly, or just to sanity-check configuration). The credential field displays the masked placeholder, as it always has. The operator clicks "Test" without touching the credential field and expects the test to exercise the real, currently saved credential against the real external endpoint.

**Why this priority**: This is the exact failure the operator hit — "Test" is unusable for any already-saved tool unless the credential is pasted in again every time, defeating the purpose of a quick verification action and creating false-negative signals about a tool's health.

**Independent Test**: Can be fully tested by saving a tool with a known-good credential, opening it for edit without changing the credential field, clicking "Test", and confirming the request sent to the external endpoint carries the real saved credential value (not the placeholder).

**Acceptance Scenarios**:

1. **Given** an existing external tool with a valid saved credential, **When** the operator opens it for edit and clicks "Test" without modifying the credential field, **Then** the test request to the external API uses the real saved credential and the result reflects the external API's actual response (success or failure), never an automatic failure caused by sending the placeholder.
2. **Given** an existing external tool with a valid saved credential, **When** the operator clears the credential field entirely (leaving it blank) and clicks "Test" without entering a new value, **Then** the test still uses the real saved credential (blank is treated the same as an untouched/masked field).
3. **Given** an existing external tool, **When** the operator types a brand-new credential value into the field (replacing the masked placeholder) and clicks "Test" before saving, **Then** the test uses the newly typed value, not the previously saved one — so operators can validate a new credential before committing it.

---

### User Story 2 - Testing a brand-new, not-yet-saved tool still requires the real credential (Priority: P2)

An operator is creating a new external tool that has never been saved. There is no saved credential to fall back to. The operator must type the real credential into the field for "Test" to work, exactly as today.

**Why this priority**: This is the regression guard for the fix in User Story 1 — the reconciliation behavior must only apply when a real saved secret actually exists to fall back to; it must not silently let an unsaved tool "pass" a test with a blank or placeholder credential, and it must never pull in a saved credential belonging to a different tool.

**Independent Test**: Can be fully tested by starting a new tool (unsaved), leaving the credential field empty or with only placeholder-looking content, clicking "Test", and confirming the test proceeds with exactly what was typed (no substitution occurs) — so an empty/placeholder credential still produces the same outcome it does today (the external call is attempted with that literal value, or the request is rejected by existing required-field validation, per current behavior).

**Acceptance Scenarios**:

1. **Given** a new, unsaved external tool, **When** the operator enters a real credential value and clicks "Test", **Then** the test uses exactly the typed value, unchanged.
2. **Given** a new, unsaved external tool, **When** the operator clicks "Test" without entering a credential, **Then** no saved credential is substituted (there is none to substitute), and behavior matches what happens today when testing with an empty credential field.

---

### User Story 3 - Masked credentials never leak in plain text through any read (Priority: P3)

Regardless of the fix to "Test", nothing about how the system displays saved tools changes: viewing a tool's list or detail still shows only the masked placeholder for any configured secret, never the real value.

**Why this priority**: This is the non-regression boundary explicitly called out by the operator's own diagnosis — the masking behavior is correct and must be preserved exactly; only the "Test" action's blind spot is being closed.

**Independent Test**: Can be fully tested by saving a tool with a real credential and confirming that listing tools and viewing a single tool's details both return only the masked placeholder for the credential field, with no code path introduced by this fix that returns the real value in a read response.

**Acceptance Scenarios**:

1. **Given** an external tool with a saved credential, **When** the operator views the tool list or opens the tool for edit, **Then** the credential field shows only the masked placeholder, never the real value.

---

### Edge Cases

- Operator edits an existing tool's non-credential fields (e.g. endpoint URL) while leaving the credential field masked/untouched, then clicks "Test" — the real saved credential is still used; the credential fallback is independent of which other fields changed.
- A tool belongs to account A; an operator cannot cause a "Test" request to resolve or use the saved credential of a tool belonging to a different account.
- Operator tests an existing tool whose saved credential is itself currently invalid/expired — the test correctly reports the real external failure (e.g. 401/403 from the actual API), which is a legitimate result, not a symptom of this bug.
- Operator opens an existing tool, clears the credential field, types a few characters, deletes them all again (ending up blank), then clicks "Test" — treated as untouched/blank, falls back to the real saved credential.
- A "Test" request references a tool id that does not resolve to a real, accessible saved tool for the requesting account (deleted, mistyped, or belonging to a different account) — the system treats this exactly like testing a brand-new unsaved tool: no credential substitution occurs, and no distinct error or response shape reveals whether the id exists in another account.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST let an operator test an already-saved external tool without re-entering its credential, using the tool's real saved credential value for the test request.
- **FR-002**: When testing an existing tool, if the submitted credential value is the masked placeholder or is blank, the system MUST substitute the tool's real saved credential before contacting the external endpoint.
- **FR-003**: When testing an existing tool, if the submitted credential value is neither the masked placeholder nor blank (i.e. the operator typed something new), the system MUST use that newly submitted value as-is, without substituting the saved credential.
- **FR-004**: The system MUST be able to identify which existing tool is being tested so it can look up the correct saved credential to fall back to.
- **FR-005**: The system MUST scope the saved-credential lookup used for testing to the tool's own account; a test request MUST NOT be able to resolve or use the saved credential of a tool belonging to a different account, or of a different tool within the same account.
- **FR-006**: For a tool that has not yet been saved, the system MUST NOT substitute any saved credential when testing (none exists) — the test MUST proceed using exactly what the operator submitted, matching current behavior for new tools.
- **FR-007**: The system MUST continue to return only the masked placeholder for saved credentials in every read operation (listing tools, viewing a tool) — this fix introduces no new way for a real credential to appear in a response.
- **FR-008**: When a "Test" request's tool id does not resolve to a real, accessible saved tool for the requesting account (deleted, mistyped, or belonging to a different account), the system MUST treat the request exactly as it treats a brand-new unsaved tool (per FR-006): no credential substitution, and no response difference that would reveal whether the id exists in another account.

### Key Entities

- **External Tool (Scout Tool)**: A configured integration an account uses to let its Scout call an external API; holds connection details (endpoint, method) and a credential/secret used to authenticate to that external API. Displays its credential only in masked form once saved; belongs to exactly one account.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of "Test" attempts against an already-saved, correctly-configured external tool, performed without retyping the credential, exercise the real external API and reflect its actual response — none fail solely because a placeholder value was sent.
- **SC-002**: Operators can verify a saved external tool's credential validity in a single "Test" click, with zero need to copy/paste the credential back into the form.
- **SC-003**: Zero instances of a real (unmasked) credential value appearing in any list/detail read response for a saved tool, before or after this change.
- **SC-004**: Testing a brand-new, not-yet-saved external tool behaves identically to today — 0 behavior change for that path.

## Assumptions

- The existing masking marker and the existing rule for treating a submitted credential as "unchanged" (equal to the masked placeholder, or blank) are reused as-is for the "Test" action, rather than introducing a new or different rule — this mirrors the rule already in place and proven for the "Save" action, per the operator's own diagnosis.
- "Testing before saving" (User Story 1, scenario 3) is in scope: an operator editing an existing tool who types a genuinely new credential value can test that new value immediately, without first saving it, consistent with how a freshly typed non-masked value is already treated on Save.
- Multi-tenant account scoping for the credential lookup follows the same account boundary already enforced elsewhere for this tool (i.e. no new cross-account exposure is introduced).
- No change to the credential input fields, form layout, or wording is required by this fix beyond making "Test" behave correctly.
