# Research: Scout V2 First-Cut Playbooks and Degradation on Missing Capabilities

Phase 0 of `/speckit.plan` for [spec.md](./spec.md). Every item was resolved against the code in
this repository (paths are project-relative). No `NEEDS CLARIFICATION` remains.

---

## §1 — Storing the completed list

**Decision**: one additive migration on the fork-owned table:
`add_column :ichatr_scout_conversation_states, :completed_playbooks, :jsonb, default: [], null: false`
(`db/migrate/21260928000000_…`). Written only through the two existing exit operations of
`ScoutConversationState`, which gain a `completed:` keyword and merge the name as a set union in the
**same** `update!` as the routing-state change (FR-026 "together with").

**Rationale**: the spec clarification fixes the storage (jsonb string array, one migration, per
conversation row). A conversation-state row is created per conversation (`for_conversation` →
`find_or_initialize_by(conversation_id:)`), so FR-025 ("empty for every new conversation, even for the
same contact") holds with no extra logic; escalation and hand-back never touch the column (FR-027).
Folding the union into the existing `update!` keeps the exit's routing change and the completion one
write, inside the exit's existing transaction/lock.

**Alternatives considered**: a join table (overkill for ≤ 3 names per conversation); a separate
`mark_completed!` call after the exit (two writes, and easy to call on a refused path by mistake).

**Dev-DB caution** (AGENTS.md): run the migration against a clean `chatwoot_dev`; `spec/config/schema_spec.rb`
fails if `db/schema.rb` picks up foreign objects.

## §2 — Which name is marked completed

**Decision**: every exit passes `completed: turn_scope.active_procedure_name`.

**Rationale**: `TurnScope#active_procedure_name` already is "the last procedure in effect": set from
the routing decision at turn start, by `OpenPlaybook#activate_procedure!`, and by
`Exits::Transition` (after the state write); a situational takeover (`replace_with_baseline!`) does
not touch it; terminal/escalation exits do not clear it. For declared terminal/transition exits it
is always the declaring playbook, because (a) declared exits are registered only by
`TurnScope#actions_for(playbook)` for the playbook being made active, (b) a transition replaces the
tool set with the target's (the source's exits disappear), (c) a takeover replaces the tool set with
the baseline, and (d) 087 FR-007 allows at most one procedure per turn. So one rule covers the three
exit kinds and the clarification's "escalation marks the last procedure in effect, including after an
interruption took over". `nil` (nothing in effect) adds nothing. Refused/failed paths return before
the state operation, and the limit-refused transition calls `record_transition!` on its refusal
branch, which ignores `completed:`.

**Edge accepted**: a transition may target a procedure that is already completed (the transition
exit ignores the target's state conditions, 087 FR-011; spec FR-028c states it explicitly). With the
shipped catalog this requires `identificacao` to be pinned while `qualificacao` is completed — only
possible if a human removes a contact's phone after qualification. The target runs; routing-by-state
guarantees (FR-028/a/b) are unaffected. No extra guard (Principle II).

## §3 — New state conditions and argument validation

**Decision**: five predicate classes (`ContactIdentityIncomplete`, `ContactHasPhone`,
`InQualification`, `OpportunityInStage`, `PlaybookNotCompleted`) registered in
`Predicates::Registry`, which gains an `ARGUMENTS` map (`opportunity_in_stage → :stage_role`,
`playbook_not_completed → :playbook_name`). Boot validation of names, argument presence/absence and
argument values moves out of `Playbook::Validator` into a new `Playbook::DependencyRules`
(together with `requires`, `needs` and marker checks — §6), which the Validator calls.

**Rationale**:
- Placeholder detection reuses `Custom::Scout::ContactIdentityService.placeholder_name?` — "the same
  detection the existing engine uses" (FR-006); v1 also treats a blank phone as a separate gap.
- `opportunity_in_stage` reads the snapshot's existing `opportunity_stage_role` (`:initial`,
  `:qualified`, `:unqualified`, `:none`), which already maps the scout's configured stage ids.
