# Feature Specification: Kanban Backend Core — Opportunities & Pipeline Stages

**Feature Branch**: `001-kanban-backend-core`

**Created**: 2026-07-30

**Status**: Draft

**Input**: User description: "vamos iniciar o trabalho de criação do kanban no chatwoot. esse será um trabalho de 4 etapas para construir o mvp. a primeira parte está desenhada em docs/kanban/01-backend-core/spec1.md."

**Phase**: 1 of 4 (Backend Core). Depends on nothing. Feeds Phase 2 (automation), Phase 3 (frontend), Phase 4 (realtime/menu).

## Clarifications

### Session 2026-07-30

- Q: What should happen to a Pipeline Stage when it still has Opportunities pointing to it and someone tries to delete it? → A: Restrict: deletion is rejected while any Opportunity still references the stage (admin must move them first)
- Q: Should the feature flag be enabled or disabled by default? → A: The flag is enabled/available platform-wide by default (not premium-gated), but functionality is only actually live for an account once its administrator activates it in account settings. Deactivating immediately stops all Opportunity/Pipeline Stage functionality for that account without deleting any data; reactivating resumes using the same previously-configured Pipeline Stages and Opportunities.
- Q: On Pipeline Stage creation, should position be auto-assigned or caller-supplied? → A: Auto-assigned: the server appends new stages to the end of the pipeline (`max(position) + 1`); explicit reordering support is deferred to a later phase.
- Q: Can an Opportunity be reopened after being marked `won`/`lost`? → A: Freely editable — `status` can be changed to any of `open`/`won`/`lost` at any time, with no transition restrictions in this phase.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Administrator configures the account's pipeline (Priority: P1)

An account administrator wants a set of ordered stages (e.g. "Leads Recebidos", "Em Contato") that represent the steps an opportunity moves through, so the account has a consistent pipeline before any opportunity is tracked. The first time the administrator (or the system, on their behalf) looks at pipeline configuration for an account with no stages defined, a sensible default pipeline must already exist — no manual setup step is required to get started.

**Why this priority**: Nothing else in the module works without at least one pipeline stage to assign an opportunity to. This is the foundation the rest of the phase builds on.

**Independent Test**: On a freshly seeded account with zero pipeline stages, request the pipeline stages list. Two default stages must be returned and persisted. A second request must return the same two stages, not create duplicates, even under concurrent first-time requests. An administrator can also add, rename, update the position of, and remove stages via the standard update action.

**Acceptance Scenarios**:

1. **Given** an account with zero pipeline stages, **When** an administrator opens (or hits the API for) pipeline stage configuration, **Then** two default stages ("Leads Recebidos" at position 0, "Em Contato" at position 1) are created and returned.
2. **Given** an account that already has default stages seeded, **When** pipeline stage configuration is opened again, **Then** no duplicate stages are created.
3. **Given** an administrator, **When** they create, rename, update the position of, or delete a pipeline stage via the standard update action, **Then** the change is persisted and scoped only to their own account (no dedicated multi-stage reorder/reindex operation exists in this phase — see Assumptions).
4. **Given** a non-administrator (agent), **When** they attempt to create, update, or delete a pipeline stage, **Then** the action is denied.
5. **Given** an account where the feature has been activated and configured, **When** the administrator deactivates it in account settings, **Then** all Pipeline Stage/Opportunity functionality stops immediately without deleting any existing data; **When** it is reactivated, **Then** the previously configured Pipeline Stages and Opportunities are used again without any reconfiguration needed.

---

### User Story 2 - Team tracks Opportunities tied to a Contact (Priority: P1)

An administrator or agent wants to record an "Opportunity" (a deal, request, or case tied to a Contact) and move it through the account's pipeline stages independently of any single conversation. An Opportunity can optionally originate from an existing conversation, and a Contact may have several Opportunities open at once.

**Why this priority**: This is the core object of the Kanban feature — without it, pipeline stages have nothing to organize.

**Independent Test**: Create an Opportunity for a Contact and pipeline stage via the API with only `contact_id` and `pipeline_stage_id`; confirm it persists, appears in the Contact's list of Opportunities, and can be moved to a different stage, reassigned, or marked won/lost/open independently of the stage it sits in.

