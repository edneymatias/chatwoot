---
feature: 073-scout-overview-conversations
verdict: PASS_WITH_GAPS
standard: .specify/extensions/tdd/templates/tdd-test-quality-rubric.md
verified_at: 4c3b445494
behaviors: 53
proven: 0
likely: 53
test_after: 0
no_test: 0
high_smells: 0
criteria_total: 7
criteria_covered: 7
mutation_score: null # no mutation tool; 6 deliberate mutants sampled, 0 survived
mutants_survived: 0
suite: 52 Ruby passed (0 failed, 11.23s targeted); 27 JS passed (0 failed, 5.51s targeted)
---

# TDD Verification: Scout Overview — Recent Conversations List

**Verdict: PASS_WITH_GAPS.** All 7 acceptance criteria in `spec.md` are covered with end-to-end assertions, all 6 sampled deliberate mutants were caught (0 survived), and all previously identified HIGH smells (vacuous `useAlert` calls, vacuous `timezoneOffset` prop check) have been eliminated. The verdict is `PASS_WITH_GAPS` because (1) all working tree changes are uncommitted per repository workflow constraints (`AGENTS.md`), meaning git history cannot corroborate chronological test-first ordering (`LIKELY`, none `PROVEN`), (2) behaviors U28–U31 had their red phases established retroactively via deliberate mutant subtraction during remediation TR001 rather than during the original loop, and (3) automated mutation testing is unmeasured across the repository.

## Audit context

This audit was conducted from cold context against the working tree at `4c3b445494`. Per repository guidelines (`AGENTS.md`), commits to the remote branch are prohibited prior to explicit local validation by the user. Consequently, all changes remain in the working directory (uncommitted). Under the rubric, when git history cannot verify that test files were committed prior to or alongside implementation files, behaviors cannot be classified as `PROVEN` and default to `LIKELY` when supported by recorded failure output in `cycle-log.md`.

Remediation pass Phase 6 cleared all 6 blocking findings (F1–F6) and 4 medium findings (F7–F10):
- **TR001 (F1–F4)**: Retroactive red failure outputs were documented in `cycle-log.md` for U28–U31 by removing `STATUS_CONFIG` entries in `ConversationStatusBadge.vue`, observing expected `TypeError` failures, and restoring.
- **TR002 & TR003 (F5)**: Replaced vacuous `toHaveBeenCalled()` in `RecentConversationsSection.spec.js` with `toHaveBeenCalledWith(expect.stringContaining('...'))` for both missing-ID and popup-blocked alerts.
- **TR004 (F6)**: Replaced vacuous `toBeDefined()` in `ScoutOverview.spec.js` with exact `String(-(new Date().getTimezoneOffset() / 60))` value check.
- **TR005 (F7)**: Replaced self-referential `start_times.sort.reverse` expectation with deterministic `[c_new.id, c_old.id]` order in `scout_overview_reports_controller_spec.rb`.
- **TR006 (F8)**: Replaced loose `>= 1` inequalities with exact counts in status counts test.
- **TR007 (F9)**: Split loop over 6 valid statuses into individual RSpec `it` blocks (increasing example count from 47 to 52).
- **TR008 (F10)**: Added explicit assertions for all 6 filter pills and their exact counts.

## Test-first evidence

