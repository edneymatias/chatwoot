# Research: Scout V2 Escalation Layer, Declared Exits, and an Auditor-Free Turn

Phase 0 of `/speckit.plan` for [spec.md](./spec.md). Every item below was resolved against the code
in this repository (paths are project-relative) or against the installed gem
(`ruby_llm-1.15.0`, read in the `rails` container). No `NEEDS CLARIFICATION` remains.

---

## §1 — RubyLLM tool-loop facts this design relies on

Verified in `/gems/ruby/3.4.0/gems/ruby_llm-1.15.0/lib/ruby_llm/{chat,tool}.rb` and
`providers/gemini/tools.rb`:

- `Chat#handle_tool_calls` executes a response's tool calls **sequentially**, each looked up in
  the *current* `@tools` (`execute_tool`: `tools[tool_call.name.to_sym]`), then ends with
  `halt_result || complete(&)`. A tool returning a `String`/`Hash` never stops the loop; only a
  `RubyLLM::Tool::Halt` does, and then `ask` returns the Halt with no further model iteration.
- A call to a name **not** in `@tools` does not raise: `execute_tool` returns
  `{ error: "Model tried to call unavailable tool ..." }` and the loop continues. This is what
  gives FR-016 ("an action no longer available MUST return an error for that action only") for
  free after a transition replaces the tool set mid-step.
- `with_tools(*tools, replace: true)` clears `@tools` and re-registers; `with_instructions`
  replaces the system message by default. `before_tool_call { |tool_call| ... }` (non-legacy
  `add_callback`) runs before each call, with `tool_call.name`/`tool_call.arguments`.
- `Tool#call` validates keyword arguments against `method(:execute).parameters`; an `execute`
  with a `**keyrest` signature accepts any keys. `CallRecorder#wrap_tool` already redefines
  `execute` as `|**args|`, so every wrapped tool skips RubyLLM's keyword check.
- Instance-level overrides are honored by the Gemini adapter: `function_declaration_for` reads
  `tool.name`, `tool.description` and `tool.params_schema`; when `params_schema` is `nil` and the
  class declares no `param`, the declaration carries **no** `parameters` key.
  `convert_property` keeps `format` (`copy_common_attributes`: description, enum, format, …).
- Class-level `description`/`param` are per-class instance variables (`@description`,
  `@parameters`) — a subclass does **not** inherit them.

## §2 — Exit handler returns text, never `Tool::Halt`

**Decision**: every exit tool returns a `String` on success and a `{ error: String }` Hash on
rejection. No code path returns `RubyLLM::Tool::Halt`.

**Rationale**: §1 — a Halt ends `ask` without a new iteration, so the customer would receive
nothing (brief 05 decision 3, design §4.6). Returning text lets the model write the final reply in
the next iteration of the same `chat.ask` (FR-009). The `{ error: }` Hash shape matches
`open_playbook`'s existing error contract, which `Integrations::LlmInstrumentation#instrument_tool_call`
already flags as an errored tool span.

**Alternatives considered**: Halt + a second `ask` to get the closing message — rejected, it is
exactly the extra top-level call FR-019 forbids.

## §3 — Exit declaration syntax in playbook frontmatter

**Decision**: `exits:` stays a mapping keyed by exit name (the existing loader contract), but each
value becomes a mapping with explicit keys:

```yaml
exits:
  concluido:
    kind: terminal
    fields: { resumo: string }
  agendar:
    kind: transition
    target: agendamento
  qualificado:
    kind: escalation
    stage: qualified
    fields: { motivo: string, prazo: datetime }
```

