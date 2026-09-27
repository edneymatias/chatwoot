# Implementation Plan: Scout V2 Trigger-Based Playbook Interruption over an Active Procedure

**Branch**: `085-scout-trigger-interruption` | **Date**: 2026-09-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/085-scout-trigger-interruption/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

Replace Brief 04's two pieces of `open_playbook` wiring — the availability gate tied to "no playbook
pinned" (`if decision.playbook` in `TurnRunner#build_tools`) and the tool's full-catalog name
acceptance — with one shared **openable set** definition: the full loaded catalog with nothing
pinned, only playbooks with no `when_state` (situational/interruption playbooks) with something
pinned. It is computed once per turn and reused identically by the always-on playbook index and by
`open_playbook`'s own name-acceptance check.
Opening a situational playbook makes it **own the rest of the turn**: the interrupted procedure's
instructions and additively-registered tools are replaced wholesale (`chat.with_instructions`,
`chat.with_tools(replace: true)`) with the always-on baseline plus whatever the interruption itself
declares, and the opening is **never persisted** to `ScoutConversationState` — so the next turn
starts from exactly the stored state it had before the interruption. The always-on baseline tool
list has one definition, in `TurnRunner`, injected into `Tools::OpenPlaybook` through a
`TurnSetup` value (`baseline_instructions`, `baseline_tools`, `tool_wrapper`), which keeps the
constructor within RuboCop's five-parameter limit (no second copy inside the tool). Opening a
`when_state`-bearing playbook with nothing pinned keeps Brief 04's original behavior verbatim
(additive tools, `activation_reason: trigger` persisted).

Production code: three changed files and one new file in the v2 namespace
(`custom/app/services/custom/scout_v2/{turn_runner.rb,tools/open_playbook.rb,playbook/index_builder.rb}`
plus new `playbook/openable_set.rb`). `IndexBuilder`'s only change is its empty-set line: it now says no
playbook is available to open this turn (`EMPTY_INDEX_LINE`) instead of "no procedure enabled in the
catalog", which would contradict Block 3 whenever a procedure is pinned and the openable set is empty
(FR-003). No schema change, no migration, v1's execution path untouched (FR-015). US1–US3 ship as one
release (spec Assumptions): US1 alone would make interruptions reachable while they still overwrite
the pin.

## Technical Context

**Language/Version**: Ruby 3.4.4 (Rails 7, per `Gemfile`)

