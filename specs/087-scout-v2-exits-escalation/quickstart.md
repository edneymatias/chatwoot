# Quickstart: validating Scout V2 exits, escalation and the auditor-free turn

Run everything inside the containers (AGENTS.md). Stack up first: `docker compose up -d`.
All rspec commands use the test-env prefix:

```bash
RSPEC="docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec"
```

Contracts referenced below: [playbook_exit_declaration.md](./contracts/playbook_exit_declaration.md),
[exit_tools.md](./contracts/exit_tools.md), [turn_assembly.md](./contracts/turn_assembly.md).
Data rules: [data-model.md](./data-model.md).

## 1. Targeted specs for this feature (Principle IX)

```bash
$RSPEC \
  custom/spec/services/custom/scout_v2/playbook/loader_spec.rb \
  custom/spec/services/custom/scout_v2/playbook/validator_spec.rb \
  custom/spec/services/custom/scout_v2/exits/ \
  custom/spec/services/custom/scout_v2/tools/ \
  custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb \
  custom/spec/jobs/custom/scout/process_message_job_spec.rb \
  custom/spec/services/custom/scout_v2/turn_runner_spec.rb \
  --format progress
```

Expected: green. The request spec (playground) and job spec (inbox) are the acceptance proof; they
stub only the Gemini `generateContent` HTTP endpoint (WebMock).

| Scenario (spec) | Entry point | Observable result |
|---|---|---|
| US1-AS1/AS5: `[Escalation]` block after `[Playbook Index]`; closing rule absent from system text | playground | request 0 system text headers = `Identity … Playbook Index, Escalation`; `CLOSING_INSTRUCTION` count 0 |
| US1-AS2/AS3: `exit_handoff` offered with nothing pinned, pinned, after takeover, after transition | playground | every provider request's `functionDeclarations` includes `exit_handoff` |
| US1-AS4, SC-002: "quero falar com uma pessoa", nothing pinned | inbox job | status `open`, team = `handover_team`, one private note with the reason, `last_exit == 'handoff'`, exactly one new outgoing message = model's final text |
| US1-AS5/AS6, FR-013 | playground | `CLOSING_INSTRUCTION` exactly once in the escalation tool result; absent from terminal/transition/stage-move results |
| US1-AS7: escalation with procedure pinned | inbox job | `active_playbook/activated_at/activation_reason` nil, `last_exit` = exit name, `transition_count`/`handoff_limit_reached_at` unchanged |
| US1-AS8, FR-022: human takes over mid-turn | inbox job — `to_return` block sets conversation `open` before the exit call | stage, team, assignee, private notes, all `ScoutConversationState` columns identical; result = refused error |
| US1-AS8 other variants: blank `reason` (T015); declared escalation with invalid data (T026); stage checks fail, and takeover with a declared stage move (T037) | inbox job | same identity check on stage, team, assignee, private notes and every state column; tool result = the payload / stage / refusal error |
| US2-AS1: declared exits only while playbook in effect | playground (fixture catalog) | `exit_concluido` etc. present only in requests where the fixture procedure is in effect |
| US2-AS10, FR-007: open a procedure while one is pinned, already opened, or a transition target | playground | `PROCEDURE_IN_EFFECT_ERROR` (or `Playbook desconhecida` when pinned); next request's `functionDeclarations` unchanged; state unchanged |
| US2-AS2/AS3: invalid then corrected payload | playground | first tool result lists every problem; second succeeds; all requests one growing transcript; no customer message in between |
| US2-AS4/AS5/AS6: terminal / transition / escalation outcomes | playground + inbox | state columns per data-model table; transition result = target body and next request offers target's tools/exits only |
| US2-AS6: declared escalation note | inbox job | one private note `📋 Transferência para atendimento humano: <name> (<f1>: <v1>; <f2>: <v2>)` in declaration order + opportunity reference; `last_exit` = declared name |
| US2-AS7: final message after terminal / transition | inbox job | exactly one new outgoing message = model's final text |
| US2-AS8: procedure opened mid-turn, no exit | inbox job | `active_playbook` = opened playbook, `last_exit` unchanged, status `pending`, no note |
| US2-AS9: terminal data not persisted | playground | opportunity/contact attributes unchanged; payload visible in `tool_calls[].arguments` |
| US3-AS1, SC-006: removed tools never offered | playground | no request ever declares `move_opportunity_stage`, `handover_to_human`, `call_custom_api`; `manage_opportunity` declaration has no `stage_id` |
| US3-AS2/AS3: stage exit with missing fields, then filled | playground | error names missing fields, stage unchanged, no `last_exit`; after filling, stage = qualified and outcome recorded |
| US3-AS5: playbook declares `update_contact` and `manage_opportunity` | playground | both in `functionDeclarations` while the fixture procedure is in effect |
| US3-AS4: customer picks an option, no exit | inbox job | status stays `pending`, no note, state unchanged |
| US4-AS1/AS2, SC-001: one top-level call, no auditor, with `feature_response_auditor: true` | inbox job | provider requests = stubbed steps; every request carries the turn's system text |
| US4-AS3, FR-020: plain-text final output | playground + inbox job | `reply` / outgoing message = model text verbatim; no provider request sets a response schema or JSON response type |
| US4-AS4/AS7: empty reply with no exit / after terminal / after transition | inbox job | standard handoff message only, transfer, one alert note; routing outcome kept |
| US4-AS5: quota exhausted / no API key on a v2 account | inbox job | zero provider requests; standard handoff message, transfer, note (unchanged behavior) |
| US4-AS8: empty reply after escalation | inbox job | exactly one outgoing message (standard handoff message), one transfer note, no alert note |
| US4-AS9, FR-019 "top-level": `feature_memory: true`, empty reply, no exit | inbox job | the turn's requests + exactly one contact-memory request (system text not the turn's); fail-safe ran; no other request |
| Edge: FR-015 call after turn-ending exit; FR-016 same-step order; 3rd transition | playground | `TURN_ENDED_ERROR`; order kept; `TRANSITION_LIMIT_ERROR` + `handoff_limit_reached_at` set |
| FR-023 playground escalation | playground | `last_exit == 'handoff'`, sandbox status unchanged (`open`), no team, no note, tool call listed |
| SC-007 boot rejection | validator spec | one `ValidationError` listing every malformed-exit violation |