Allowed keys: `kind` (required), `fields` (optional mapping `field_name: type`), `target`
(transition only), `stage` (optional, any kind). Type tokens: `string`, `integer`, `number`,
`boolean`, `datetime` (the spec's text / integer / number / true-false / date-time).
Full grammar and validation messages: [contracts/playbook_exit_declaration.md](./contracts/playbook_exit_declaration.md).

**Rationale**: design.md §4.4's example (`agendado: { opportunity_id: integer, starts_at: datetime }`)
puts fields at the top level of the exit, so adding `kind`/`target`/`stage` there would make those
three words unusable as field names and make a typo'd reserved key indistinguishable from a field.
Nesting fields under `fields:` removes the ambiguity. Type tokens follow design.md's example
(`integer`, `datetime`, `string`) and JSON Schema's vocabulary, which is what the tool declaration
sends to the provider (§6).

**Loader/Validator split** (mirrors `when_state`): `Playbook::Loader#normalize_exits` turns each
entry into a `Custom::ScoutV2::Playbook::ExitDeclaration` value and records **shape** problems on
`load_errors` (entry not a mapping, `fields` not a mapping, unknown key in an exit entry).
`Playbook::Validator` checks **semantics** (FR-006): unknown kind; transition without target /
unknown target / self target / situational target; target on a non-transition exit; unsupported
field type; field name outside `NAME_PATTERN`; unsupported stage role; an exit named `handoff`; a
situational playbook (`when_state` empty) declaring any exit. `validate_exit_tokens` skips
`exit_handoff`. All go into the same one-pass `violations` list, so the existing boot hook
(`config/initializers/scout_v2_playbooks.rb`) fails startup with every problem at once (SC-007).

The unknown-key loader error prevents a silently dropped stage move from a hand-written
`stage_role:` instead of `stage:`. It is listed in FR-006 together with the other shape checks;
failing loudly at boot matches the repo rule for misconfiguration ("let it fail loudly").

**Alternatives considered**: flat shape with reserved keys — rejected above; a separate
`exits.yml` — rejected, the spec keeps exits "part of a playbook file".

**Cutover**: `playbook/loader_spec.rb`'s flat-shape example and every `exits:` Hash literal in
`validator_spec.rb`/`open_playbook_spec.rb` move to the new shape / `ExitDeclaration` values. The
shipped `custom/playbooks/qualificacao.md` declares no exits and is unchanged (which playbooks
declare exits is Brief 06).

## §4 — One per-turn object: `Custom::ScoutV2::TurnScope`

**Decision**: replace `Tools::OpenPlaybook::TurnSetup` (Brief 11's `Data`) with a small mutable
per-turn class `Custom::ScoutV2::TurnScope` (`custom/app/services/custom/scout_v2/turn_scope.rb`)
that owns:

- the live `chat`, the turn's `catalog`, `baseline_instructions`, the `playground` flag;
- the **baseline** (always-on) tool instances: `search_knowledge_base`, `exit_handoff`, and
  `open_playbook` when the openable set is non-empty;
- tool registration: `#add_baseline(tool)`, `#register(tools)`, `#replace_with_baseline!(tools)`
  (instructions → baseline; tools → baseline + given, `replace: true`), and
  `#actions_for(playbook, scout:, conversation:)` (the playbook's registry tools + one exit tool per
  declared exit);
- the turn's outcome state: `ended?`, `escalated?`, `transitions` and the mutators the exit
  effects call;
- `procedure_in_turn?` — true once a procedure is pinned at turn start, opened mid-turn, or made a
  transition target. `OpenPlaybook`'s procedure path returns `{ error: PROCEDURE_IN_EFFECT_ERROR }`
  and changes nothing while it is true (FR-007: one procedure per turn), so at most one procedure's
  exits are ever offered and two playbooks' `exit_<name>` tools cannot collide. Pinned turns already
  get this from `OpenableSet` (procedures are not openable); the flag extends the same rule to a
  procedure opened mid-turn with nothing pinned, which Brief 04 left additive. `PROCEDURE_IN_EFFECT_ERROR`
  = `Já existe um procedimento em andamento neste turno: <nome>. Siga esse procedimento; a troca de procedimento só acontece por um exit de transição.`
  Alternative considered: a second open replaces the first procedure's tools/exits — rejected, it
  re-pins silently mid-turn and drops a takeover's tools, a larger change to Brief 04/11 behavior.

Every tool it registers goes through one wrapper: a **turn-ended guard** (returns
`{ error: TURN_ENDED_ERROR }` without running the tool once a terminal/escalation exit succeeded,
FR-015) *inside* `CallRecorder#wrap_tool` (so the rejected call is still recorded, FR-024).

**Rationale**:
- Exits need shared turn state (a turn-ending outcome, whether it was an escalation, the per-turn
  transition count for `ScoutConversationState#record_transition!(turn_transition_count:)`), and a
  transition needs exactly the takeover mechanics Brief 11 gave `open_playbook`. One owner avoids
  a second copy of "baseline + replace" inside the exit code.
- The baseline must contain `open_playbook` and `exit_handoff`, and both need the per-turn object —
  a frozen `Data` built before them cannot list them (085 worked around this by re-adding `self` in
  `OpenPlaybook#takeover!`). A mutable scope that tools are added to after construction removes the
  workaround.
- `Metrics/ParameterLists` (`Max: 5`, keywords counted): `TurnScope.new(chat:, catalog:,
  baseline_instructions:, tool_wrapper:, playground:)` is 5; `OpenPlaybook.new(scout, conversation,
  openable:, scope:)` is 4; `Exits::ExitTool.new(scout, conversation, declaration:, scope:)` is 4.
- `Metrics/ClassLength` (`Max: 175`): `TurnRunner` is at 164 code lines today. Moving tool assembly
  into `TurnScope` is what leaves room for the final-reply/fail-safe logic (§11) in `TurnRunner`.

**Alternatives considered**: keeping `TurnSetup` and mutating its (unfrozen) baseline Array after
construction — works, but hides mutation behind a value type; module-level turn state in
`Thread.current` — rejected, invisible coupling.

## §5 — Exit tools: one class, built-in `exit_handoff` is a declaration constant

**Decision**: `Custom::ScoutV2::Exits::ExitTool < Custom::Scout::Tools::BaseTool` is the only exit
tool class. Instance methods `name` (`"exit_#{declaration.name}"`), `description` (per kind, see
contract) and `params_schema` (§6) come from its `ExitDeclaration`. `execute(**payload)`:

1. `Exits::PayloadValidator.call(declaration, payload)` → list of problems; any → `{ error: }`,
   no effect (FR-008).
2. Dispatch by kind to `Exits::Terminal`, `Exits::Transition` or `Exits::Escalation`, each a small
   class with `.call(exit_tool, payload)` returning the result text or `{ error: }`.

The built-in exit is `Custom::ScoutV2::Playbook::ExitDeclaration::HANDOFF` =
`name: 'handoff', kind: 'escalation', fields: { 'reason' => 'string' }` — so `exit_handoff` is just
`ExitTool.new(..., declaration: HANDOFF, ...)`, registered as baseline by `TurnRunner`. Its
`last_exit` is `handoff` (clarification Q1) because the declaration name is `handoff`; its note
carries the reason alone (the only branch that looks at `declaration.equal?(HANDOFF)`).

**Rationale**: brief 05 §5 names "handler + one class per kind"; the per-kind classes are where
the effects differ, while name/schema/validation are identical for all kinds, built-in included.
FR-004 (non-empty reason) falls out of the generic string rule (§7).

## §6 — Tool declaration sent to the provider

**Decision**: `ExitTool#params_schema` returns
`{ type: 'object', properties: { field => { type:, [format: 'date-time'] } }, required: [all fields] }`
built from the declaration, and `nil` when the exit declares no fields (so no `parameters` key is
sent — §1). Type map: `string → string`, `integer → integer`, `number → number`,
`boolean → boolean`, `datetime → string + format: date-time`.

**Rationale**: the model needs the field list to call the exit correctly the first time; the
provider schema is advisory, the Ruby check (§7) is the authority. Omitting parameters for a
field-less exit avoids sending an OBJECT with empty `properties`.

## §7 — Payload validation rules (FR-008, FR-004)

**Decision**: `Exits::PayloadValidator.call(declaration, payload)` returns *every* problem:

- each declared field missing → "campo ausente";
- each key not declared → "campo não declarado";
- type mismatch → "deve ser <type>": `string` → non-blank `String`; `integer` → `Integer`;
  `number` → `Integer` or `Float`; `boolean` → `true`/`false`; `datetime` → non-blank `String`
  accepted by `Time.iso8601` (verified in-container: `2026-10-01T10:00:00` and
  `2026-10-01T10:00:00-03:00` parse, `2026-10-01` and free text raise `ArgumentError`).
- `nil` is never a valid value.

Error result: `{ error: "Dados inválidos para exit_<name>: <problem>; <problem>. Corrija e chame o exit novamente." }`.

**Rationale**: "Accept only the documented type, shape, and value. Do not add compatibility
coercions" (AGENTS.md) — no string→integer coercion. Blank strings are rejected for every string
field, not only the built-in `reason`: a declared field exists to carry data, and FR-004 is the
same rule applied to the built-in.

## §8 — Stage move reuses `OpportunityStageTransitionService`

**Decision**: `Exits::StageMove` (used by all three kinds when `declaration.stage` is set):

1. no `conversation.active_opportunity` → error "a conversa não tem oportunidade";
2. `scout.qualified_stage_id` / `scout.unqualified_stage_id` for the role is `nil` → error naming
   the unconfigured role;
3. otherwise `Custom::Scout::OpportunityStageTransitionService#call(stage_id:)`, which already
   applies the scout's qualification requirements for the qualified stage and the model's
   forward-move stage requirements (`Custom::Concerns::OpportunityValidations`), and names the
   missing fields on failure.

`OpportunityStageTransitionService` gains one **additive** reader, `moved?` (true after its
`@opportunity.save` succeeds), so v2 can tell success from failure without parsing the returned
text. On failure, v2 returns the service's text as the exit error (it names the missing fields,
FR-014). On success, v2 **discards** the service's text (for the qualified stage it ends with
`NO_QUESTION_CLOSING_INSTRUCTION`, which FR-013 forbids outside an escalation result) and ignores
`handoff_needed` (FR-014: a stage move never transfers).