**Acceptance Scenarios**:

1. **Given** a Contact and a pipeline stage belonging to the same account, **When** an authorized user creates an Opportunity with a title, **Then** it is persisted, linked to the Contact, and appears in the Contact's Opportunities.
2. **Given** an existing Opportunity, **When** an authorized user updates its `pipeline_stage_id`, `title`, `assignee_id`, or `status` (`open`/`won`/`lost`), **Then** the change is persisted.
3. **Given** an Opportunity created with an `origin_conversation_id`, **When** any user attempts to change that field afterward, **Then** the request is rejected and the original value is retained.
4. **Given** a Contact that already has one open Opportunity, **When** a second Opportunity is created for the same Contact, **Then** both coexist without conflict.
5. **Given** an attempt to create or move an Opportunity to a pipeline stage belonging to a different account, **When** the request is submitted, **Then** it is rejected as invalid.

---

### User Story 3 - Access to Opportunities is limited to the people who should see them (Priority: P2)

An agent should only see and edit Opportunities they are directly responsible for (assigned to them) or that stem from a conversation they already have access to through existing inbox/team permissions. Administrators can see and manage every Opportunity in the account.

**Why this priority**: Without this, any agent could view or edit any customer's Opportunity, which is a data-access regression compared to how conversations are already scoped.

**Independent Test**: As an agent who is neither the assignee nor has conversation access, attempt to view/edit an Opportunity and confirm it is denied; as the assignee (or with conversation access), confirm it is allowed; as an administrator, confirm full access.

**Acceptance Scenarios**:

1. **Given** an administrator, **When** they view or edit any Opportunity in the account, **Then** access is granted.
2. **Given** an agent who is the Opportunity's assignee, **When** they view or edit it, **Then** access is granted.
3. **Given** an agent with existing access to the Opportunity's origin conversation (via inbox/team scoping) but who is not the assignee, **When** they view or edit it, **Then** access is granted.
4. **Given** an agent who is neither the assignee nor has access to the origin conversation, **When** they attempt to view or edit it, **Then** access is denied.

---

### Edge Cases

