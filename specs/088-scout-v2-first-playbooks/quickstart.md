# Quickstart: validating the first-cut playbooks and degradation

Run everything inside the containers (AGENTS.md). Stack up first: `docker compose up -d`.

```bash
RSPEC="docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec"
```

Contracts: [playbook_catalog.md](./contracts/playbook_catalog.md),
[state_conditions.md](./contracts/state_conditions.md), [turn_assembly.md](./contracts/turn_assembly.md).
Data rules: [data-model.md](./data-model.md). Decisions: [research.md](./research.md).

## 0. Migration

```bash
docker compose exec rails bundle exec rails db:migrate
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rails db:migrate
```

Expected `db/schema.rb` diff: one line, `t.jsonb "completed_playbooks", default: [], null: false`
in `ichatr_scout_conversation_states`, and the schema version. Anything else (e.g. `n8n` objects) means
the dev DB is contaminated — clean it, do not commit (AGENTS.md; `spec/config/schema_spec.rb`).

## 1. Targeted specs (Principle IX)

```bash
$RSPEC \
  custom/spec/models/scout_conversation_state_spec.rb \
  custom/spec/services/custom/scout_v2/predicates/ \
  custom/spec/services/custom/scout_v2/routing_snapshot_spec.rb \
  custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb \
  custom/spec/services/custom/scout_v2/router_spec.rb \
  custom/spec/services/custom/scout_v2/playbook/ \
  custom/spec/services/custom/scout_v2/turn_scope_spec.rb \
  custom/spec/services/custom/scout_v2/unsatisfied_items_spec.rb \
  custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb \
  custom/spec/services/custom/scout_v2/exits/ \
  custom/spec/services/custom/scout_v2/turn_runner_spec.rb \
  custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb \
  custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb \
  custom/spec/jobs/custom/scout/process_message_job_spec.rb \
  spec/config/scout_v2_playbooks_spec.rb \
  --format progress
```

Expected: green. Acceptance proof = the playground request spec on the **shipped** catalog and the
inbox job spec; the only doubles are WebMock on Gemini `generateContent` and, in the trace context, on
the Langfuse OTLP endpoint. "Key phrases" = the literal strings in contracts/playbook_catalog.md
"Asserted key phrases".