**Rationale**: the spec's assumption "stage-change rules are reused as effects"; re-implementing
the qualification check and `resolve_missing_stage_items` would be a second copy of the same
rules. `conversation.active_opportunity` is the opportunity `RoutingSnapshot::Builder` already uses
for `pending_fields`, so the exit checks the same record the model was told about.
v1 is untouched: nothing in v1 reads `moved?` (FR-025).

**Alternatives considered**: matching the service's success string — brittle; editing the
service to not append the instruction — changes v1 (FR-025).

## §9 — Escalation effect: all-or-nothing under a row lock, reusing `HandoffService`

**Decision**: `Exits::Escalation` on the inbox:

```text
conversation.with_lock do                    # BEGIN; SELECT … FOR UPDATE; reload
  refuse unless conversation.pending?        # FR-022 care check, after data validation
  stage error = StageMove (if declared)      # FR-014 checks, then the stage write
  raise ActiveRecord::Rollback if error
  HandoffService#transfer!(reason: note_reason)  # team, bot_handoff!, transfer note
  ScoutConversationState#record_terminal_exit!(declaration.name)
end
```

then `scope.end_turn!(escalated: true)` and the result text containing `CLOSING_INSTRUCTION` once.
No `return` inside the transaction block (non-local exits from `transaction` are not a portable
commit/rollback signal); failures raise `ActiveRecord::Rollback` or are decided before any write.

