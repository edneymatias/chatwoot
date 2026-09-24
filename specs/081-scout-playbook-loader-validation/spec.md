# Feature Specification: Scout Playbook Loader and Boot Validation

**Feature Branch**: `081-scout-playbook-loader-validation`

**Created**: 2026-09-24

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 13/scoutv2/briefs/01-playbook-loader-e-validacao.md" — Fase 01 of the ScoutV2 epic. Today every new behavior rule for the Scout assistant — including rules that only apply in specific situations — is added to one shared prompt-building codebase (`system_prompts_service.rb` and its guardrails/funnel sections), because there is no unit smaller than "the entire prompt" to name, test, or change independently. This feature introduces "playbooks": versioned files that each declare one situational procedure (when it applies, what tools/capabilities it needs, what steps to follow, how it can end), loaded into a typed, queryable catalog at boot, with the whole set validated up front so a broken reference between playbooks fails loudly before any conversation is served, and the "when does this apply" condition is expressed as small, independently testable, named checks instead of prose.

## Clarifications

### Session 2026-09-24

- Q: Must every playbook file declare a `priority` value, or is `priority` optional with some default when absent? → A: `priority` is required, must be an integer, and unique across the catalog — no default; a file with a missing or non-integer `priority` fails validation the same way as the other boot-validation checks (unregistered condition check, unknown capability, undeclared ending, missing handoff target, duplicate priority).
- Q: Can a valid playbook declare zero endings, or must every playbook declare at least one ending? → A: Zero endings is valid. The loader always materializes `endings` as an empty collection (never nil), following the same optional-field rule as `requires`/`needs`/`tools`/conditions. Boot validation never fails on missing or empty endings — only on a broken reference (an ending named in the procedure body that isn't declared in the endings list, per FR-009). A playbook with no endings has no typed outcome: the turn answers and waits for the customer instead of exiting through a declared ending.
- Q: If two different playbook files declare the same `name`, is that a boot validation failure, or undefined/unhandled by this phase's validator? → A: Duplicate `name` is a boot validation failure, in the same class as duplicate `priority` (FR-011): the loader raises, CI fails, and the error identifies both offending files and the conflicting name. Uniqueness is checked against the declared `name` field, independent of filename or directory location, and is global across the whole catalog.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Load a playbook file into a typed, queryable catalog (Priority: P1)

A developer adds or edits a playbook file describing one situational procedure (its name, title, ordering priority, the conditions under which it applies, the sentence used to recognize it by intent, the capabilities/knowledge/tools it needs, its possible endings, and its step-by-step body). The system reads every playbook file and produces a catalog: each playbook is available as a single object with all its declared fields readable individually, its procedure text intact, and the whole set can be looked up by name or ordered by priority.

**Why this priority**: This is the foundational capability — without a working catalog, nothing else (validation, routing, execution) has anything to operate on. It is also the direct fix for the core problem: today there is no addressable unit smaller than the whole prompt; this delivers that unit.

**Independent Test**: Can be fully tested by placing one playbook file with a full set of fields and confirming every field is readable on the resulting object and the procedure text matches the file exactly, with no conversation or model call involved.

**Acceptance Scenarios**:

1. **Given** a playbook file with all fields filled in (name, title, priority, conditions, recognition sentence, required capabilities, required knowledge, usable tools, declared endings) and a procedure body, **When** the system loads it, **Then** the resulting object exposes every one of those fields individually and the procedure body is preserved exactly as written, with no reformatting or truncation.
2. **Given** a playbook file that only declares the fields it must have (name, title, priority, recognition sentence) and omits every optional field, **When** the system loads it, **Then** it loads successfully and each omitted field reads back as an empty collection, not an error and not a missing/nil field that breaks downstream reads.
3. **Given** a directory containing several playbook files, **When** the system loads the full set, **Then** it produces one catalog in which any playbook can be looked up by its name and the full set can be ordered by its priority value.

---

### User Story 2 - Boot fails loudly on any broken reference between playbooks (Priority: P2)

A developer (or CI) starts the system with a set of playbook files that contains a mistake: a condition check that refers to a check that doesn't exist, a required capability that isn't in the known list, an ending mentioned in the procedure text that was never declared, a handoff to another playbook that doesn't exist, a playbook with a missing or non-integer ordering priority, two playbooks that declare the same name, or two playbooks that claim the same ordering priority. Startup stops with a clear error naming the offending file and exactly what reference is broken — it does not start in a degraded or partially-working state, and it never reaches a real conversation.

**Why this priority**: This is the safety net that makes the file-based format trustworthy at scale — every commit changes files by hand, so silent misconfiguration is the main risk this feature must close. It depends on User Story 1 (there is nothing to validate before it loads), which is why it is not P1.

**Independent Test**: Can be fully tested by constructing one broken playbook set per kind of breakage listed above, starting the system, and confirming each one is rejected at startup with an error that names the specific file and reference — with a known-good set as the control that starts cleanly.

**Acceptance Scenarios**:

1. **Given** a playbook whose condition list names a check that is not registered anywhere in the system, **When** the system starts, **Then** startup fails with an error identifying the playbook file and the unregistered check name.
2. **Given** a playbook that requires a capability not present in the declared list of known capabilities, **When** the system starts, **Then** startup fails with an error identifying the playbook file and the unknown capability name.
3. **Given** a playbook whose procedure body references an ending that was not declared among its own endings, **When** the system starts, **Then** startup fails with an error identifying the playbook file and the undeclared ending.
4. **Given** a playbook whose procedure hands off to another playbook by name, and no playbook with that name exists in the set, **When** the system starts, **Then** startup fails with an error identifying the playbook file and the missing target playbook name.
5. **Given** two playbooks in the same set that declare the same ordering priority, **When** the system starts, **Then** startup fails with an error identifying both files and the duplicated priority value.
6. **Given** a complete set of playbook files with no broken references, **When** the system starts, **Then** it starts cleanly with no warnings and without making any call to a language model.
7. **Given** a playbook whose `priority` value is absent or not an integer, **When** the system starts, **Then** startup fails with an error identifying the playbook file and the invalid `priority` value.
8. **Given** two playbook files anywhere in the playbooks directory that declare the same `name`, **When** the system starts, **Then** startup fails with an error identifying both files and the duplicated name.
9. **Given** a playbook file missing `name`, `title`, or `trigger`, or where any of those fields is blank, **When** the system starts, **Then** startup fails with an error identifying the playbook file and the missing/blank field.

---

### User Story 3 - A condition check is a small, independently testable, named unit (Priority: P3)

A developer defines one condition check as a small, isolated unit that takes the current routing information (and, optionally, one extra value) and answers true or false, addressable by the name used inside a playbook's condition list. When a playbook lists more than one condition, it only applies when every one of them is true. Referring to a condition check name that was never defined is treated as the startup error from User Story 2, never as a silent "false."

**Why this priority**: This makes "when does this playbook apply" verifiable without a model in the loop, which is the testability goal behind the whole feature — but it is only useful once there is a catalog (US1) and a validation pass that enforces it (US2), so it is the third priority, not the first.

**Independent Test**: Can be fully tested by defining one condition check, exercising it directly with inputs that should return true and false, and confirming a playbook's multi-condition list only matches when every listed condition is individually true.

**Acceptance Scenarios**:

1. **Given** a defined condition check and a routing context that satisfies it, **When** the check is evaluated by its registered name, **Then** it returns true; given a context that does not satisfy it, it returns false.
2. **Given** a playbook whose condition list has two or more checks, **When** every listed check is true for the current context, **Then** the playbook is considered a match; **When** at least one listed check is false, **Then** the playbook is not considered a match.
3. **Given** the condition-check contract accepts an optional extra value (e.g. "is the opportunity in stage X"), **When** a condition check that uses that value is evaluated with different values, **Then** it returns a result specific to the value supplied, not a fixed answer. *(The two condition checks shipped in this phase — `opportunity_open`, `pending_required_fields` — do not consume the extra value; a value-differentiated condition check is authored in a later phase once a playbook needs one, per Assumptions.)*

---

### Edge Cases

- A playbook file declares no conditions at all (trigger-only activation) — this is an explicitly normal case, not an error; it loads with an empty condition list.
- The playbooks directory contains zero files — the catalog loads as empty rather than failing (no playbooks is a valid, if degenerate, starting state).
- A condition list has exactly one entry that is false — the playbook does not match (single-entry lists follow the same all-must-be-true rule as multi-entry lists).
- A playbook's procedure body mentions an ending in prose but the same ending is also properly declared in its endings list — this is valid; only an ending referenced in the body but absent from the declared list is an error.
- A duplicate-priority error and a broken-reference error both exist in the same startup attempt — startup still fails; every failure that can be identified in one pass is surfaced, not just the first one encountered (see Assumptions for the exact reporting behavior chosen).
- A capability name in `requires` matches a name in the declared capability catalog exactly except for case or whitespace — treated as not matching (no fuzzy/normalized comparison), so it fails validation like any other unknown capability.
- A playbook declares `priority` as a non-integer value (e.g. a string or decimal) — treated as a boot validation failure identifying the offending file, not coerced to a number.
- A playbook declares zero endings — this is valid; it has no typed outcome and the turn answers and waits for the customer instead of exiting through a declared ending. Boot validation never fails on missing or empty endings; it only fails when the procedure body references an ending name that isn't declared (FR-009).
- Two playbook files declare the same `name` regardless of their filenames or directory location — treated as a boot validation failure identifying both files and the duplicated name; `name` uniqueness is global across the whole catalog, not scoped by file path.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST read a playbook from a single versioned file containing structured metadata (name, title, priority, conditions, recognition sentence, required capabilities, required knowledge, usable tools, declared endings) plus a free-form procedure body, and expose each metadata field individually on the resulting object.
- **FR-002**: The system MUST preserve the procedure body exactly as written in the file (no reformatting, truncation, or reflow) on the resulting object.
- **FR-003**: The system MUST treat `requires` (capabilities), `needs` (knowledge), `tools`, declared endings, and the condition list as optional: when absent from a file, each MUST resolve to an empty collection, not an error and not a missing value.
- **FR-004**: The system MUST require `name`, `title`, `priority`, and the recognition sentence (`trigger`) on every playbook file, and MUST require `priority` to be an integer value; a file missing any of `name`, `title`, or `trigger`, or with a missing or non-integer `priority`, MUST fail to load.
- **FR-005**: The system MUST load every playbook file in the playbooks directory into a single catalog, queryable by playbook name and orderable by priority.
- **FR-006**: The system MUST run a validation pass over the full loaded catalog before the system is ready to serve conversations, and MUST NOT allow startup to complete while any of the checks in FR-004, FR-007–FR-011, or FR-017 fails.
- **FR-007**: Validation MUST fail, naming the offending file and the specific reference, when a playbook's condition list names a check that is not registered.
- **FR-008**: Validation MUST fail, naming the offending file and the specific reference, when a playbook's required capability is not present in the declared catalog of known capabilities.
- **FR-009**: Validation MUST fail, naming the offending file and the specific reference, when a playbook's procedure body references an ending that is not declared among that playbook's own endings.
- **FR-010**: Validation MUST fail, naming the offending file and the specific reference, when a playbook's procedure hands off to another playbook by name and no playbook with that name exists in the loaded set.
- **FR-011**: Validation MUST fail, naming the offending files and the value, when two or more playbooks in the set declare the same priority.
- **FR-012**: A validation failure MUST stop startup outright (fail loud) rather than skipping, disabling, or silently degrading the offending playbook; the same failure MUST also cause an automated build/CI run to fail.
- **FR-013**: A fully valid playbook set MUST start with no errors, no warnings, and no calls to a language model or other conversational model during loading or validation.
- **FR-014**: The system MUST provide a condition check as a small, independently invocable unit, resolvable by the name used in a playbook's condition list, that accepts the current routing context and one optional extra value and returns a boolean.
- **FR-015**: When a playbook's condition list has two or more entries, the system MUST consider it satisfied only when every listed condition check evaluates to true (logical AND); it MUST NOT support "or" or nested logic.
- **FR-016**: Referencing an unregistered condition-check name anywhere in a playbook's condition list MUST be treated exclusively as the startup validation failure described in FR-007, never evaluated as a runtime `false`.
- **FR-017**: Validation MUST fail, naming both offending files and the duplicated value, when two or more playbook files in the set declare the same `name`, independent of file location or filename.

### Key Entities

- **Playbook**: One versioned file describing a single situational procedure. Attributes: unique name, human-readable title, ordering priority (required, integer, unique across the catalog — no default), list of condition-check references (optional; implemented as the `when_state` field), recognition sentence used for intent-based activation, list of required capabilities (optional), list of required knowledge items (optional), list of usable tools (optional), list of declared endings (optional — resolves to an empty collection when absent; each declared ending has its own expected outcome data; implemented as the `exits` field), and the step-by-step procedure body text.
- **Playbook Catalog**: The full loaded, validated set of playbooks for the system, queryable by name and orderable by priority.
- **Condition Check**: A small, named, independently testable unit that evaluates one fact about the current routing context (optionally parameterized) and returns true or false; used to build a playbook's condition list (implemented as a `Predicate`, referenced by name in the `when_state` field).
- **Declared Capability Catalog**: The known list of capability names that a playbook's `requires` field is checked against during validation (the capabilities themselves are not resolved or exercised by this feature — only their names are checked to exist).
- **Boot Validation Failure**: The error raised when the loaded catalog contains any broken reference, a missing or non-integer `priority`, a duplicate priority, or a duplicate playbook `name`; identifies the offending file(s) and the specific broken reference or value.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of startup attempts with at least one broken reference (unregistered condition check, unknown capability, undeclared ending, missing handoff target, missing `name`/`title`/`trigger`, missing or non-integer `priority`, duplicate priority, or duplicate playbook `name`) are rejected before the system becomes ready to serve any conversation — zero such conditions ever reach a live conversation.
- **SC-002**: A complete, valid set of playbook files starts with zero errors, zero warnings, and zero calls to a language model.
- **SC-003**: Adding, changing, or removing one situational behavior rule requires touching only that rule's own playbook file — zero lines of the shared prompt-building code need to change for that kind of edit.
- **SC-004**: Every condition check used to decide when a playbook applies can be exercised and verified (true and false cases) in isolation, without a language model or a live conversation.

## Assumptions

- "Fail loud" for boot validation means the process that would otherwise become ready to serve conversations does not become ready — reported as a single failure (raised error / non-zero exit) after collecting every broken reference found in that pass, so a developer sees the full list of problems at once rather than fixing them one at a time across repeated boot attempts.
- Capability name matching in validation is exact-string, case-sensitive; no normalization or fuzzy matching is applied.
- This feature validates only that a `requires` capability name exists in a declared list of known capability names — it does not resolve, instantiate, or exercise the capability itself (that belongs to a later phase of the wider effort this feature is part of).
- The procedure body text is written in the same human language the assistant's operators already write internal instructions in, and is not part of the product's translated user-interface strings — this only affects how the model is instructed, not what a customer reads, since customer-facing replies keep following whatever language detection already governs them today.
- This feature covers loading, cataloging, and validating playbooks, and defining condition checks as testable units. It does not decide which playbook becomes "active" during a real conversation, does not build or send any prompt to a model, and does not change any existing shared prompt-building code path — those are handled by later, separate efforts.
- An empty playbooks directory is a valid (if unusual) state: the catalog loads empty and validation passes trivially, rather than being treated as a configuration error.
- The two condition checks this phase ships (`opportunity_open`, `pending_required_fields`) do not use the optional extra value in the condition-check contract — both evaluate only the routing context. The extra-value contract itself (US3 Acceptance Scenario 3) is satisfied structurally by the condition-check signature and by the evaluator forwarding the value through to the resolved check; a concrete condition check whose result differs by the value supplied is authored in a later phase once a playbook needs one.