| Behavior | Class | Evidence |
|---|---|---|
| A1 | LIKELY | Cycle outer-loop: `AssertionError: expected [] to deeply equal [...]` recorded |
| A2 | LIKELY | Cycle 34: failure against minimal stub without click handler |
| A3 | LIKELY | Cycle 39: failure against minimal stub without PaginationFooter |
| A4 | LIKELY | Cycles 44–46: explicit red command output recorded (`AssertionError: expected false to be true`) |
| A5 | LIKELY | Cycle: failure against minimal stub without neutral badge styling |
| A6 | LIKELY | Cycle 41: failure against minimal stub without row click handler |
| A7 | LIKELY | Cycles 42–43: failure against minimal stub without alert guards |
| U1 | LIKELY | Cycle 1: `expected status :unauthorized (401) but it was :not_found (404)` (1 failed) recorded |
| U2 | LIKELY | Cycle 2: deliberate-mutant check with explicit failure description |
| U3 | LIKELY | Cycle 3: deliberate-mutant check |
| U4 | LIKELY | Cycle 4: deliberate-mutant check |
| U5 | LIKELY | Cycle 5: deliberate-mutant check |
| U6 | LIKELY | Cycle 6: deliberate-mutant check |
| U7 | LIKELY | Cycle 7: `expected status :unprocessable_content (422) but it was :ok (200)` (1 failed) recorded |
| U8 | LIKELY | Cycle 8: deliberate-mutant check |
| U9 | LIKELY | Cycle 9: `JSON::ParserError: unexpected end of input` (1 failed) recorded |
| U10 | LIKELY | Cycle 10: deliberate-mutant check |
| U11 | LIKELY | Cycle 11: `PG::GroupingError: column "messages.created_at" must appear in GROUP BY` (1 failed) recorded |
| U12 | LIKELY | Cycle 12: deliberate-mutant check (corroborated in audit via Mutant 1) |
| U13 | LIKELY | Cycle 13: deliberate-mutant check |
| U14 | LIKELY | Cycle 14: deliberate-mutant check |
| U15 | LIKELY | Cycle 15: deliberate-mutant check |
| U16 | LIKELY | Cycle 16: observed real failure (status defaulted to `:pending`, corroborated in audit via Mutant 2) |
| U17 | LIKELY | Cycle 17: deliberate-mutant check |
| U18 | LIKELY | Cycle 18: deliberate-mutant check (corroborated in audit via Mutant 3) |
| U19 | LIKELY | Cycle 19: deliberate-mutant check |
| U20 | LIKELY | Cycle 20: deliberate-mutant check (corroborated in audit via Mutant 4) |
| U21 | LIKELY | Cycle 21: deliberate-mutant check |
| U22 | LIKELY | Cycle 22: deliberate-mutant check |
| U23 | LIKELY | Cycle 23: deliberate-mutant check |
| U24 | LIKELY | Cycle 24: deliberate-mutant check |
| U25 | LIKELY | Cycle 25: deliberate-mutant check |
| U26 | LIKELY | Cycle 26: `TypeError: default.getConversations is not a function` (1 failed) recorded |
| U27 | LIKELY | Cycle 27: `AssertionError: expected '' to be 'Qualified'` (1 failed) recorded |
| U28 | LIKELY | Cycle 28: retroactive red documented in TR001 (`TypeError: Cannot read properties of undefined`) |
| U29 | LIKELY | Cycle 29: retroactive red documented in TR001 (`TypeError: Cannot read properties of undefined`) |
| U30 | LIKELY | Cycle 30: retroactive red documented in TR001 (`TypeError: Cannot read properties of undefined`) |
| U31 | LIKELY | Cycle 31: retroactive red documented in TR001 (`TypeError: Cannot read properties of undefined`, corroborated in audit via Mutant 5) |
| U32 | LIKELY | Cycle 32: `AssertionError: expected [] to deeply equal ['Contact', ...]` (1 failed) recorded |
| U33 | LIKELY | Cycle 33: failure against minimal stub without filter pills |
| U34 | LIKELY | Cycle 34: failure against minimal stub without click handler |
| U35 | LIKELY | Cycle 35: failure against minimal stub without duration cell |
| U36 | LIKELY | Cycle 36: failure against minimal stub without dash placeholder |
| U37 | LIKELY | Cycle 37: failure against minimal stub without contact name element |
| U38 | LIKELY | Cycle 38: failure against minimal stub without EmptyStateLayout |
| U39 | LIKELY | Cycle 39: failure against minimal stub without PaginationFooter |
| U40 | LIKELY | Cycle 40: `AssertionError: expected false to be true` (1 failed) recorded |
| U41 | LIKELY | Cycle 41: failure against minimal stub without row click handler |
| U42 | LIKELY | Cycle 42: failure against minimal stub without guard (corroborated in audit via Mutant 6) |
| U43 | LIKELY | Cycle 43: failure against minimal stub without blocked popup detection |
| U44 | LIKELY | Cycle 44: `AssertionError: expected false to be true` (1 failed) recorded |
| U45 | LIKELY | Cycle 45: deliberate-mutant check |
| U46 | LIKELY | Cycle 46: deliberate-mutant check |

### Weakened existing tests

Diff of working tree against `origin/ichatr-main` was inspected. The only modified existing spec file in the repository is `custom/spec/services/custom/scout/system_prompts_service_spec.rb`, which belongs to feature 071 and added stricter assertions to track intentional prompt text refinements. **No existing tests were weakened or loosened.**

### tasks.md vs test-list concordance

All 29 original implementation tasks (T001–T029) and all 8 remediation tasks (TR001–TR008) in `tasks.md` are marked `[X]`. All 53 behaviors (A1–A7, U1–U46) in `tdd/test-list.md` are marked `DONE`. Concordance between tasks and test list is complete.

## Findings

Ordered by severity, each with evidence and recommended remediation.