`Custom::Scout::HandoffService` gains one **additive** public method:

```ruby
def transfer!(reason:)   # caller confirmed `pending` under a row lock; caller delivers the customer message
  @action_reason = reason
  assign_team_and_user(nil, nil)
  @conversation.bot_handoff!
  create_transfer_note(reason)
end
```

**Rationale**:
- `HandoffService#perform` cannot be used as-is: it saves the team **before** its pending check
  (FR-022 requires team unchanged on refusal), always posts a public handoff message (FR-012: the
  final reply is the only customer message), and runs `ContactNotesService`, which makes a second
  `llm_chat` call (FR-019) — inside what would now be a row-locked transaction. Changing
  `perform`'s ordering would change v1 (FR-025), and adding kwargs to `perform` would take it to 6
  parameters (`Metrics/ParameterLists` `Max: 5`).
- `transfer!` reuses the team resolution (`scout.handover_team_id` — "the scout's configured
  transfer settings"), `bot_handoff!`, and the note format with `opportunity_reference`
  ("with the conversation's opportunity reference, as today").
- The row lock makes FR-022's "changed hands at that moment" impossible rather than detected: once
  the lock is held and the status read is `pending`, no other writer can change the conversation
  until commit; any concurrent agent action waits and then applies on top. If the status is not
  `pending`, nothing has been written, and the stage write happens only after the care check, so
  "undo a stage move already applied" reduces to the transaction rollback when `transfer!` itself
  raises.
- Transfer note reason: built-in → the supplied `reason`; declared → `"<exit name> (<field>: <value>; …)"`
  in declaration order (just `<exit name>` with no fields). `HandoffService#reason_label_and_prefix`
  renders an unknown reason as `📋 Transferência para atendimento humano: <reason>`, then appends
  ` | Oportunidade #<id> - <title>` when an opportunity is linked.
- Contact-memory generation is **not** run on a v2 escalation: it is a second model call (FR-019)
  and v2 memory is Brief 08's typed memory.

**Playground (FR-023)**: the sandbox conversation is `open` by construction
(`PlaygroundConversation#find_or_create_conversation` calls `open!`), so the care check and
`transfer!` are skipped there; the stage move (if any) and `record_terminal_exit!` run in one
transaction, the result text is identical, and the call is in `tool_calls` like any exit.

**Refusal** (not pending) → `{ error: 'A transferência não aconteceu e o estágio não foi alterado: a conversa não está mais aos cuidados do assistente.' }`;
turn not ended; recorded like any failed exit.

## §10 — Terminal and transition effects

**Terminal**: `ActiveRecord::Base.transaction { stage move (if declared, Rollback on error); state.record_terminal_exit!(name) }`,
then `scope.end_turn!`; result `TERMINAL_RESULT` (tells the model the outcome was recorded and to
write its final reply — FR-010). Data goes only to the record of actions (FR-009).

**Transition**:
1. `scope.transitions >= 2` → `state.record_transition!(target, turn_transition_count: scope.transitions)`
   (which only sets `handoff_limit_reached_at` and returns `false`), result
   `{ error: TRANSITION_LIMIT_ERROR }` telling the model the transition did not happen and to reply
   now (FR-011). Checked **before** any stage move so the refusal changes nothing else.
2. otherwise transaction { stage move (Rollback on error); `record_transition!` → `true` },
   `scope.count_transition!`, then `scope.replace_with_baseline!(scope.actions_for(target, …))`
   and return `target.body` — the target's full content (FR-011); source guidance/tools/exits are
   gone from the next step, the baseline (with `exit_handoff`) stays (FR-003).

`scope.transitions` starts at 0 each turn — matching `TurnRunner`'s existing
`turn_transition_count: 0` for the routing snapshot.

## §11 — Final reply, empty reply and the fail-safe (FR-012, FR-020, FR-021)

**Decision**: v2 keeps the plain-text final output decided in 083 (research D9: no `with_schema`).
FR-020 is therefore already met — the final output *is* the customer message; there is no
`reasoning` field to remove and no `scout_v2/response_schema.rb` to create. "A final output that
cannot be read" on v2 means `response&.content` is not a `String` or is blank after `strip`.

`TurnRunner` after `chat.ask`:

| Final output | Escalation succeeded this turn | Inbox | Playground |
|---|---|---|---|
| readable | any | `{ reply: content }` → `ProcessMessageJob` posts it (unchanged) | `{ reply: content }` |
| empty/unreadable | yes | `{ reply: I18n.t('conversations.scout.handoff', locale:) }` → job posts it; no second transfer, no alert note | same reply shown |
| empty/unreadable | no | fail-safe: `HandoffService#perform(message: nil, reason: UNREADABLE_REPLY_REASON)`, `{ reply: '' }` (job posts nothing) | `{ reply: 'Erro ao executar simulação: …', error:, tool_calls: }`, nothing transferred |

The fail-safe is the **existing v2 infra fail-safe** (`TurnRunner#handle_infra_failure`, 083 D10),
generalized to take a reason and used for quota/API key (unchanged) and for an unreadable output.
It posts the standard localized handoff message, transfers (team + `bot_handoff!`), and writes the
internal note `📋 Transferência para atendimento humano: <reason>` — the "internal alert note". It
never touches `ScoutConversationState`, so a terminal/transition outcome recorded earlier in the
turn stands (FR-021). Its existing contact-memory generation is part of that unchanged fail-safe:
when the scout has memory enabled it is one more model request, which the spec's Terminology
excludes from "top-level" (FR-019); US4-AS9 pins that with `feature_memory: true`.

Locale for the standard message: `conversation.language.presence || account.locale.presence ||
I18n.default_locale` — the same resolution `HandoffService`/`AgentRunner` use.

**Rationale**: `ProcessMessageJob#dispatch_scout_v2` already posts `result[:reply]` whenever it is
non-blank and never re-checks `pending`, so the escalation turn's final reply (or the standard
message) arrives after the transfer as the turn's single customer message with **no job change**.

