# Feature Specification: Realtime Sync & Menu/Route Wiring

**Feature Branch**: `004-realtime-sync-menu-wiring`

**Created**: 2026-07-31

**Status**: Draft

**Input**: User description: "Phase 4: Realtime Sync & Menu/Route Wiring — dispatch an `opportunity_updated` realtime event over the existing account-level broadcast channel so open Kanban boards update live, register the Kanban board and Pipeline Stages settings screens into the app's navigation/routing/store, and provide a repeatable, fail-fast sync mechanism for re-applying those navigation edits after every upstream merge."

## Clarifications

### Session 2026-07-31

- Q: Should the Pipeline Stages settings screen be reachable by any agent, or only administrators? → A: Administrators only — this is already enforced by the existing `PipelineStagePolicy` (all actions require `administrator?`), so the navigation/route wiring must not offer this screen to non-admin agents. Resolved by inspecting existing policy code rather than requiring a product decision.
- Q: Should the maintainer's sync tool only cover the handful of files needed for board/settings reachability (menu, routes, store, realtime), or every shared/upstream file touched anywhere across this project's build so far? → A: Every shared/upstream file touched so far, including ones added for the automation-action integration built alongside the Kanban feature (e.g., feature-flag definitions, automation action helpers, and their interface text) — not just the reachability-related ones. An audit of prior work confirmed additional shared files beyond the original reachability set were already modified and are equally at risk of being silently reverted by an upstream merge.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Kanban board updates live across sessions (Priority: P1)