| Scenario | Entry point | Observable result |
|---|---|---|
| US1-AS1/AS13, FR-006 | playground (sandbox contact renamed to a placeholder / given a phone) | state `active_playbook`/`activation_reason`; `identificacao` only while name is placeholder or phone blank |
| US1-AS2/AS8, SC-002 | playground | request `functionDeclarations`: `update_contact`+`exit_identificado` (no `manage_opportunity`) vs `manage_opportunity`+`exit_qualificado`+`exit_desqualificado` (no `update_contact`) |
| US1-AS3/AS5, FR-010, SC-001 | playground | system text of the `identificacao` turn: every `identificacao` key phrase, none of its "must not" strings, + "dados de contato faltando" block naming `nome` then `telefone`; scripted `exit_identificado` with the phone still blank succeeds (state `qualificacao`/`transition`) |
| US1-AS4, AS6, SC-001, FR-029 | playground, scripted `update_contact` then `exit_identificado` | contact name/phone updated; the `exit_identificado` result carries `qualificacao`'s body + pending-fields block; state `qualificacao`/`transition`; the sandbox row's `completed_playbooks == ['identificacao']` (FR-029: same column and rule as the inbox); next step offers qualificacao's actions; later turns (phone still blank) keep `qualificacao` pinned |
| US1-AS7 | inbox job: `identificacao` completed on conversation A, then a new conversation B for the same (still incomplete) contact | B's first turn pins `identificacao` by state; B's row `completed_playbooks == []`, A's unchanged |
| US1-AS9, AS14, US3-AS2, SC-006, FR-011a | playground, `exit_qualificado` then `exit_handoff` | stage = qualified; the `exit_qualificado` result carries `agendamento`'s rendered content with `chame exit_handoff neste mesmo turno` and the five `PENDENTE` lines; state row after the turn: procedure cleared, `last_exit 'handoff'`, `completed_playbooks` ⊇ `qualificacao`, `agendamento` (and `identificacao` in AS14, `transition_count 2`); step after `exit_qualificado` shows `PENDENTE` markers, no `exit_agendado`/`exit_sem_horario` |
| US1-AS10, FR-011a | playground, `exit_qualificado` with a required field blank | tool result names the field; stage unchanged; state `qualificacao` pinned; `completed_playbooks` unchanged |
| US1-AS11 | playground, `exit_desqualificado(motivo:)` | stage = unqualified; `last_exit 'desqualificado'`; `completed_playbooks` ∋ `qualificacao` |
| US1-AS12 | inbox job, `exit_handoff` with `qualificacao` pinned | transferred (087 effects); `completed_playbooks` ∋ `qualificacao` |
| FR-026(b) declared escalation | inbox job, 087 example 'verifies US2-AS6 and US1-AS7: declared escalation transfers…' (`fluxo_teste` pinned, declared escalation `qualificado`) | transferred; `completed_playbooks == ['fluxo_teste']` |
| Edge: escalation with nothing in effect | inbox job, nothing pinned, no opening, `exit_handoff` | transferred; `completed_playbooks == []` |
| US1-AS15/AS16/AS17, FR-011, FR-011b, SC-009 | playground, real-name contact with phone, no opportunity | `qualificacao` by state on turn 1; pending block lists the scout requirements; system text has every `qualificacao` key phrase and none of its "must not" strings; scripted `manage_opportunity create` creates the opportunity; a turn without `manage_opportunity` leaves the conversation with no opportunity |
| US1-AS18, FR-028a | playground, after `exit_desqualificado` | next turn: nothing pinned by state (opportunity still open in unqualified stage with pending fields) |
| FR-028c re-opening | playground, real-name contact with phone, open opportunity with a pending field, `completed_playbooks == ['qualificacao']` | nothing pinned by state; scripted `open_playbook('qualificacao')` → result = body + pending-fields block; state `qualificacao`/`trigger` |
| Edge: complete opportunity, nothing pinned | playground, real-name contact with phone, active opportunity open in the initial stage with every required field filled, no state row | nothing pinned by state; the `[Playbook Index]` `qualificacao` line contains `ainda não confirmados`; scripted `open_playbook('qualificacao')` pins it with reason `trigger` and the next step offers `manage_opportunity` + its exits |
| Edge: preemption adds nothing | playground, `qualificacao` pinned, real-name contact whose phone is then removed, `identificacao` not completed | next turn pins `identificacao` by state; `completed_playbooks == []` |
| US2-AS1, FR-012 | inbox job, `identificacao` or `qualificacao` pinned (US2); `agendamento` pinned (US3): `open_playbook('fora_de_prospeccao')` then `exit_handoff` | step after opening offers only baseline; opening result has every `fora_de_prospeccao` key phrase; transferred; `completed_playbooks` ∋ the pinned procedure; `agendamento` variant: no `PENDENTE` in the request after the opening |
| US2-AS2/AS3/AS5, FR-013, SC-003 | playground, `open_playbook('duvida_comercial')` mid-qualification, then next turn | opening step: `search_knowledge_base` offered, no data tool; returned content has every `duvida_comercial` key phrase; `tool_calls` shows the opening; state unchanged (`qualificacao`, same reason, same `completed_playbooks`); next turn system text has the same pending block |
| US2-AS4, FR-014, SC-003 | playground, `open_playbook('pausa')` with `qualificacao` pinned, then next turn; and `open_playbook('pausa')` with nothing pinned | no data tool offered; no state change (`completed_playbooks` included); returned content has every `pausa` key phrase; next turn: `qualificacao` still pinned, same reason, same pending block; nothing-pinned variant: no `active_playbook` after the turn |
| US2-AS6, SC-004 | playground (representative: placeholder contact without phone; real-name contact with phone, no opportunity; qualified opportunity with phone and every procedure completed) + `router_spec` (shipped catalog, exhaustive) | playground: the state row never holds a situational `active_playbook`; router: the example first asserts the three situational names are in the shipped catalog (so it cannot pass vacuously), then the exhaustive product of identity × phone × opportunity (none / open-pending / open-complete / each role) × completed subsets → no situational winner |
| US2-AS7, FR-005 | playground request (`[Playbook Index]` text) + `playbook/catalog_spec` (shipped) | the index lines for `duvida_comercial` and `fora_de_prospeccao` each name the other as excluded |
| US3-AS1/AS3 | playground | `agendamento` by state only with qualified stage + phone + not completed |
| US3-AS4/AS5/AS6/AS7, SC-005 | playground with `agendamento` pinned | system text: every `agendamento` key phrase, exactly five marker lines `PENDENTE — indisponível: …` + notice, none of its "must not" strings; no `exit_agendado`/`exit_sem_horario` offered and no scheduling tool (only baseline + `exit_handoff`); `unsatisfied_flags == {procedure: 'agendamento', pending_fields: [], unmet_requires: [scheduling, customer_registry], unmet_needs: [politica_reagendamento]}` |
| US3-AS6 trace, US3-AS8 trace, removed `turn_runner_spec` trace examples | playground trace context (real SDK, in-memory exporter) | `agendamento` pinned: finished agent-session span `langfuse.trace.metadata.unsatisfied_flags` == persisted record with the three items; `qualificado → exit_handoff`: record names `agendamento` while `…metadata.playbook == 'qualificacao'`, `…activation_reason == 'state'`; trigger-stored procedure: `activation_reason == 'trigger'`; no LLM-call span carries `…metadata.unsatisfied_flags`; both `llm.scout_v2.turn_runner` spans (agent session + child LLM call) carry `langfuse.user.id`, `langfuse.session.id` (`<account_id>_<conversation_id>`), `langfuse.trace.tags == ['scout_v2_turn_runner']`, `langfuse.observation.metadata.feature_name`, `…metadata.scout_id`/`playbook`/`activation_reason`; LLM-call span `gen_ai.request.model` |
| FR-019 (design property) | `content_builder_spec`, `turn_scope_spec`, `unsatisfied_items_spec` with satisfied lists | no `PENDENTE`, marker stripped; exits offered; record lists empty — same shipped file |
| US3-AS8 | inbox job, `qualificacao` pinned, `exit_qualificado` + `exit_handoff` | record attributes the three items to `agendamento`; procedure cleared; `last_exit 'handoff'` |
| US3-AS9, SC-010 | inbox job: escalate with `agendamento` in effect, set conversation back to `pending`, customer "obrigado" | second turn: nothing pinned, status stays `pending`, no new transfer note |
| Edge: fail-safe adds nothing | inbox job, empty final reply with `qualificacao` pinned | fail-safe transfer; `completed_playbooks` unchanged; `unsatisfied_flags` written |
| FR-018: no record before/without a model turn | inbox job: quota exhausted; missing API key; Gemini HTTP error raising from `chat.ask` | `unsatisfied_flags` untouched in all three |
| FR-018 supersedes 085/087 "writes nothing" | the 12 cutover assertions (research §12) in the job and playground specs | every column except `unsatisfied_flags`/`updated_at` unchanged (row-absent cases: only default routing columns); `unsatisfied_flags` == the turn's record |
| FR-009a, FR-020, markers | `validator_spec` | one `ValidationError` listing every new violation message, including both argument-arity rules and a `playbook_not_completed` naming a situational playbook |