- `in_qualification` composes the two existing predicate classes for its second branch, so it is
  "exactly" them (FR-009b), not a re-implementation.
- The Loader already parses `- name: arg` into `[name, arg]`, so no syntax change is needed.
- `playbook_not_completed` accepts only a procedure playbook (non-empty `when_state`) of the loaded
  catalog (FR-009a): situational playbooks are never recorded as completed (FR-026), so naming one
  would make the condition always hold without anyone noticing.
- `Playbook::Validator` is at the `Metrics/ClassLength` limit (≈ 175 code lines); extracting the
  dependency checks (and moving the two existing `validate_when_state`/`validate_requires` there)
  keeps it under without a `.rubocop_todo.yml` entry.

**Alternatives considered**: a generic expression language (`any_of:`) in `when_state` — rejected,
the only OR the catalog needs is `in_qualification`, and the clarification named that predicate.

## §4 — `in_qualification` and pending fields without an opportunity

**Decision**: `RoutingSnapshot::PendingFields.call(scout:, opportunity:)` (extracted from the
Builder) returns the scout's qualification requirement keys when `opportunity` is nil; unchanged
otherwise. Builder, `UnsatisfiedItems` and `ContentBuilder` all use it.

**Rationale**: FR-009b: "When the conversation has no active opportunity, the pending fields shown to
the assistant MUST be the scout's qualification requirements". The only other consumer of
`pending_fields` is `PendingRequiredFields`, which is used only together with `OpportunityOpen`
(false without an opportunity), so routing is unaffected outside `in_qualification`. Creating the
opportunity stays the model's job through `manage_opportunity` (existing continuity resolution);
nothing is created in Ruby (FR-011b).

## §5 — Procedure content: one renderer, context blocks tied to the conditions that read them

**Decision**: new stateless `Playbook::ContentBuilder` renders every appearance of playbook guidance —
pinned (system instructions), `open_playbook` result, transition result — as: body with markers
resolved, the pending-steps notice when anything is pending, and, for procedures, a context block per
fact their `when_state` reads: pending fields for `in_qualification`/`pending_required_fields`,
missing contact data for `contact_identity_incomplete` (new `ContactGapsFormatter`). Blocks are
computed fresh at render time (`reload_active_opportunity`, current contact).

**Rationale**:
- FR-016 requires pending steps to be shown "when a pinned **or opened** playbook" has unsatisfied
  requirements, and US3-AS2 needs them after `qualificado`'s transition — so the transition and
  `open_playbook` paths must render too; today they return the raw body.
- The v2 prompt carries no contact context. Without the missing-data block `identificacao` could not
  know which items to ask for (FR-010 "each missing item"); v1 derived this from the same two facts.
- Tying blocks to the playbook's own conditions keeps them scoped (design goal of the epic): the
  pending-fields list no longer appears during `identificacao` (where it would invite qualification
  questions), and identity gaps never appear during `qualificacao` (where they would re-open
  identification after it completed — FR-028).
- Fresh computation matters for the same-turn chain `identificacao → qualificacao` and for a
  qualification that creates the opportunity mid-turn.

**Alternatives considered**: a templating syntax in bodies (`{{pending_fields}}`) — more surface for
authors to get wrong; an always-on contact block in the system instructions — contradicts the
brief's goal of removing always-on identity guidance.

## §6 — Pending steps: marker syntax and exit withholding

