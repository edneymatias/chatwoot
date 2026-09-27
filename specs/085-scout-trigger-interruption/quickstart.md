# Quickstart: validating Scout V2 Trigger-Based Playbook Interruption over an Active Procedure

Prerequisites: stack up (`docker compose up -d`). No migration — this feature adds no schema.

## 1. Targeted specs (primary proof — run these, not the full suite, per Constitution Principle IX)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec --format progress \
  custom/spec/services/custom/scout_v2/playbook/openable_set_spec.rb \
  custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb \
  custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb \
  custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb
```

Expected: all green. See `contracts/` and `data-model.md` for the exact shapes these pin.

- **`openable_set_spec.rb`:** with nothing pinned, the openable set has exactly the catalog's
  members. With something pinned, it is situational-only, including the empty case.
- **`index_builder_spec.rb`:** an empty set renders `EMPTY_INDEX_LINE` ("Nenhum playbook disponível
  para abrir neste turno.").
- **`open_playbook_spec.rb`** (real `RubyLLM::Chat`, no HTTP):
  - Unknown or excluded name → tool error, no side effects (guard).
  - Path A → system message replaced by the baseline; tools become exactly baseline + `open_playbook`
    + the playbook's own; no state write. This covers a second takeover, re-opening the same
    playbook, and a playbook with no tools.
  - Path B → additive tools and `activation_reason: trigger`.
  - Mixed A/B orders.
- **`playground_messages_controller_spec.rb`**, real-engine context (the real controller →
  `TurnRunner` → `RubyLLM::Chat`, with WebMock only at Gemini's `generateContent`): every acceptance
  scenario of US1–US3, plus Edge Cases 1–7, FR-016/FR-017, and an interruption over a procedure pinned by an
  earlier trigger opening (`activation_reason: trigger`). Assertions are on the HTTP response
  (`reply`, `tool_calls`), persisted `ScoutConversationState`, and the outgoing provider request
  bodies:
  - system text: `contents[0].parts[0].text`;
  - offered tools: `tools[0].functionDeclarations[].name`.

## 2. Playground smoke test (behavioral proof — brief §7's own acceptance check)

Needs a development account with the `scout`, `scout_v2` and `opportunities` features, and a
`ScoutAccountConfig` with a **real** API key (this step calls the real model).

1. **Build a throwaway dev catalog.** `tmp/` is gitignored:
   ```bash
   mkdir -p tmp/scout_v2_playbooks && cp custom/playbooks/qualificacao.md tmp/scout_v2_playbooks/
   cat > tmp/scout_v2_playbooks/pausa.md <<'MD'
   ---
   name: pausa
   title: Pausa solicitada
   priority: 20
   trigger: O cliente pede para pausar ou continuar a conversa mais tarde.
   ---

   ## Passos
   1. Confirme a pausa com gentileza e diga que a conversa pode ser retomada a qualquer momento.
   MD
   ```
   Add `SCOUT_V2_PLAYBOOKS_DIR=/app/tmp/scout_v2_playbooks` to `.env`, then run
   `docker compose up -d --force-recreate rails`.
2. **Pin `qualificacao` by state.** Make `qualificacao`'s `when_state` true for the scout's
   playground conversation (`Custom::ScoutV2::PlaygroundConversation.for(scout)`): give the scout at
   least one required opportunity attribute, and open an `Opportunity` for that conversation with
   the attribute still empty. Send any message. Confirm
   `ScoutConversationState.for_conversation(conversation)` has `active_playbook == 'qualificacao'`
   and `activation_reason == 'state'`, and record its `activated_at`.
3. **Trigger the interruption.** Send "posso pausar por um momento?". The response's `tool_calls`
   should show `open_playbook` with `arguments: { name: 'pausa' }`, and the reply should follow
   `pausa`'s steps, not ask for the pending qualification field.
4. **Check that nothing was written (FR-011).** Immediately re-read the state:
   `active_playbook == 'qualificacao'`, `activation_reason == 'state'`, and `activated_at` equal to
   the value recorded in step 2.
5. **Check that the procedure resumes (FR-012).** Send the next message in the same playground
   conversation (a new top-level turn), e.g. "ok, pode continuar". The reply should ask for the
   pending qualification field again: the conversation is routed to `qualificacao`, not stuck on
   `pausa`.
6. **Clean up.** Remove the `.env` line, run `docker compose up -d --force-recreate rails`, and
   delete `tmp/scout_v2_playbooks/`.

## 3. Openable-set boundary check (SC-001, SC-002, FR-004 edge cases)

Uses the dev catalog from §2 step 1. The shipped catalog alone has no situational playbook, so
the pinned check below would pass on an empty set and prove nothing.

```ruby
# docker compose exec rails bundle exec rails console
catalog = Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('tmp/scout_v2_playbooks'))
pinned_playbook = catalog['qualificacao']

