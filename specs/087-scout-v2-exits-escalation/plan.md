# Implementation Plan: Scout V2 Escalation Layer, Declared Exits, and an Auditor-Free Turn

**Branch**: `087-scout-v2-exits-escalation` | **Date**: 2026-09-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/087-scout-v2-exits-escalation/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

Every v2 outcome becomes an explicit exit tool, validated in Ruby before any write, returning text
(never `RubyLLM::Tool::Halt`) so the model writes the customer's single final reply in the same
`chat.ask`. Playbook frontmatter gains typed exit declarations (`kind`, `fields`, `target`, `stage`),
normalized by `Playbook::Loader` into `ExitDeclaration` values and checked at boot by
`Playbook::Validator`. One exit tool class (`Exits::ExitTool`) serves declared exits and the always-on
built-in `exit_handoff`; per-kind effects (`Exits::Terminal`, `Exits::Transition`, `Exits::Escalation`)
reuse Brief 02's `ScoutConversationState` operations, `OpportunityStageTransitionService` for stage
moves, and a new additive `HandoffService#transfer!` for the escalation's team/`bot_handoff!`/note,
all inside `conversation.with_lock` so a refused escalation writes nothing. A per-turn
`Custom::ScoutV2::TurnScope` replaces Brief 11's `OpenPlaybook::TurnSetup`: it owns the baseline
(`search_knowledge_base`, `exit_handoff`, `open_playbook`), registration of a playbook's tools+exits,
the takeover/transition replacement, and the turn-ended guard. A new always-on `[Escalation]`
instruction block follows the Playbook Index; the transfer-closing rule exists only in the escalation
exit's result. The v2 registry offers `manage_opportunity` (a v2 subclass without `stage_id` and
without the closing nudge) and `update_contact`; stage-change, transfer and custom-API tools are
unreachable. `TurnRunner` treats an empty final reply as unreadable (fail-safe on the inbox, error in
the playground) except after an escalation, where the standard handoff message becomes the reply.
v1 (`AgentRunner`, auditor, v1 tools, prompt) is unchanged. No migration.

## Technical Context

**Language/Version**: Ruby 3.4.4, Rails 7.2.3.1

**Primary Dependencies**: RubyLLM 1.15.0 (sequential tool loop; unavailable-tool calls return an
error Hash instead of raising; `with_tools(replace: true)`; `before_tool_call` callback; instance
`name`/`description`/`params_schema` honored by the Gemini adapter — research §1). Existing
`Custom::ScoutV2::*` engine (`TurnRunner`, `Router`, `Playbook`/`Loader`/`Validator`/`Catalog`/
`OpenableSet`/`IndexBuilder`, `Tools::Registry`, `Tools::OpenPlaybook`, `Instructions::Builder`),
`ScoutConversationState` (Brief 02), `Custom::Scout::{HandoffService,OpportunityStageTransitionService}`,
`Custom::Scout::Tools::{BaseTool,CallRecorder,ManageOpportunity,UpdateContact,SearchKnowledgeBase}`.

**Storage**: PostgreSQL — no migration. Writes existing columns only: `ichatr_scout_conversation_states`
(`active_playbook`, `activated_at`, `activation_reason`, `last_exit`, `transition_count`,
`handoff_limit_reached_at`), `opportunities.pipeline_stage_id`, `conversations.{team_id,status}`,
`messages` (private transfer note). See [data-model.md](./data-model.md).

**Testing**: RSpec in the `rails` container, targeted files only (Principle IX). Doubles only at the
external boundary: the Gemini `generateContent` HTTP API via WebMock (research §16).
- **Playground acceptance** — new real-engine context in
  `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb` with a fixture
  catalog (terminal/transition/escalation exits with typed fields and a stage role) via
  `Dir.mktmpdir` + `with_modified_env SCOUT_V2_PLAYBOOKS_DIR:` (existing pattern).