## 2. v1 regression (FR-025, SC-008)

```bash
$RSPEC \
  custom/spec/services/custom/scout/agent_runner_spec.rb \
  custom/spec/services/custom/scout/response_auditor_spec.rb \
  custom/spec/services/custom/scout/handoff_service_spec.rb \
  custom/spec/services/custom/scout/opportunity_stage_transition_service_spec.rb \
  custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb \
  custom/spec/services/custom/scout/tools/move_opportunity_stage_spec.rb \
  custom/spec/services/custom/scout/tools/handover_to_human_spec.rb \
  --format progress
```

Expected: green with **no edits** to these files.

## 3. Boot validation

```bash
docker compose exec rails bundle exec rails runner 'puts Custom::ScoutV2::Playbook::Validator.call!(Custom::ScoutV2::Playbook::Loader.load_all).playbooks.map(&:name)'
```

Expected: prints `qualificacao` (shipped catalog still valid). Pointing `SCOUT_V2_PLAYBOOKS_DIR` at a
directory with a malformed exit (e.g. `kind: finish`, `exits: { handoff: … }`) must raise
`Custom::ScoutV2::Playbook::Validator::ValidationError` listing every problem.

## 4. Manual playground check (design §6 preflight path)

1. Enable `scout_v2` for a dev account (Super Admin → Accounts → Features) and make sure the
   account has a `ScoutAccountConfig` with a working key.
2. Open the scout's playground, send `Quero falar com uma pessoa, por favor.` on a fresh sandbox.
3. Expect: one reply (a closing message with no question); the action list shows `exit_handoff`
   with a `reason` and a text result; `ScoutConversationState` for the sandbox conversation has
   `last_exit = 'handoff'`; the sandbox conversation is still `open` with no team.

## 5. Deliberate-mutant checks (Principle VII — no mutation tooling in the repo)

Apply each mutant locally, run the named spec, confirm it **fails**, revert.

| Mutant | Must fail |
|---|---|
| Drop `exit_handoff` from `TurnScope` baseline on takeover/transition | US1-AS3 examples |
| Guard `ended?` never set by escalation | FR-015 example |
| Escalation care check removed (or moved after the stage write) | US1-AS8 / FR-022 example |
| `PayloadValidator` stops at the first problem | US2-AS2 "every problem" example |
| `string` type accepts blank | built-in reason FR-004 example |
| Transition limit `>= 2` → `>= 3` | 3rd-transition example |
| Append `CLOSING_INSTRUCTION` to `TERMINAL_RESULT` | US1-AS6 / SC-003 example |
| Fail-safe runs even when escalated | US4-AS8 example |
| `Validator` accepts situational target | SC-007 validator example |
| v2 `ManageOpportunity` keeps `stage_id` | US3-AS1 example |
| `OpenPlaybook` lets a second procedure open | US2-AS10 example |
| Declared note built from a Hash sorted by key instead of declaration order | US2-AS6 example (fields declared out of alphabetical order) |
| Unreadable check uses `empty?` instead of `strip.empty?` | US4-AS4 whitespace-only example |

## 6. Lint

```bash
docker compose exec rails bundle exec rubocop custom/app/services/custom/scout_v2 custom/app/services/custom/scout/handoff_service.rb custom/app/services/custom/scout/opportunity_stage_transition_service.rb custom/spec/services/custom/scout_v2 custom/spec/requests/api/v1/accounts/scouts custom/spec/jobs/custom/scout
```

Expected: no offenses, no new `.rubocop_todo.yml` entries.
