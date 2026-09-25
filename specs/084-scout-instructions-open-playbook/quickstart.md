# Quickstart: validating Scout V2 Typed Instructions, Playbook Index, and Mid-Turn Playbook Activation

Prerequisites: stack up (`docker compose up -d`), migration applied
(`docker compose exec rails bundle exec rails db:migrate RAILS_ENV=test` and, for manual
verification, the same against `development`).

## 1. Targeted specs (primary proof — run these, not the full suite, per Constitution Principle IX)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout_v2/instructions/ \
  custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb \
  custom/spec/services/custom/scout_v2/playbook/validator_spec.rb \
  custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb \
  custom/spec/services/custom/scout_v2/tools/registry_spec.rb \
  custom/spec/services/custom/scout_v2/turn_runner_spec.rb \
  custom/spec/models/scout_spec.rb \
  custom/spec/models/scout_conversation_state_spec.rb
```

Expected: all green. These exercise, respectively — see `contracts/` and `data-model.md` for the
exact shapes each spec is pinning:

- US1 (Instructions block: exactly 4 typed sections, config changes reflected without prose
  edits, no v1 situational bullets present, Safety declares-but-doesn't-time the knowledge base).
- US2 (index: one line per enabled playbook, new catalog entries picked up without code changes).
- US3 (`open_playbook`: offered only without a state-forced playbook, tools/body/trigger
  activation land within the same turn, unknown name → tool error without failing the turn).

## 2. Playground smoke test (behavioral proof — brief §8's own acceptance check)

1. In a `scout_v2`-flagged development account (`Super Admin → Accounts → scout_v2` checkbox —
   pre-existing flag from Brief 03/`design.md` §4.11, unchanged by this feature), open the Scout
   playground for a scout with at least two catalog playbooks loaded (the shipped `qualificacao`
   plus a second fixture placed under `SCOUT_V2_PLAYBOOKS_DIR` for this check, per the spec's own
   Assumptions — no new playbook ships to `custom/playbooks/` in this feature).
2. Send a message with **no state signature** for either playbook (e.g. a pure pricing question:
   "quanto custa?") on a conversation with no open opportunity.
3. Expected: the reply addresses the question in-character (per `[Identity]`/`[Communication]`),
   and the turn's tool-call trace (visible in the playground's tool-call panel /
   `result[:tool_calls]`) shows an `open_playbook` call whose result body matches the fixture
   playbook's markdown body — all in this one turn, no dead turn waiting for the next customer
   message.
4. Inspect `ScoutConversationState.for_conversation(conversation)`: `active_playbook` equals the
   opened playbook's name, `activation_reason` equals `"trigger"`.
5. Send a follow-up message reachable only via a tool the opened playbook declared: confirm the
   model can call it (proves the tool injected mid-turn is still present on the next turn's
   catalog too, since `decision.playbook` now resolves via continuity).

## 3. Config-change smoke test (SC-002)

```ruby
# docker compose exec rails bundle exec rails console
scout = Scout.find(<id>)
before = Custom::ScoutV2::Instructions::Builder.call(scout: scout)
scout.update!(tone: :humorous, response_length: :thorough, greeting: 'E aí, tudo certo?')
after = Custom::ScoutV2::Instructions::Builder.call(scout: scout)
before == after # => false — only the [Communication] section differs
```

## 4. Regression check — v1 untouched (FR-017)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb
```

Expected: unchanged, all green — no file under `custom/app/services/custom/scout/` (v1 namespace)
is touched by this feature.