- **Inbox acceptance** — new real-engine context in `custom/spec/jobs/custom/scout/process_message_job_spec.rb`
  (`described_class.new.perform(conversation.id)` on a `pending` conversation): transfer, notes,
  messages, routing state, fail-safe, one-call count with `feature_response_auditor: true`. FR-022's
  mid-turn takeover is simulated inside a WebMock `to_return` block (boundary, not a domain stub).
  Scouts in these contexts set `feature_memory: false` wherever the pre-existing fail-safe runs, so
  its contact-memory request does not consume a stubbed turn response (research §11) — except the one
  US4-AS9 example, which sets `feature_memory: true` and stubs that memory request at the same HTTP
  boundary to pin FR-019's "top-level" definition (the memory request is the only extra one).
- **Unit** — `exits/payload_validator_spec.rb` (pure), `exits/exit_tool_spec.rb` and
  `tools/open_playbook_spec.rb` with a real `scout.llm_chat` (offline until `ask`), `loader_spec`,
  `validator_spec`, `tools/registry_spec.rb`, `tools/manage_opportunity_spec.rb` (v2 subclass).
- **Cutovers** (contract changes, research §16; tasks T002/T003/T008/T010/T011): baseline tool
  lists + `exit_handoff`; header lists + `Escalation`; `TurnSetup` → `TurnScope` in
  `open_playbook_spec`; `turn_runner_spec`'s shared `fake_chat` allows `before_tool_call`
  (pre-existing `RubyLLM::Chat` doubling not extended, no new examples there, not used as
  evidence); flat `exits:` examples → new shape.
- **Test-first order** — each phase in tasks.md writes its tests before its implementation.
  `TurnScope` first lands as a no-behavior-change refactor on a green suite (T007–T009);
  `HandoffService#transfer!` and `OpportunityStageTransitionService#moved?` are driven red-first by
  the US1/US3 acceptance examples that first need them, so the v1 spec files stay unedited.
- **Mutation resistance** — deliberate-mutant table in [quickstart.md](./quickstart.md) §5.

**Target Platform**: Rails app server + Sidekiq (containerized, rootless Podman)

**Project Type**: Web application backend module (fork-owned `custom/` tree in a Rails monolith; no
frontend change — the playground already renders `tool_calls`)

**Performance Goals**: exactly one top-level call per v2 turn — the turn's reply-producing
`chat.ask`, one provider request per step on one growing transcript — including invalid-then-corrected
exits (FR-019/SC-001); zero reply-audit calls on v2. Not top-level (spec Terminology): model calls
inside a tool, and the fail-safe's existing contact-memory generation.

**Constraints**: v1 behavior byte-for-byte unchanged (FR-025) — v1 files receive only additive,
unreferenced-by-v1 members (`HandoffService#transfer!`, `OpportunityStageTransitionService#moved?`);
escalation all-or-nothing under a row lock (FR-022); no `Tool::Halt`; no `return` inside transaction
blocks; `Metrics/ParameterLists` ≤ 5 and `Metrics/ClassLength` ≤ 175 (TurnRunner is at 164 code
lines — tool assembly moves to `TurnScope`), no `.rubocop_todo.yml` additions.

**Scale/Scope**: 0 migrations; new files: `playbook/exit_declaration.rb`, `turn_scope.rb`,
`instructions/escalation.rb`, `exits/{exit_tool,payload_validator,stage_move,terminal,transition,escalation}.rb`,
`tools/manage_opportunity.rb` (v2 subclass); changed: `turn_runner.rb`, `tools/open_playbook.rb`,
`tools/registry.rb`, `playbook/loader.rb`, `playbook/validator.rb`, `custom/scout/handoff_service.rb`
(+1 method), `custom/scout/opportunity_stage_transition_service.rb` (+1 reader).