## §12 — v2 tool catalog (FR-018)

**Decision**:
- `Tools::Registry::TOOL_CLASSES` = `manage_opportunity → Custom::ScoutV2::Tools::ManageOpportunity`,
  `update_contact → Custom::Scout::Tools::UpdateContact`. `move_opportunity_stage`,
  `handover_to_human`, `call_custom_api` are not in the registry, so they can never be offered and
  a playbook declaring them fails boot (`Validator#validate_tools`, "Unregistered tool").
- New `Custom::ScoutV2::Tools::ManageOpportunity < Custom::Scout::Tools::ManageOpportunity`:
  redeclares `description` and every `param` **except `stage_id`** (§1: class-level params are not
  inherited); `execute` rejects a supplied `stage_id` with `{ error: }`, else `super`; overrides the
  private `already_qualified_update_message` to keep the requalification note but drop
  `@handoff_needed = true` and `NO_QUESTION_CLOSING_INSTRUCTION`.

**Rationale**: the v1 `manage_opportunity` accepts `stage_id` and routes it through
`OpportunityStageTransitionService` — a stage-change path (FR-018, US3: "changing the stage happens
only as part of an exit") — and appends the transfer-closing instruction both on a qualified stage
move and on any data update to an already-qualified opportunity (FR-013/SC-003: that instruction
belongs only in a successful escalation result). In v2 today nothing reads `handoff_needed`, so the
model is told a transfer will happen that never does. The subclass keeps v1's class byte-identical
(FR-025) and keeps the name `manage_opportunity`, so playbooks and `chat.tools[:manage_opportunity]`
checks are unaffected. The override couples to one private method of the parent; that is the price
of not editing v1, and it is covered by the v2 request spec.
`UpdateContact` has no stage or handoff path and is registered as is.

**Consequence (accepted, spec Assumptions)**: until Brief 06 adds exits to `qualificacao.md`, a v2
turn cannot move an opportunity's stage at all.

## §13 — Record of actions for exits no longer available (FR-024)

**Decision**: `TurnRunner` registers `chat.before_tool_call { |call| ... }` that appends
`{ tool_name:, arguments:, result: { error: … } }` to `recorded_tool_calls` when `call.name` is not
in `chat.tools` at that moment (RubyLLM will return its own unavailable-tool error, §1).

**Rationale**: after a transition in the middle of a step, a later call to a source exit is an
"exit attempt" that RubyLLM rejects without ever reaching a wrapped tool, so `CallRecorder` never
sees it. Four lines close that gap; without them FR-024 would hold only for available exits.

## §14 — Escalation section and the closing instruction (FR-001, FR-002, FR-013)

**Decision**: `Custom::ScoutV2::Instructions::Escalation::SECTION`, a Portuguese block headed
`[Escalation]`, appended by `TurnRunner#build_instructions` right after the Playbook Index and
before the pinned body — so it is also in `baseline_instructions` (takeover/transition keep it).
Content is derived from v1's "Fallback para humano" and "Reconhecimento de intenção fora de
prospecção" bullets (`system_prompts_service.rb` `guardrails_section`), with the tool name moved to
`exit_handoff` and the closing-message sentence removed. Exact text:
[contracts/turn_assembly.md](./contracts/turn_assembly.md).

`Custom::ScoutV2::Exits::Escalation::CLOSING_INSTRUCTION` is the only place the closing rule
exists on the v2 path; it appears once in a successful escalation result and nowhere else. Tests
count occurrences of that constant (SC-003).

## §15 — What is *not* built

- No v2 `ResponseSchema` (§11). No changes to `ResponseAuditor`, `ActionClassifierService`,
  `ClaimConsistencyService`, `AgentRunner`, `SystemPromptsService`, `MoveOpportunityStage`,
  `HandoverToHuman`, `CallCustomApi` (FR-025; physical removal is Brief 10).
- No `ProcessMessageJob` change (§11).
- No migration: `ScoutConversationState` already has `last_exit`, `transition_count`,
  `handoff_limit_reached_at` and the `transition` reason (Brief 02).
- No retry cap on invalid exits (spec Assumptions). No `exit_action` trace metadata (design §4.9
  mentions it; no FR requires it).
- `ReferralInterestClassifierService` inside `manage_opportunity`'s create path is a nested tool
  call, not a turn-level call nor a reply-audit component; it is left as is.

## §16 — Test strategy against the constitution (Principles VI, VII, IX)

- **External boundary only**: the Gemini `generateContent` HTTP endpoint, stubbed with WebMock
  (`stub_request … .to_return(*responses)`), as in 085's real-engine context. FR-022's
  "human took over mid-turn" is simulated **at that boundary**: a `to_return` block updates the
  conversation to `open` before returning the function-call response that invokes the exit.
- **Real entry points**: playground → `POST /api/v1/accounts/:id/scouts/:scout_id/playground_messages`
  (new context in `playground_messages_controller_spec.rb`); inbox →
  `described_class.new.perform(conversation.id)` (the existing job-spec convention; new v2 context in
  `custom/spec/jobs/custom/scout/process_message_job_spec.rb`) — real `TurnRunner`, `RubyLLM::Chat`,
  `HandoffService`, `OpportunityStageTransitionService`, `ScoutConversationState`.
- **Observables**: HTTP `reply`/`tool_calls`; persisted conversation status/team/assignee,
  messages (public count and content, private notes), opportunity stage, every
  `ScoutConversationState` column; outgoing provider request bodies (system text, offered
  `functionDeclarations[].name`, tool-result parts); number of provider requests (one `chat.ask`
  ⇒ one request per step, all sharing one growing transcript; an auditor would add requests with a
  different system text — SC-001/FR-019, asserted with `feature_response_auditor: true`).
- **Unit**: `PayloadValidator` (pure), `Loader`/`Validator` (fixture files / values),
  `ExitTool`/`OpenPlaybook` with a real `scout.llm_chat` (offline until `ask`).
- **Cutovers** (contract changes, not new behavior): baseline tool lists gain `exit_handoff`;
  instruction headers gain `Escalation`; `open_playbook_spec`'s `TurnSetup` fixture moves to
  `TurnScope`; `turn_runner_spec`'s shared `fake_chat` double allows `before_tool_call` (its
  pre-existing `RubyLLM::Chat` doubling is not extended and is not used as proof of new behavior).
- **Regression (FR-025)**: v1 specs run unchanged — `agent_runner_spec`, `handoff_service_spec`,
  `opportunity_stage_transition_service_spec`, `tools/manage_opportunity_spec`,
  `tools/move_opportunity_stage_spec`, `tools/handover_to_human_spec`, `response_auditor_spec`.