nothing_pinned = Custom::ScoutV2::Playbook::OpenableSet.call(catalog: catalog, pinned: nil)
nothing_pinned.to_a == catalog.to_a # => true — full catalog

something_pinned = Custom::ScoutV2::Playbook::OpenableSet.call(catalog: catalog, pinned: pinned_playbook)
something_pinned.map(&:name) # => ["pausa"] — situational only, non-empty

shipped = Custom::ScoutV2::Playbook::Loader.load_all
Custom::ScoutV2::Playbook::OpenableSet.call(catalog: shipped, pinned: shipped['qualificacao']).none? # => true — FR-004: open_playbook withheld
```

## 4. Regression check — Brief 04 contract points that must still hold

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec --format progress \
  custom/spec/services/custom/scout_v2/turn_runner_spec.rb \
  custom/spec/services/custom/scout_v2/router_spec.rb \
  custom/spec/services/custom/scout_v2/instructions/ \
  custom/spec/services/custom/scout_v2/playbook/validator_spec.rb \
  custom/spec/models/scout_conversation_state_spec.rb
```

Expected: all green. Only `turn_runner_spec.rb`'s pinned tool-catalog example is edited (Brief 11 §5
cutover, `research.md` §9); every other example still holds under the new gate.
`index_builder_spec.rb` is edited (empty-set wording) and runs in §1.

## 5. Regression check — v1 untouched (FR-015)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec --format progress \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb
```

Expected: unchanged, all green — no file under `custom/app/services/custom/scout/` (v1 namespace)
is touched by this feature.

## 6. Deliberate-mutant checks (Constitution Principles VI/VII — no mutation tooling in repo)

Apply each mutant alone. Run the §1 specs. Confirm **at least one example fails**. Then revert
(`git checkout -- <file>`). A mutant that survives means a missing assertion: add it before
finishing.

| # | Mutant | Must be killed by |
|---|---|---|
| M1 | `OpenableSet.call` always returns `catalog` | `openable_set_spec.rb` pinned case; request spec "index lists only situational playbooks while pinned" |
| M2 | `TurnRunner` gate `openable.any?` → `true` | request spec "pinned, no situational playbook → `open_playbook` not offered"; "nothing pinned, empty catalog" |
| M3 | `takeover!`: `replace: true` → `replace: false` | `open_playbook_spec.rb` Path A `pausa`, pinned (`manage_opportunity` must be dropped); request spec FR-016 same-step call |
| M4 | `takeover!` also calls `record_trigger_activation!` | `open_playbook_spec.rb` Path A no-write; request spec US3 AC1/AC2/AC3, "Edge Case 7", "FR-011 over a trigger-stored pin" |
| M5 | branch inverted (`when_state.present?` → takeover) | `open_playbook_spec.rb` Path A and Path B examples |
| M6 | `TurnSetup#baseline_instructions` built with `decision.playbook` (keeps Block 3) | request spec US2 AC1/AC2 (post-takeover system text lacks `qualificacao` body) |
| M7 | `self` omitted from `takeover!`'s `with_tools` | `open_playbook_spec.rb` FR-009; request spec second takeover in same turn |
| M8 | `takeover!` registers the playbook's declared tools without `@turn_setup.tool_wrapper` | request spec "FR-012 clause 3" (`tool_calls` lacks the `manage_opportunity` entry added by the `duvida_comercial` takeover) |
| M9 | `IndexBuilder::EMPTY_INDEX_LINE` reverted to the "Nenhum procedimento específico habilitado no catálogo." wording | `index_builder_spec.rb` empty case; request spec "pinned, no situational playbook" index assertion |
| M10 | `takeover!` rebuilds the baseline index from the pin stored mid-turn (e.g. `OpenableSet.call(catalog:, pinned: <playbook named by ScoutConversationState>)` instead of the injected `TurnSetup#baseline_instructions`) | request spec "FR-017 / FR-002 / Edge Case 6" (after Path B then Path A, the last request's index still lists `- qualificacao:`) |
| M11 | `TurnRunner` calls `wrap_tool` on `always_on_tools` (or on `open_playbook`) by hand, before the `setup_chat` loop wraps them again | request spec US2 AC1–AC3 (`tool_calls` is exactly `open_playbook` + one `search_knowledge_base`); request spec US3 AC4 (exactly one `open_playbook` entry) |
| M12 | `takeover!` passes `@turn_setup.baseline_tools` and `self` through `@turn_setup.tool_wrapper` again | request spec US2 AC1–AC3 (the post-takeover `search_knowledge_base` call is recorded once); request spec US2 AC4 (exactly three `open_playbook` entries) |