**Decision**: steps name their dependencies with `[[depends: a, b]]` (contract:
[playbook_catalog.md](./contracts/playbook_catalog.md#pending-step-markers)). `ContentBuilder`
replaces a marker with `(PENDENTE — indisponível: …)` when any named item is unsatisfied, strips it
otherwise, and appends one fixed notice. `TurnScope#actions_for` omits a playbook's declared exits
while any of its `requires` is unsatisfied; `needs` alone never withholds exits (FR-017 speaks of
capabilities; spec Assumptions: all-exits, not per-exit).

**Rationale**: FR-015 wants each dependent step to "identify which one"; FR-019 wants satisfaction to
change rendering with no file edit — an inline marker satisfies both and is checkable at boot
(names must be the playbook's own `requires`/`needs`). Withholding in `actions_for` covers every
entry path (pinned, opened, transition target) in one place.

## §7 — Unsatisfied-items record: when, what, where

**Decision**: computed once per model turn by new `Custom::ScoutV2::UnsatisfiedItems`, right after
`chat.ask` returns. Inside `instrument_agent_session`, `UnsatisfiedItems.trace!` builds it (reads only)
and sets it as trace metadata on the current (agent-session) span
(`langfuse.trace.metadata.unsatisfied_flags`, JSON); after that block returns, `TurnRunner` persists it
to the existing `unsatisfied_flags` column ([turn_assembly.md §6](./contracts/turn_assembly.md)). Shape and key names in
[data-model.md](./data-model.md#unsatisfied-items-record-unsatisfied_flags-value-and-trace-metadata);
`unmet_requires` keeps the key the trace already used, `unmet_needs` mirrors the `needs` frontmatter
key, `procedure` names the playbook.

**Rationale**:
- The record must describe the last procedure in effect and survive the clearing done by an exit
  (clarification Q4) — so it can only be computed after the tool loop ends, and it is written after
  every exit write of the turn, so nothing can clear it afterwards.
- Placing it before `build_final_reply` covers the empty/unreadable-output fail-safe (FR-018 "including
  … the fail-safe transfer") and the escalated empty reply alike. The quota/API-key fail-safe never
  routes or calls the model; it writes nothing (there is no "procedure in effect").
- Today the metadata (`metadata_for`) is computed before `ask` from the routing decision; keeping
  `playbook`/`activation_reason` there satisfies "the trace's playbook and activation reason keep
  describing the routing decision", and dropping the start-of-turn `unsatisfied_flags` avoids two
  contradictory values on one trace.
- `unsatisfied_flags` already exists (Brief 02 schema) and was never written, so no new column
  (spec Assumptions).
- `instrument_agent_session` does not yield its span; `tracer.in_span` makes it the current span, so
  `OpenTelemetry::Trace.current_span` is that span inside the block and a no-op span when OTel is off.

**Risk addressed**: `instrument_agent_session` rescues `StandardError` and re-runs its block while
`executed` is still false (`lib/integrations/llm_instrumentation.rb:45-47`). A write inside the block
that raised (e.g. `RecordNotUnique` when FR-018 creates the row concurrently) would silently repeat
`chat.ask` and every exit of the turn — duplicate transitions, stage moves and transfers — instead of
failing loudly. So no write happens inside the block: the persist runs after it, where a failure
raises out of the turn. No rescue added (Principle II).

## §8 — Satisfaction and the satisfied path (FR-019)

**Decision**: satisfaction stays a routing-snapshot fact: `satisfied_capabilities` (exists) and
`satisfied_business_facts` (new), both always `[]` from the Builder in this feature. `TurnScope`,
`ContentBuilder` and `UnsatisfiedItems` read only these lists. FR-019's satisfied path is verified by
building a snapshot with both lists filled and driving those three real components (no double),
with the unmodified shipped `agendamento.md`.

**Rationale**: there is no satisfaction source until Brief 07 (spec Assumptions), and adding an env
flag or config just for tests would be speculative production code. Constructing the input value is
not a test double, so Principle VII holds. The request/job acceptance specs cover the unsatisfied
path end-to-end; the satisfied path is proven at component level (`content_builder_spec`,
`turn_scope_spec`, `unsatisfied_items_spec`) because no production path can produce it yet. The spec
therefore states it as a design property of FR-019, not as an acceptance scenario, so Principle VI
("every acceptance criterion through the real entry point") is not deviated from; it gains a request
example when Brief 07 delivers a satisfaction source.

## §9 — Playbook authoring: sources, names, priorities

**Decision**: exact frontmatter in [contracts/playbook_catalog.md](./contracts/playbook_catalog.md).
Priorities 100/60/50/30/20/10 (`fora_de_prospeccao`/`duvida_comercial`/`pausa`/`identificacao`/
`agendamento`/`qualificacao`) — `qualificacao` keeps 10. Exit names: `identificado`;
`qualificado`, `desqualificado` (`motivo: string`); `agendado` (`inicio: datetime`), `sem_horario`
(`motivo: string`). Bodies in Portuguese, ported from the v1 sources:

| Playbook | v1 source (text carried over, minus v1 tool names) |
|---|---|
| `identificacao` | `SystemPromptsService#identity_warning`, `#phone_request_warning`, guardrail "Identidade do contato" |
| `qualificacao` | `FunnelSectionBuilder#build_funnel_guidelines_lines` (minus the stage-move/transfer/"tools are sufficient" bullets, now structural), guardrail "Intenção Comercial" |
| `fora_de_prospeccao` | guardrail "Reconhecimento de intenção fora de prospecção" |
| `duvida_comercial` | `SystemPromptsService#knowledge_tool_instruction` + Anti-alucinação |
| `pausa` | guardrail "Respeito ao ritmo do lead" |
| `agendamento` | brief 06 §5 / design §6 (new capability, no v1 source) |

**Rationale**: FR-002 table; FR-003 order; the exit names are the brief's outcome names; `motivo`
matches the note-reason convention of 087's declared escalations. v1 text stays in place (FR-024,
Brief 10 removes it).

## §10 — Model-behavior scenarios vs. scripted verification

**Decision**: scenarios whose outcome depends on model wording (US1-AS3 name before phone, US1-AS5
ask once then leave, US1-AS16/AS17 opportunity only on commercial interest, US2-AS2 answer from the
knowledge base, US2-AS4 no qualification question, US3-AS7 no slot offered) are worded in the spec as
the instruction/actions contract the system controls on that step — the rule present in the
instructions or in the content returned by an opening, the forbidden tools absent, declared exits
withheld, and the state effect of each scripted call (e.g. `exit_identificado` succeeds with the
phone still blank; a turn without `manage_opportunity` leaves no opportunity). They are asserted in
request/job specs through the real engine with Gemini stubbed at HTTP; the model's actual wording is
observed in the manual playground pass ([quickstart.md](./quickstart.md) §4, SC-007).

**Rationale**: with the provider stubbed, the reply text is whatever the stub returns; asserting it
would test the stub (Principle VII). Wording the acceptance criteria as the contract keeps every one
of them testable through the real entry point (Principle VI).

## §11 — Test strategy

- **Acceptance through the real engine**, Gemini `generateContent` stubbed with WebMock (the only
  double; 087 pattern):
  - new request spec `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb`
    runs the **shipped** catalog (no `SCOUT_V2_PLAYBOOKS_DIR`): US1, US2, US3 multi-turn scripts,
    offered `functionDeclarations` per provider request, system text per request, `tool_calls`,
    `ScoutConversationState` columns, opportunity/contact rows.
  - new context in `custom/spec/jobs/custom/scout/process_message_job_spec.rb` (inbox): transfer +
    completed list (US1-AS12, US2-AS1), hand-back re-routing (US3-AS9, SC-010, edge "hand-back keeps
    the list"), fail-safe adds nothing, unsatisfied record after `qualificado → exit_handoff`
    (US3-AS8).
- **Trace metadata** at the entry point: a trace context in the playground request spec
  (`playground_first_cut_catalog_spec.rb`) with the real SDK and no stub of an internal class. Real
  `InstallationConfig` rows (`OTEL_PROVIDER=langfuse`, `LANGFUSE_BASE_URL`, `LANGFUSE_PUBLIC_KEY`,
  `LANGFUSE_SECRET_KEY`) make `ChatwootApp.otel_enabled?` true and let `OpentelemetryConfig.initialize!`
  configure the SDK provider; the context attaches
  `SimpleSpanProcessor.new(OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new)` to that
  provider, stubs the Langfuse OTLP endpoint with WebMock (external HTTP boundary), and restores the
  previous global provider and calls `OpentelemetryConfig.reset!` afterwards. Its examples assert, on
  finished spans: `langfuse.trace.metadata.unsatisfied_flags` equals the persisted record naming
  `agendamento`'s three items (US3-AS6, and US3-AS8 after `qualificado → exit_handoff`, with
  `…metadata.playbook`/`activation_reason` still describing the routed `qualificacao`/`state`); a
  trigger-stored procedure yields `activation_reason == 'trigger'`; no LLM-call span carries the
  dropped start-of-turn `unsatisfied_flags`; and, on both `llm.scout_v2.turn_runner` spans (agent
  session and its child LLM call), `langfuse.user.id`, `langfuse.session.id`, `langfuse.trace.tags`,
  `langfuse.observation.metadata.feature_name`, `…metadata.scout_id`/`playbook`/`activation_reason`,
  plus `gen_ai.request.model` on the LLM-call span. These replace the `turn_runner_spec` examples
  'populates turn metadata with trigger activation_reason…' (L467–490) and 'wraps the LLM call with
  instrument_agent_session…' (L556–581), which double `ChatwootApp`, the tracer and the runner under
  test (Principle VII). Every property those examples assert is asserted again on real spans (tasks
  T066 examples 3–4); only the start-of-turn `unsatisfied_flags` expectation goes, replaced by the
  turn-completion record (FR-018).
- **Unit**: predicate specs (5 new), `routing_snapshot/builder_spec` (completed list, pending fields
  without opportunity), `validator_spec` (every new violation, one error), `catalog_spec` (shipped
  catalog: FR-001/002/003/005 facts, validates clean), `content_builder_spec` (markers pending vs.
  satisfied, notice, context blocks by condition), `turn_scope_spec` (content rendering, withholding,
  satisfied path) with a real `scout.llm_chat` (offline until `ask`), `unsatisfied_items_spec` (record
  per last procedure; empty lists when satisfied or nothing in effect), `scout_conversation_state_spec`
  (union, idempotence, refusal branch, `record_unsatisfied_items!`), `router_spec` exhaustive
  combinations for SC-004 / US2-AS6 with the shipped catalog (exhaustiveness is a router property;
  the playground spec adds representative combinations through the entry point, Principle VI).
- **Mutation checks** listed in [quickstart.md](./quickstart.md) §5.

## §12 — Existing specs that depend on the shipped catalog

**Decision**: specs that test the 085/087 *mechanisms* stop depending on the shipped files. A frozen
fixture `custom/spec/fixtures/scout_v2/qualificacao_procedure.md` (new directory, referenced by explicit `Rails.root.join`; the pre-088
`qualificacao.md`: `when_state [opportunity_open, pending_required_fields]`, `tools
[manage_opportunity]`, no exits) replaces every `FileUtils.cp(Rails.root.join('custom/playbooks/qualificacao.md'), …)`,
and contexts that ran on the shipped directory get the same fixture directory through the existing
`Dir.mktmpdir` + `with_modified_env SCOUT_V2_PLAYBOOKS_DIR:` pattern. The shipped catalog's behavior
is asserted only by the new 088 specs (§11). These are contract changes, not red-first claims.

**Rationale**: under the new catalog, factory contacts (`Contact N`, `phone_number: nil`) and the
playground sandbox contact (`Scout Playground (…)`, no phone) are "identity incomplete", so every
shipped-catalog example would route to `identificacao`; and the new `qualificacao.md` declares a
transition to `agendamento`, which a single-file fixture directory cannot resolve. Pinning the
mechanism specs to a frozen fixture keeps them about the mechanism.

Scan (read-only, 2026-09-28):

| Spec | Depends on shipped catalog | Change |
|---|---|---|
| `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` | L49–215 and L275–741 run the shipped dir; L196, L386 call `Loader.load_all` without args; L225 copies `qualificacao.md` | one `around` hook on `describe '#perform'` runs every example with `SCOUT_V2_PLAYBOOKS_DIR` = a tmp dir holding the frozen fixture (the argument-less `Loader.load_all` calls then read it); 'dynamically reflects newly added playbooks…' (L217) copies the fixture instead of the shipped file into its own tmp dir. In 'executes open_playbook during the turn…' (L360–395) the result-body expectation (L386–387) is removed — the example stubs `scout.llm_chat` and doubles `RubyLLM::Chat` (Principle VII), and the rendered-result contract is asserted by the playground FR-028c re-opening example (T036) — and L390 becomes the 085 parity check `open_pb_call[:result] == open_pb_tool_result`. The L467–490 and L556–581 examples (doubles of `ChatwootApp`, the tracer and the runner under test) are removed and their assertions move to the playground trace context (§11). The file's other pre-existing `fake_chat`/`scout.llm_chat` doubles stay in the untouched 085/087 mechanism examples (Principle VI restraint); no 088 assertion is written in this file |
| `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb` | L154, L167 copy `qualificacao.md` | copy the frozen fixture instead. FR-018 contract change: L803, L868, L1176, L1261 (`state.reload.attributes == snapshot`) and L927, L940 (sandbox row absent) — every completed model turn now writes `unsatisfied_flags`, creating the row when absent |
| `custom/spec/jobs/custom/scout/process_message_job_spec.rb` | L208–313 ('with the real Scout V2 engine and exits (US1)') runs the shipped dir | run it in the frozen-fixture dir. FR-018 contract change: L290, L307 (row absent) and L456, L528, L591, L616 (`state.reload.attributes == initial_snapshot`) |
| `custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb` | — | L120–123 "empty array when there is no opportunity" becomes "scout qualification requirement keys when there is no opportunity" (FR-009b); L216–218 extended with `completed_playbooks`/`satisfied_business_facts` |
| `custom/spec/services/custom/scout_v2/routing_snapshot_spec.rb` | — | defaults for the two new members |
| `custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb` | in-memory playbooks; `TurnScope` built without `setup_initial_tools!` | the scope gets its snapshot through `setup_initial_tools!(…, ctx:)` (the only snapshot entry, turn_assembly §4) with a real Builder snapshot; the L228/L238 registered-tool sets gain the production baseline's `exit_handoff`; L213 body equality now against `content_for` (identical: the in-memory playbook has no markers and its `when_state` reads no context fact) |
| `custom/spec/services/custom/scout_v2/exits/exit_tool_spec.rb` | in-memory target playbook; `TurnScope` built without `setup_initial_tools!` | same snapshot wiring; L180 transition result stays exact-equal (the target has no markers and no `when_state`) |
| `spec/config/scout_v2_playbooks_spec.rb`, `loader_spec`, `validator_spec` | fixture dirs / in-memory only | unaffected (validator_spec gains new examples) |

FR-018 cutover rule (T066a): each listed assertion compares every column except `unsatisfied_flags`
and `updated_at` with its snapshot (row-absent assertions: the only row holds default routing
columns and `completed_playbooks == []`), and additionally asserts `unsatisfied_flags` equals the
record FR-018 prescribes for that turn (`procedure: nil` and empty lists when no procedure was in
effect). The rule each example protects — no transfer, no stage change, no routing change on a
refused or absent exit — is kept; only the new `unsatisfied_flags` write is admitted.

Other contract changes re-scanned (2026-09-28): the pending-fields block now follows the playbook's
`when_state` instead of being appended to every pinned procedure. Every existing assertion on that
block (`turn_runner_spec` L112–114, L736; playground spec L515, L813–814, L879) runs on the frozen
fixture, whose `when_state` reads `pending_required_fields`, or on a situational takeover, so none
changes. No other exact-body assertion on an `open_playbook` or transition result exists in the
playground or job specs.

Factory facts: `spec/factories/contacts.rb` default name `Contact N` (never matches
`/\A[a-z]+-[a-z]+-\d{1,3}\z/`), `phone_number` nil unless `:with_phone_number`.