All Technical Context items resolved in [research.md](./research.md); no `NEEDS CLARIFICATION`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Upstream Compatibility First | PASS | Every file lives under `custom/`. `HandoffService`/`OpportunityStageTransitionService` are fork-owned (`custom/app/services/custom/scout/`), not upstream/Enterprise, so no MANIFEST entry is required; both changes are additive members. No migration, no core table. |
| II. Smallest Production-Ready Change | PASS | No v2 `ResponseSchema` (already plain text, 083 D9), no job change, no retry cap, no trace metadata, no memory in escalation (spec Assumptions). `TurnScope` replaces (not adds to) `TurnSetup`. One exit class for all kinds incl. the built-in. The Loader shape checks (including an unknown key in an exit entry, which prevents a silently dropped stage move from a YAML typo) are part of FR-006 (research §3). The one-procedure-per-turn rule (FR-007) is one guard in `OpenPlaybook`, mirroring `OpenableSet`'s existing pinned rule, and makes exit-name collisions between procedures impossible without a catalog-wide uniqueness check. |
| III. Established Conventions | PASS | Loader-shape / Validator-semantics split mirrors `when_state`; `{ error: }` tool-result shape mirrors `open_playbook`; Portuguese model-facing text like other v2 sections; `Data.define` values like `Playbook`/`Router::Decision`; RuboCop limits respected by design (research §4). No user-facing UI strings → no i18n files change (the standard handoff message reuses `conversations.scout.handoff`). |
| IV. Safe, Reversible Change | PASS | No migration, no destructive operation; escalation writes are one transaction. Rollback = unset `scout_v2` flag (v1 path untouched). |
| V. Dual-Tree Awareness | PASS | `grep -rln Scout enterprise/` → no matches (re-verified 2026-09-27). No Enterprise counterpart; decision stated in the PR description (tasks T053). |
| VI. TDD | PASS | Every acceptance scenario, including US4-AS3/AS9, US3-AS5, US2-AS7/AS8/AS10 and every US1-AS8 variant, maps to a request-spec (playground) or job-spec (inbox) example through the real engine (quickstart §1 table). In tasks.md each phase's tests precede its implementation; `TurnScope` first lands as a no-behavior refactor on green; cutover edits to existing assertions are labeled as contract changes, not red-first claims. |
| VII. Observable Behavior / Mutation Resistance | PASS | Only WebMock at the provider HTTP boundary; assertions on HTTP payload, persisted rows, messages, outgoing provider bodies. No new stubs of `Scout`, `Conversation`, `HandoffService`, `TurnRunner` or `RubyLLM::Chat`. Deliberate-mutant table covers high-risk rules. |
| VIII. Functional Slices | PASS | Slices: (0) declarations — loader+validator, and the `TurnScope` refactor; (1) escalation layer + built-in `exit_handoff` + guard (US1); (2) declared exits, all kinds + one procedure per turn (US2); (3) stage move + catalog cutover — registry, v2 `manage_opportunity` (US3); (4) final-reply/fail-safe rules + one-call/no-auditor proof (US4). No step journals. |
| IX. Surgical Execution Scope | PASS | Quickstart §1/§2 are targeted file lists; full suite reserved for pre-release. |

**Post-design re-check (after Phase 1)**: PASS — the design added no table, no upstream edit, no
new dependency, and no test double beyond WebMock. Complexity Tracking stays empty.

## Project Structure

### Documentation (this feature)