- An account has zero pipeline stages and the pipeline stage endpoint is hit concurrently more than once before the default stages are created — duplicates must not be created (the lazy-seed operation MUST be safe under concurrent first requests, not just under sequential repeat calls).
- An Opportunity is created without any `origin_conversation_id` (fully manual, no related conversation) — this must be supported since it is optional.
- An attempt is made to set or change `origin_conversation_id` on `update` — must be rejected, including when the new value is otherwise valid.
- A pipeline stage is deleted while Opportunities still reference it — the deletion MUST be rejected until the admin moves or resolves those Opportunities first (no cascade, no silent orphaning).
- An Opportunity references a `pipeline_stage_id` from a different account than its own `account_id` — must fail validation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support an isolated, self-contained module for this feature so that it can be pulled/merged without conflicting with future upstream Chatwoot changes, wired into the application via the smallest possible edit to shared core configuration.
- **FR-002**: The system MUST provide a "Pipeline Stage" concept, scoped to a single account, with a name and an explicit ordering (position), so stages display in a consistent, admin-controlled sequence. A newly created stage MUST be automatically appended to the end of the account's pipeline (position = current max + 1); explicit client-supplied reordering/repositioning beyond this phase's basic `update` is out of scope and deferred to a later phase.
- **FR-003**: The system MUST provide an "Opportunity" concept that belongs to exactly one Contact, one Pipeline Stage, and one Account; optionally references the conversation it originated from and an assignee; has a title; and has a status (`open` by default, `won`, or `lost`) that is tracked independently of which pipeline stage it currently sits in and is freely editable to any of the three values at any time (no one-way transition restriction in this phase).
- **FR-004**: The system MUST require a title, a Contact, a Pipeline Stage, and an Account for every Opportunity, and MUST reject an Opportunity whose Pipeline Stage belongs to a different account than the Opportunity itself.
- **FR-005**: When an account has no Pipeline Stages yet and pipeline configuration is accessed for the first time, the system MUST automatically create exactly two default stages ("Leads Recebidos", "Em Contato", in that order) for that account only, and MUST NOT create duplicates on subsequent access.
- **FR-006**: The system MUST enforce that administrators can view and edit every Opportunity in their account, while agents can only view and edit an Opportunity if they are its assignee or already have access to its origin conversation through existing conversation access rules.
- **FR-007**: The system MUST restrict creating, updating, reordering, and deleting Pipeline Stages to administrators only, and MUST reject deletion of a Pipeline Stage that still has any Opportunity referencing it.
- **FR-008**: The system MUST expose Opportunity management (list scoped to what the requester is allowed to see, view single, create, update — including moving between stages — and delete) through an API, matching the existing unpaginated list convention already used by comparable account-scoped settings resources (e.g. Macros, Custom Attribute Definitions), and MUST allow setting `origin_conversation_id` only at creation time, rejecting any attempt to change it afterward.
- **FR-009**: The system MUST expose Pipeline Stage management (list, create, update name/position, delete) through an API restricted to administrators.
- **FR-010**: The system MUST persist Pipeline Stages and Opportunities in a way that is additive to the existing database schema — introducing new tables only, never altering or dropping any existing table (Conversations, Contacts, etc.) — and any such change MUST be reversible.
- **FR-011**: A Contact MUST be able to have zero, one, or many associated Opportunities, retrievable from the Contact itself, without modifying the Contact's existing core definition directly.
- **FR-012**: The system MUST support gating this feature (Pipeline Stage configuration and Opportunity management) behind a feature flag, independent of any paid/premium tier. The flag MUST be available platform-wide by default, but the underlying functionality MUST only be active for a given account once its administrator activates it in that account's settings; deactivating it MUST immediately stop all Pipeline Stage/Opportunity functionality for that account without deleting any existing Pipeline Stages or Opportunities, and reactivating MUST resume using that same preserved configuration and data.

### Key Entities

- **Pipeline Stage**: A named, ordered step in an account's single implicit pipeline. Belongs to one Account. Has a display name and a position determining its order relative to other stages in the same account.
- **Opportunity**: A trackable deal/case tied to one Contact, moving through one Pipeline Stage at a time within one Account. Has a title, a status (`open`/`won`/`lost`) independent of its stage, an optional assignee, and an optional, immutable-after-creation link to the conversation it originated from. A Contact may have multiple Opportunities simultaneously.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An account with zero prior configuration reaches a usable pipeline (two default stages) with zero manual setup steps the first time pipeline configuration is accessed, and repeated access never produces duplicate stages.
- **SC-002**: 100% of attempts to change an Opportunity's origin conversation after creation are rejected, with the original value unchanged.
- **SC-003**: 100% of cross-account Pipeline Stage assignments to an Opportunity are rejected at creation or update time.
- **SC-004**: Access-control checks correctly grant or deny visibility/edit rights in all four tested roles (administrator, assignee-agent, conversation-access agent, unrelated agent) with zero incorrect grants or denials.
- **SC-005**: Enabling this feature introduces zero changes to existing Conversations, Contacts, Accounts, or other pre-existing data — verified by the migrations being purely additive and fully reversible.
- **SC-006**: A Contact can be associated with more than one simultaneous Opportunity without conflict or data loss.

## Assumptions

- This phase ships no end-user interface; verification happens through backend console/API checks and automated tests, matching the module's stated scope (manual CRUD and data model only — automation, frontend, and realtime updates are explicitly deferred to later phases).
- A single implicit pipeline per account is sufficient for the MVP; multiple named pipelines per account are out of scope for this phase.
- The feature flag introduced here only controls visibility of settings/API surfaces relevant to this phase; it does not yet gate any end-user-facing UI, since none exists yet.
- Reassigning or clearing `origin_conversation_id` after an Opportunity is created is permanently out of scope, not just deferred.
- "Reordering" pipeline stages in this phase means updating a single stage's `position` field via the standard `update` action; a dedicated multi-stage reorder/reindex operation (e.g. atomically shifting siblings) is deferred to a later phase.