An agent has the Kanban board open in two browser sessions (e.g., their desktop and a teammate's screen-share, or two tabs). When either agent or an automation moves an opportunity to a different pipeline stage, changes its status, or reassigns it, every other open board for that account reflects the change within seconds — without anyone refreshing the page.

**Why this priority**: Live collaboration is the core value proposition of a Kanban board. Without it, the board silently goes stale and agents make decisions on outdated information (e.g., double-working a card someone else already moved).

**Independent Test**: Open the board in two sessions on the same account, drag a card to a new stage in one session, and confirm the second session's board updates without a manual refresh.

**Acceptance Scenarios**:

1. **Given** two active sessions viewing the same account's Kanban board, **When** an opportunity's stage, status, contact, or assignee changes in one session, **Then** the other session's board reflects the change within a few seconds without a page refresh.
2. **Given** an opportunity is updated by a process other than the Kanban board itself (e.g., an automation), **When** the update is saved, **Then** any open Kanban board for that account still reflects the change live.

---

### User Story 2 - Agents can discover and reach the Kanban board (Priority: P2)

An agent whose account has the Kanban feature enabled sees a navigation entry for it and can open the board directly. Agents on accounts without the feature enabled see no such entry.

**Why this priority**: Without a discoverable entry point, the board built in prior phases is unreachable by normal users, so the feature delivers zero value regardless of how well the board itself works.

**Independent Test**: Enable the Kanban feature for a test account, log in, confirm a navigation entry appears and leads to the board; confirm the entry is absent for an account without the feature enabled.

**Acceptance Scenarios**:

1. **Given** an account with the Kanban feature enabled, **When** an agent views the main navigation, **Then** an entry linking to the Kanban board is visible and, when clicked, opens the board.
2. **Given** an account without the Kanban feature enabled, **When** an agent views the main navigation, **Then** no Kanban board entry is shown.
3. **Given** an account with the Kanban feature enabled, **When** an administrator navigates to account settings, **Then** a Pipeline Stages management screen is reachable and loads correctly.
4. **Given** an account with the Kanban feature enabled, **When** a non-administrator agent navigates to account settings, **Then** the Pipeline Stages management screen is not offered to them, consistent with the existing administrator-only permission already enforced for managing pipeline stages.

---

### User Story 3 - Maintainers can safely re-apply all shared-file wiring after every upstream update (Priority: P3)

A maintainer pulls in a fresh upstream update to the underlying product and needs to know whether the shared/upstream files this project has modified — across every phase of this project's build, not only the board's menu/route entries — still contain all the expected edits, without silently losing any of them or manually re-diffing files by hand.

**Why this priority**: This project's changes live inside shared application files that the maintainer does not otherwise control and that change frequently upstream. That includes not just the board's navigation/routing/store/realtime entries, but also earlier edits such as the feature-flag definition and the automation-action integration built alongside the Kanban feature. Without a repeatable, safe way to detect and re-apply *all* of this wiring — not just a subset — an upstream update can silently drop any of it, and nobody would notice until an agent complained a feature "disappeared."

**Independent Test**: Run the check in "report only" mode on an already-wired checkout and confirm it reports every wiring point present (across all covered files, not only the board's menu/route entries) with no changes needed; run apply twice in a row and confirm the second run makes no additional changes; deliberately break one wiring point and confirm the check fails loudly and identifies exactly what broke.

**Acceptance Scenarios**:

1. **Given** a checkout where all wiring has already been applied, **When** the maintainer runs the check in report-only mode, **Then** it confirms every wiring point is present, across every shared file this project has modified, and reports no changes needed.
2. **Given** a fresh checkout where the wiring has not yet been applied, **When** the maintainer runs the apply mode, **Then** all wiring points are added across all covered files, and running apply again afterward makes no further changes.
3. **Given** an upstream update has altered the exact location where one wiring point is supposed to be inserted, **When** the maintainer runs the check, **Then** it fails clearly, naming the specific file and wiring point affected, and does not partially apply the remaining changes for that file.
4. **Given** a wiring point belonging to the automation-action integration built alongside the Kanban feature (e.g., the feature-flag definition or an automation helper entry), **When** the maintainer runs the check, **Then** it is verified with the same rigor as the board's menu/route wiring points — it is not treated as out of scope just because it predates this phase.

### Edge Cases

- What happens if an opportunity is updated for an account while no one has a Kanban board open for that account? (No board is listening; no error should occur, and the change is simply picked up the next time a board is opened or refreshed.)
- What happens if two agents move the same card to different stages within the same second? (Last update wins; both boards converge to the same final state once the second update's live notification arrives.)
- What happens if the live update mechanism itself is temporarily unavailable (e.g., a dropped connection)? (The board recovers state on reconnect/refresh; a brief connectivity gap must not corrupt the board's data, only delay its freshness.)
- What happens if the maintainer's upstream update changes unrelated content in a wired file but leaves the exact wiring point intact? (The check should report the wiring point as still present and not falsely flag drift.)
- What happens if the maintainer runs apply mode on a file where the wiring was already manually (and correctly) added by hand rather than by the tool? (Apply must recognize the wiring is already present and skip it, not insert a duplicate.)
- What happens if a future phase of this project modifies yet another shared/upstream file not yet covered by the tool? (The tool only guarantees coverage of wiring points that have been explicitly added to its definitions; extending coverage to a newly touched file is a manual addition to those definitions, not automatic discovery.)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST notify all active viewers of an account's Kanban board, in real time, whenever an opportunity belonging to that account is created or updated.
- **FR-002**: The live update notification MUST include enough information about the changed opportunity (identifying which record changed, its pipeline stage, its status, its associated contact, and its assignee, plus when it changed) for a board already open in a session to update itself without needing to reload data from scratch.
- **FR-003**: The live update MUST be delivered over the account's existing real-time communication channel rather than a new, separate channel — an agent's board updates through the same connection already used for other real-time account activity.
- **FR-004**: Upon receiving a live opportunity update, an open Kanban board MUST move the affected card to its correct stage column and refresh its displayed details in place, without requiring a manual page refresh.
- **FR-005**: The application's primary navigation MUST include an entry linking to the Kanban board, visible only to agents on accounts where the Kanban feature is enabled.
- **FR-006**: The Kanban board MUST be reachable at a dedicated location within the application once the feature is enabled for an account.
- **FR-007**: The Pipeline Stages management screen MUST be reachable at a dedicated location within the application's account settings area once the feature is enabled, and MUST be offered only to administrators, consistent with the existing administrator-only permission already enforced for managing pipeline stages.
- **FR-008**: The application's data layer MUST be wired up so the Kanban board and Pipeline Stages screens have access to the opportunity and pipeline-stage data they need to function.
- **FR-009**: A maintainer MUST be able to run a check, at any time, that reports whether all of the required wiring points are present in the current codebase, without making any changes.
- **FR-010**: A maintainer MUST be able to run an apply step that adds any missing wiring points to the codebase.
- **FR-011**: Running the apply step multiple times in a row MUST NOT produce duplicate entries or duplicate changes — each wiring point is added at most once.
- **FR-012**: If any required wiring point cannot be located in its expected file (e.g., because an unrelated update changed that file's structure), the check or apply step MUST fail immediately and clearly identify which file and which wiring point could not be found, rather than silently skipping it or partially applying the remaining changes to that file.
- **FR-013**: The definitions of what to wire, where, and how (file, insertion point, and content) MUST be kept in one reviewable place, so that updating a definition after an intentional upstream change, or adding coverage for a newly touched file, is a small, easily reviewed edit.
- **FR-014**: The set of wiring points covered by the check/apply tool MUST include every shared/upstream file this project has modified up to and including this phase — not only the files needed for board/settings reachability (menu, routing, store registration, realtime event handling), but also files modified earlier for the automation-action integration built alongside the Kanban feature (at minimum: the feature-flag definition, the automation action helper/composable entries, the automation action type/constant list, and the associated interface text needed to display that action). Coverage of a shared file added in a later phase beyond this one is out of scope until explicitly added to the tool's definitions (see FR-013).

### Key Entities

- **Opportunity live update notification**: A real-time message describing a single opportunity's change — which opportunity, its stage, status, contact, assignee, and last-changed time — delivered to everyone currently viewing that account.
- **Wiring point**: One specific, named location in a shared/upstream application file (e.g., "the main navigation menu," "the settings routing list," "the data-layer registration list," "the feature-flag list," "the automation action helper map") where an entry added by this project must exist for a piece of this project's functionality — board/settings reachability, live updates, or the automation-action integration — to work correctly.
- **Wiring check/apply run**: A single execution of the maintainer's tool, which either reports on or applies the current state of all wiring points across all covered shared/upstream files, and produces a pass/fail-with-reason outcome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When an opportunity changes, every other session currently viewing that account's Kanban board reflects the change within 5 seconds, without a manual refresh.
- **SC-002**: 100% of agents on accounts with the Kanban feature enabled can find and open the Kanban board from the main navigation within two clicks.
- **SC-003**: Accounts without the Kanban feature enabled show zero Kanban-related navigation entries.
- **SC-004**: A maintainer can determine, in under one minute and without inspecting individual files by hand, whether an upstream update has broken any part of this project's shared-file wiring — including the automation-action integration, not only the board's navigation entries.
- **SC-005**: Re-running the wiring apply step on an already-wired codebase produces no observable changes (zero unexpected diffs).
- **SC-006**: When a wiring point is missing or broken, the maintainer is told exactly which one within the same check run — no follow-up investigation is needed to locate the problem.

## Assumptions

- The application already has an existing account-level real-time communication channel used for other live updates; this feature reuses it rather than introducing a new one.
- The Kanban board and Pipeline Stages screens, along with the underlying data layer they depend on, already exist as functioning building blocks from prior phases of this project; this feature is only responsible for making them reachable and live-updating, not building them.
- Visibility of the Kanban navigation entry is controlled by the same account-level feature flag already established for this project, consistent with prior phases.
- The maintainer role is a technical user (e.g., a developer maintaining this customized installation) rather than an end-user agent; the wiring check/apply tooling is a development-time tool, not an end-user-facing feature.
- A "few seconds" of live-update latency, and brief reconnect gaps, are acceptable; this feature does not need to guarantee sub-second delivery or offline durability.
- The full set of shared/upstream files to cover was determined by reviewing the actual changes made in prior phases of this project (as of this phase) rather than by re-deriving it from each phase's original spec documents; it includes files touched for the automation-action integration in addition to the board/settings reachability files originally anticipated.
- Coverage is a fixed, explicitly maintained list (FR-013), not an automatic discovery mechanism; if a future phase modifies additional shared files, extending the tool's coverage to them is a manual step for whoever builds that phase.