**Primary Dependencies**: RubyLLM 1.15.0 (`chat.with_instructions` defaults to
`replace_system_instruction`; `chat.with_tools(*tools, replace: true)` clears `@tools` then
re-registers exactly the given list; `handle_tool_calls` executes a response's tool calls
sequentially, each looked up in the *current* `chat.tools` — all verified in-container against
`ruby_llm-1.15.0/lib/ruby_llm/chat.rb` and by a WebMock-driven probe, see `research.md` §3 and §9),
existing `Custom::ScoutV2::*` engine (`TurnRunner`, `Router`, `Playbook`/`Playbook::Catalog`/
`Playbook::Loader`, `Tools::Registry`, `Tools::OpenPlaybook` from Brief 04,
`Custom::Scout::Tools::{SearchKnowledgeBase,BaseTool,CallRecorder}`), `Integrations::LlmInstrumentation`
(read-only reuse — `BaseTool#call`'s existing `instrument_tool_call` span plus `CallRecorder`'s
`result[:tool_calls]` already produce this feature's reviewable record, see `research.md` §7).

**Storage**: PostgreSQL — no migration. `ichatr_scout_conversation_states` schema unchanged (its
`trigger` `activation_reason` value already exists, delivered by Brief 03); this feature's
persistence-side change is a **new non-write path** (situational playbook opened → nothing
persisted), not a new column.

**Testing**: RSpec, targeted per Constitution Principle IX. Test doubles only at the external
boundary (Principle VII), which for this feature is the **LLM provider's HTTP API**, stubbed with
WebMock (already loaded globally by `spec/spec_helper.rb`, `disable_net_connect!`) — see
`research.md` §9:

- **Real entry point (Principle VI)**: every acceptance scenario is exercised through
  `POST /api/v1/accounts/:account_id/scouts/:scout_id/playground_messages` (`type: :request`)
  with the **real** `TurnRunner`, real `Scout#llm_chat` → real `RubyLLM::Chat`, real `Router`,
  real `ScoutConversationState`. The Gemini `generateContent` endpoint is stubbed with a sequenced
  `to_return` (function-call responses, then a text response), which drives RubyLLM's real tool loop.
  Observable assertions: the HTTP response (`reply`, `tool_calls`), persisted
  `ScoutConversationState`, and the **outgoing provider request bodies** (the external contract:
  system text = `contents[0].parts[0].text`, offered tools = `tools[0].functionDeclarations[].name`,
  tool results = later `contents` entries — shape verified in-container for RubyLLM 1.15 + Gemini).
  New context in the existing `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb`,
  independent of that file's pre-existing `TurnRunner`-doubling examples.
- **Unit (`Tools::OpenPlaybook`)**: a real `RubyLLM::Chat` from the real `scout.llm_chat` (needs a
  `ScoutAccountConfig` row, `scout.rb:60-62`; it builds offline — no HTTP until `ask`); assertions on
  `chat.messages` (system content) and `chat.tools.keys` (symbols, `tool.name.to_sym`), plus persisted
  `ScoutConversationState`. Turn-setup registration mirrors the turn state under test (pinned: procedure
  tool + procedure instructions; nothing pinned: neither). No `instance_double(RubyLLM::Chat)`.
- **Unit (`Playbook::OpenableSet`)**: pure value-in/value-out.
- **Fixture catalog**: per-context `Dir.mktmpdir` + `FileUtils.cp` of the shipped
  `custom/playbooks/qualificacao.md` + inline `File.write` of situational fixtures, activated with
  `with_modified_env SCOUT_V2_PLAYBOOKS_DIR:` — the existing pattern at `turn_runner_spec.rb:221-224`.
  A procedure-only variant (tmp dir with only the copied `qualificacao.md`) is used for the
  "pinned, no situational playbook" case, so it doesn't depend on what ships in `custom/playbooks/`.
- **Cutover (Brief 11 §5)**: `turn_runner_spec.rb`'s pinned tool-catalog example no longer asserts
  `open_playbook` absent while pinned (Brief 04's rule); it keeps only the declared/undeclared tool
  assertions. Its other examples are **not touched**. They stub `scout.llm_chat` with an
  `instance_double(RubyLLM::Chat)`, a pre-existing pattern that Principle VII forbids and that this
  feature neither extends nor rewrites. Every one still holds under the new gate (`research.md` §9),
  and the file runs as regression (quickstart §4). It is **not** evidence for any behavior this
  feature adds or changes in `TurnRunner`: the openable-set gate, the index input, the baseline
  injection and the takeover are all proven by the real-engine request context, which doubles only
  the provider's HTTP API. Retiring the doubled examples is out of scope here (Principle VI:
  "restraint still applies to code the change does not touch").
  `index_builder_spec.rb` changes only in its empty-catalog example, which moves to the new
  `EMPTY_INDEX_LINE` wording (red first on the old constant).
- **Mutation resistance**: deliberate-mutant checks on the high-risk rules (quickstart §6), since
  the repo has no mutation tooling.

**Target Platform**: Rails app server (containerized, rootless Podman per `AGENTS.md`)

**Project Type**: Web application backend module (Rails engine-style namespace inside a monolith;
no frontend surface touched)

**Performance Goals**: No new LLM calls per turn — still exactly 1 top-level `chat.ask`
(`design.md` §4.6's invariant); the takeover happens inside the same `chat.ask`'s tool loop.

**Constraints**: Zero behavior change to the v1 execution path (FR-015); the openable set is
computed exactly once per turn and reused by both the index and `open_playbook` (FR-002/FR-003);
opening a situational playbook never writes `ScoutConversationState` (FR-011); `open_playbook`
never raises for a name outside the openable set (FR-005); turn-setup tool registration stays
per-tool `chat.with_tool` (only the takeover uses `with_tools(replace: true)`).

**Scale/Scope**: Zero migrations, zero new enums, 1 new stateless class
(`Playbook::OpenableSet`), one `Data.define` (`Tools::OpenPlaybook::TurnSetup`, inside
`open_playbook.rb`), a signature cutover + two-path branch on `Tools::OpenPlaybook`, a
bounded rewrite of `TurnRunner#setup_chat`/`#build_tools` (public interface — `.new(...).perform`
— unchanged), and one reworded constant in `Playbook::IndexBuilder` (`EMPTY_CATALOG_LINE` →
`EMPTY_INDEX_LINE`, no other reference in the repo).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Upstream Compatibility First | PASS | Every touched/new file lives under `custom/`; zero migrations, zero upstream/enterprise files touched. |
| II. Smallest Production-Ready Change | PASS | Production diff: `turn_runner.rb`, `tools/open_playbook.rb`, `playbook/index_builder.rb` (empty-set line only), new `playbook/openable_set.rb`. No capability registry, no exit mechanism, no interruption cap, no new instrumentation. Mixed-path and same-step multi-call behaviors (FR-016/FR-017) need no code — they follow from the two paths plus RubyLLM's sequential tool loop. |
| III. Adhere to Established Conventions | PASS | `Playbook::OpenableSet` mirrors the `Tools::Registry`/`Predicates::Registry` compact-class `.call` convention; fixture catalogs reuse the existing `Dir.mktmpdir` + `with_modified_env` pattern; WebMock is the repo's existing HTTP double. RuboCop: `OpenPlaybook#initialize` stays at five parameters (`scout, conversation, chat:, openable:, turn_setup:`), within `Metrics/ParameterLists`' default `Max: 5` (keywords counted, no override in `.rubocop.yml`/`.rubocop_todo.yml`). The flat seven-parameter form would need a `rubocop:disable`, which Brief 04 already had to remove from this constructor (084 T042). See research §6. |
| IV. Safe, Reversible Change Management | PASS | No migration, no destructive operation. |
| V. Dual-Tree Awareness | PASS | `grep -rn Scout enterprise/` → zero matches (re-verified 2026-09-25); no new model/endpoint surface. The "no Enterprise counterpart" decision for the new `Playbook::OpenableSet` goes into the PR description (tasks.md T024). |
| VI. TDD | PASS | Every acceptance scenario has a request-spec example through the real controller → real `TurnRunner`. Tasks are ordered so each new example is red on the code it precedes, for the absence of the behavior and not for a signature mismatch (`tasks.md` names the expected red reason); examples that protect existing behavior (e.g. FR-013, FR-015, the unit-level FR-005 lookup) are labeled guards, not claimed red-first. Deliberate-mutant checks cover high-risk rules. `open_playbook_spec.rb`'s fixture rewrite is a test-only refactor done first, on a green suite against the current `catalog:` signature, in its own commit (T004). T005, still in the Foundational phase and before any red-first example exists, is a behavior-free refactor commit: it moves the production signature, its only production caller (`TurnRunner#build_tools`, still behind the old `decision.playbook` gate and still passing the full catalog) and the spec subject together. No commit leaves a caller on the old signature, and both refactors land on a green suite, so the suite never goes red for a structural reason. |
| VII. Observable Behavior / Mutation Resistance | PASS | Only new double: WebMock at the provider HTTP boundary. No stubbing of `Scout`, `ScoutConversationState`, `TurnRunner`, or `RubyLLM::Chat` in any example this feature adds; the unit spec's `tool_wrapper` is the real `CallRecorder#wrap_tool`, not a recording lambda, and no example asserts that a collaborator was called. Assertions on HTTP response (`reply`, `tool_calls`), persisted state, and outgoing provider payloads / real `chat.messages`/`chat.tools`. Known pre-existing debt: `turn_runner_spec.rb` doubles `RubyLLM::Chat`. This feature doesn't extend it or rely on it as proof (Testing, "Not touched"). |
| VIII. Functional Slices | PASS | A behavior-free foundation (fixtures + `OpenPlaybook` signature cutover, T003–T005), then two slices: (1) openable set + gating + rejection + index wording, together with the `TurnRunner` wiring that computes the baseline once from the openable set and injects it into `OpenPlaybook`; (2) `OpenPlaybook`'s two paths (takeover + non-persistence + Path B), built together. No step journals. |
| IX. Surgical Execution Scope | PASS | Quickstart §1/§4/§5 are targeted file lists; full suite reserved for pre-release. |

No violations — Complexity Tracking table below is empty by design.

## Project Structure

### Documentation (this feature)

```text
specs/085-scout-trigger-interruption/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── open_playbook_tool.md
│   └── turn_prompt_assembly.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
custom/
├── app/
│   └── services/custom/
│       └── scout_v2/
│           ├── turn_runner.rb                    # setup_chat/build_tools: openable set computed once; index + gate from it; OpenPlaybook::TurnSetup (baseline_instructions, baseline_tools, tool_wrapper) injected into OpenPlaybook
│           ├── playbook/
│           │   ├── index_builder.rb              # empty-set line reworded: EMPTY_CATALOG_LINE → EMPTY_INDEX_LINE (FR-003)
│           │   └── openable_set.rb               # NEW — single openable-set definition
│           └── tools/
│               └── open_playbook.rb              # signature cutover (catalog:, tool_wrapper: → openable:, turn_setup:) + nested TurnSetup Data + takeover!/activate_procedure! branch
└── spec/
    ├── requests/api/v1/accounts/scouts/
    │   └── playground_messages_controller_spec.rb  # NEW context: real engine, WebMock at Gemini HTTP — every acceptance scenario
    └── services/custom/scout_v2/
        ├── playbook/
        │   ├── index_builder_spec.rb             # empty-catalog example moves to the EMPTY_INDEX_LINE wording
        │   └── openable_set_spec.rb              # NEW
        └── tools/
            └── open_playbook_spec.rb             # rewritten: real RubyLLM::Chat, situational + when_state fixtures, Path A/B matrix

# turn_runner_spec.rb: one-example Brief 11 §5 cutover; otherwise run as regression (quickstart §4).
# No db/migrate/ entry — this feature adds no schema.
```

**Structure Decision**: Single Rails monolith; every change lives inside the existing
`custom/app/services/custom/scout_v2/` fork-specific tree established by Briefs 01–04. No new
top-level directory, no frontend surface, no database table/column.

## Complexity Tracking

*No Constitution Check violations — table intentionally empty.*