## 2. v1 regression (FR-024, SC-008)

```bash
$RSPEC custom/spec/services/custom/scout/ custom/spec/jobs/custom/scout/process_message_job_spec.rb --format progress
git diff --stat "$(git merge-base ichatr-main HEAD)" -- custom/app/services/custom/scout/
```

Expected: green; the diff shows exactly two additive members already reviewed and accepted in Brief
087 — `custom/app/services/custom/scout/handoff_service.rb#transfer!` and
`custom/app/services/custom/scout/opportunity_stage_transition_service.rb#moved?` (insertions only, no
deletion, no other v1 file touched) — and no other v1 file. The diff runs against the merge base with
`ichatr-main`, so it covers committed and uncommitted changes of the feature branch (a bare `git diff`
would only show unstaged edits and pass vacuously after a commit). `custom/app/services/custom/scout/`
holds every v1 file (`AgentRunner`, `SystemPromptsService`, `system_prompts/FunnelSectionBuilder`, v1
tools, including `update_contact.rb`, which v2 reuses unchanged).

## 3. Boot validation of the shipped catalog

```bash
docker compose exec rails bundle exec rails runner 'Custom::ScoutV2::Playbook::Validator.call!(Custom::ScoutV2::Playbook::Loader.load_all); puts :ok'
```

Expected: `ok`. Break a copy (e.g. `needs: [politica_inexistente]`) under `SCOUT_V2_PLAYBOOKS_DIR` → boot raises
`ValidationError` naming the file and `Unknown business fact: politica_inexistente`.

## 4. Manual playground pass (SC-007; model-behavior scenarios, research §10)

Account with `scout`, `scout_v2`, `opportunities` enabled; a scout with default/qualified/unqualified
stages and one qualification requirement. The sandbox conversation persists per scout, so reset it
before each script:

```bash
docker compose exec rails bundle exec rails runner '
  scout = Scout.find(ENV.fetch("SCOUT_ID"))
  conv = Custom::ScoutV2::PlaygroundConversation.for(scout)
  ScoutConversationState.where(conversation_id: conv.id).delete_all
  conv.contact.update!(name: "lindo-peixe-123", phone_number: nil)'
```

1. "Oi" → Langfuse trace `activation_reason=state`, `playbook=identificacao`; reply asks only the name.
2. Give the name, ignore the phone question → `exit_identificado` in the tool list; next turns in `qualificacao` (`activation_reason=transition`), phone never asked again.
3. Ask a price question → `open_playbook duvida_comercial` (trigger); next turn resumes the same pending field.
4. "Vou pensar" → `pausa`; no qualification question.
5. Fill every field and confirm → `exit_qualificado`, then `exit_handoff` in the same turn; `unsatisfied_flags` on the row lists the three items under `agendamento`; no slot offered.
6. Reset, then "Sou cliente, meu pedido atrasou" → `fora_de_prospeccao`, transfer.

## 5. Deliberate-mutant checks (Principle VII)

Each mutation must turn at least one listed spec red:

| Mutation | Must fail |
|---|---|
| `ContactIdentityIncomplete` drops the phone branch | predicate spec; US1-AS1 playground example |
| `PlaybookNotCompleted` returns true always | predicate spec; US1-AS6, US1-AS18, SC-010 |
| `InQualification` drops the no-opportunity branch | predicate spec; US1-AS15 |
| `record_terminal_exit!` ignores `completed:` | model spec; US1-AS11, US1-AS12, SC-010 |
| `record_transition!` adds `completed` on the refused branch | model spec (refusal) |
| Transition passes the target instead of the source | US1-AS4 (`['qualificacao']` ≠ `['identificacao']`) |
| `actions_for` keeps exits when `requires` unsatisfied | US3-AS5 |
| `ContentBuilder` leaves unsatisfied markers raw | `content_builder_spec`; US3-AS4 |
| Unsatisfied record uses the routed playbook | US3-AS8 |
| Record written before `chat.ask` | US3-AS8 (would name `qualificacao`) |
| `PendingFields` returns `[]` without opportunity | builder spec; US1-AS15 |
| `DependencyRules` skips `needs` | validator spec |
| `DependencyRules` skips the argument-arity rules | validator spec (both arity examples) |
| `DependencyRules` accepts a situational playbook for `playbook_not_completed` | validator spec |
| `Exits::Escalation` passes `completed:` only for `exit_handoff` | FR-026(b) declared-escalation job example |
| `open_playbook` (situational) or state preemption appends to `completed_playbooks` | US2-AS2/AS4 playground (list unchanged); preemption edge example |
| `TurnRunner` records a start-of-turn `unsatisfied_flags` again | trace context (LLM-call span carries the key) |
| `UnsatisfiedItems.trace!` skips the span attribute | trace context (US3-AS6 span ≠ persisted record) |
| `TurnRunner#instrumentation_params` drops `conversation_id` or `feature_name` | trace context parity example (session id / tags missing) |
| Content: delete the `chame exit_handoff neste mesmo turno` line from `agendamento.md` | US3-AS4 system-text example; US1-AS9 `exit_qualificado` result |
| Content: delete the `siga no mesmo turno` line from `qualificacao.md` | US1-AS8 system-text example (T064) |
| Content: delete the `nunca retorne uma oportunidade…` line from `qualificacao.md` | US1-AS15 system-text example |
| Content: delete the `não tente resolver` line from `fora_de_prospeccao.md` | US2-AS1 opening-result example |
| Content: add `manage_opportunity` to the `identificacao.md` body | US1-AS3 system-text example ("must not") |
| Content: delete the `urgência clínica` line from `agendamento.md` | US3-AS4 system-text example |
| Content: delete the `diga que não tem essa informação` line from `duvida_comercial.md` | US2-AS2 opening-result example |
| Content: delete the `reconheça brevemente` line from `qualificacao.md` | US1-AS15 system-text example |

## 6. Lint

```bash
docker compose exec rails bundle exec rubocop custom/app/services/custom/scout_v2 custom/app/models/scout_conversation_state.rb \
  custom/spec/services/custom/scout_v2 custom/spec/requests/api/v1/accounts/scouts custom/spec/jobs/custom/scout \
  db/migrate/21260928000000_add_completed_playbooks_to_ichatr_scout_conversation_states.rb
```

Expected: no offenses, no `.rubocop_todo.yml` change.