| # | Severity | Finding | Evidence | Remediation |
|---|---|---|---|---|
| 1 | MED | **Framework under test** — `scoutOverviewReports.spec.js:6-10` asserts `toBeInstanceOf(ApiClient)` and `toHaveProperty('get')`, testing framework inheritance rather than feature behavior | `app/javascript/dashboard/api/specs/scoutOverviewReports.spec.js:6-10` | Remove inheritance assertions or replace with feature contract assertion |
| 2 | LOW | **Duplicate test identifier in name** — `ScoutOverview.spec.js` contains two tests tagged `(U44)`: line 109 (scout selector re-fetch from feature 072) and line 127 (RecentConversationsSection embedding for 073), causing minor ambiguity in test failure output | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js:109,127` | Renumber the older test description to remove the conflicting `(U44)` tag |

## Mutation results

No automated mutation tool is configured in this repository. Six deliberate mutants were sampled across the highest-risk behaviors (status classification, duration calculation, chronological sorting, badge styling, and error notifications).

| Mutant | File | Behavior | Change | Caught | Failure Evidence / Judgment |
|---|---|---|---|---|---|
| M1 | `scout_overview_conversations_builder.rb:58` | U12 | Replaced `'qualified'` with `'disqualified'` in CASE branch | Yes | `expected: "qualified", got: "disqualified"` at `scout_overview_reports_controller_spec.rb:664` |
| M2 | `scout_overview_conversations_builder.rb:64` | U16 | Replaced `'transferred_without_opportunity'` with `'disqualified'` | Yes | `expected: "transferred_without_opportunity", got: "disqualified"` at `scout_overview_reports_controller_spec.rb:726` |
| M3 | `scout_overview_conversations_builder.rb:142` | U18 | Replaced duration difference `(last_at - first_at).to_i` with `0` | Yes | `expected: 180, got: 0` at `scout_overview_reports_controller_spec.rb:759` |
| M4 | `scout_overview_conversations_builder.rb:119` | U20 | Removed `.reverse` from chronological sort | Yes | `expected: [3294, 3293], got: [3293, 3294]` at `scout_overview_reports_controller_spec.rb:793` |
| M5 | `ConversationStatusBadge.vue:34` | U31 | Replaced neutral slate classes with ruby red classes | Yes | `expected [ Array(12) ] to include 'bg-n-slate-3'` at `ConversationStatusBadge.spec.js:55` |
| M6 | `RecentConversationsSection.vue:127` | U42 | Replaced `INVALID_ID` alert message with `'something else'` | Yes | `expected "spy" to be called with arguments: [ StringContaining "missing or invalid" ], Received: [ "something else" ]` at `RecentConversationsSection.spec.js:284` |

**All 6 deliberate mutants were caught. 0 mutants survived.** Every mutant was restored immediately and verified green.

## Traceability

| Criterion | Behaviors | Tests | End-to-end |
|---|---|---|---|
| AC-1 (5-column table renders) | A1, U3, U12, U13, U14, U15, U32, U44 | `RecentConversationsSection.spec.js::renders 5 table headers`, `ScoutOverview.spec.js::embeds RecentConversationsSection`, `scout_overview_reports_controller_spec.rb::GET /conversations authorized member` | Yes — exercises component mount and real HTTP endpoint |
| AC-2 (status filter pill filters) | A2, U8, U21, U22, U33, U34 | `RecentConversationsSection.spec.js::clicking a status filter pill updates active status`, `scout_overview_reports_controller_spec.rb::filters conversations to matching status` | Yes — exercises pill click re-fetch and backend SQL filtering |
| AC-3 (pagination next page) | A3, U23, U39 | `RecentConversationsSection.spec.js::renders PaginationFooter and fetches page on page change`, `scout_overview_reports_controller_spec.rb::paginates results` | Yes — exercises pagination event and backend envelope |
| AC-4 (period/scout selector sync) | A4, U45, U46 | `ScoutOverview.spec.js::synchronizes recent conversations when period changes`, `synchronizes recent conversations when scout selector changes` | Yes — exercises prop propagation on real page container |
| AC-5 (transferred neutral styling) | A5, U16, U31 | `RecentConversationsSection.spec.js::displays transferred without opportunity with neutral styling`, `ConversationStatusBadge.spec.js::renders neutral slate styling`, `scout_overview_reports_controller_spec.rb::builder classifies transferred_without_opportunity` | Yes — exercises badge classes and SQL fallback |
| AC-6 (row click new tab) | A6, U41 | `RecentConversationsSection.spec.js::invokes window.open on row click with target _blank and noopener,noreferrer` | Yes — exercises row click and native URL construction |
| AC-7 (graceful error handling) | A7, U42, U43 | `RecentConversationsSection.spec.js::displays warning notification when conversation ID is missing`, `displays warning notification when popup is blocked` | Yes — asserts specific alert messages for both failure modes |

Untested criteria: none. Tests tracing to nothing: `scoutOverviewReports.spec.js:6-10` (framework check, noted in Finding 1).

## What was not audited

- **Full Ruby test suite**: Only the targeted feature request spec (`custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb`, 52 examples) was run in this pass; the full suite (~16 minutes) was skipped. The pre-existing order-dependent failure in `spec/builders/agent_builder_spec.rb:47` is documented in `tdd-profile.md` and unrelated to this feature.
- **Automated mutation testing**: No automated mutation tool is installed or configured for Ruby or JavaScript in this repository; evaluation relied on 6 sampled deliberate mutants on high-risk behaviors.
- **Playwright E2E browser suite**: Detected in repository under `tests/playwright/`, but requires a live running Chatwoot server with seeded account credentials; not executed during this verification.
- **Performance at scale**: SC-002 specifies <1s response time on datasets of up to 10,000 conversations; sub-second performance at that scale was not verified under synthetic load.
- **This audit was conducted from cold context** by re-reading all test and source files directly, but within the same session environment.