```text
specs/087-scout-v2-exits-escalation/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── playbook_exit_declaration.md
│   ├── exit_tools.md
│   └── turn_assembly.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
custom/
├── app/services/custom/
│   ├── scout/
│   │   ├── handoff_service.rb                  # + public transfer!(reason:) — team, bot_handoff!, note; no message, no memory
│   │   └── opportunity_stage_transition_service.rb  # + moved? reader (true after a successful save)
│   └── scout_v2/
│       ├── turn_runner.rb                      # [Escalation] block; builds TurnScope + baseline; before_tool_call record; final-reply / fail-safe rules
│       ├── turn_scope.rb                       # NEW — per-turn chat/catalog/baseline, register/replace, actions_for, procedure_in_turn?, turn-ended guard, outcome state
│       ├── instructions/
│       │   └── escalation.rb                   # NEW — SECTION constant
│       ├── playbook/
│       │   ├── exit_declaration.rb             # NEW — Data + KINDS/FIELD_TYPES/STAGE_ROLES + HANDOFF
│       │   ├── loader.rb                       # normalize_exits → ExitDeclaration + shape load_errors
│       │   └── validator.rb                    # FR-006 exit rules; exit_handoff token allowed
│       ├── exits/
│       │   ├── exit_tool.rb                    # NEW — RubyLLM tool per exit (name/description/params_schema), validate → dispatch
│       │   ├── payload_validator.rb            # NEW — every-problem payload check
│       │   ├── stage_move.rb                   # NEW — opportunity / role / service checks, moved? detection
│       │   ├── terminal.rb                     # NEW
│       │   ├── transition.rb                   # NEW
│       │   └── escalation.rb                   # NEW — with_lock, care check, transfer!, CLOSING_INSTRUCTION
│       └── tools/
│           ├── open_playbook.rb                # TurnSetup → TurnScope; procedure path registers tools + exits; refuses a 2nd procedure (FR-007)
│           ├── registry.rb                     # manage_opportunity → v2 subclass; + update_contact
│           └── manage_opportunity.rb           # NEW — v2 subclass: no stage_id, no closing nudge
└── spec/
    ├── requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb  # NEW real-engine context (exits); baseline lists + exit_handoff
    ├── jobs/custom/scout/process_message_job_spec.rb                            # NEW real-engine v2 inbox context
    └── services/custom/scout_v2/
        ├── exits/{payload_validator_spec,exit_tool_spec}.rb                    # NEW
        ├── playbook/{loader_spec,validator_spec}.rb                             # new shape + FR-006 violations
        ├── tools/{open_playbook_spec,registry_spec,manage_opportunity_spec}.rb  # TurnScope cutover; registry; NEW v2 subclass spec
        └── turn_runner_spec.rb                                                  # cutover: headers + Escalation, tool lists + exit_handoff, fake_chat allows before_tool_call

# Unchanged: custom/app/jobs/custom/scout/process_message_job.rb, AgentRunner, ResponseAuditor,
# ActionClassifierService, ClaimConsistencyService, SystemPromptsService, v1 tools, custom/playbooks/qualificacao.md.
# No db/migrate entry.
```

**Structure Decision**: single Rails monolith; all production code in the fork-owned
`custom/app/services/custom/scout_v2/` tree established by Briefs 01–04/11, plus two additive members
in fork-owned `custom/app/services/custom/scout/` services reused as effects. No frontend, no schema.

## Risks

- **No stage moves on v2 until Brief 06** — the v2 `manage_opportunity` drops `stage_id` and the
  shipped `qualificacao.md` declares no exits yet. Accepted by the spec (Assumptions); v2 is flag-gated.
- **Subclass couples to a v1 private method** (`ManageOpportunity#already_qualified_update_message`).
  Covered by the v2 manage_opportunity spec; a v1 rename fails it loudly.
- **Row lock during escalation** holds the conversation row for the duration of a stage save, a team
  save, `bot_handoff!` and a note insert — no model call inside (memory generation deliberately not run).
- **Model tool-calling reliability** is now load-bearing (exits); per design, remedy is the account's
  model choice, observed in Langfuse.
- **Procedure opening is now one per turn** (FR-007): with nothing pinned, a model that opens a second
  procedure (or the same one again) gets `PROCEDURE_IN_EFFECT_ERROR`, where Brief 04 used to add the
  second one's tools on top. Switching procedure mid-turn goes through a transition exit.

## Complexity Tracking

*No Constitution Check violations — table intentionally empty.*
