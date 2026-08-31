# Quickstart: Funnel Outcome-Stage Matching for Scout

This feature is a prompt-text and UI-copy change, so validation is (1) automated spec assertions that
the new/extended guidance text is actually built into the prompt, and (2) a manual behavioral smoke
test replaying the real conversations that motivated the feature, since — per spec.md's Assumptions —
no automated test can prove the model reliably *obeys* prompt text, only that the text is present.

## Prerequisites

- Stack running: `docker compose up -d`
- No new data/migration needed; use any account with a Scout configured with
  `qualified_stage`/`unqualified_stage` and at least one stage `description` set (see
  `custom/spec/services/custom/scout/system_prompts_service_spec.rb`'s `funnel_section` context for a
  ready-made fixture shape if you need to build one in the console).

## 1. Automated: prompt text assertions

Run the extended spec file:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb
```

**Expected**: all examples pass, including the new ones added under `funnel_section (User Story 1)`
(outcome-comparison bullet with the tie-break/forward-only clauses; tools-are-sufficient bullet) and
under the top-level `.build` describe block (extended "Confirmação de ação" and "Esclarecimento"
assertions; new "Ritmo e condução da conversa" bullet assertions). See `data-model.md` and
`research.md` §1–§2 for exactly which bullets/clauses each new example should assert on.

## 2. Manual: UI hint visibility

1. Open the dashboard → Settings → Pipeline Stages (wherever `AddPipelineStage.vue`/
   `EditPipelineStage.vue` are mounted in this account's Kanban settings).
2. Click "Add stage" — confirm the hint paragraph appears directly under the "Description" label,
   above the textarea, in the account's configured language (English or Portuguese depending on
   locale), with the field still empty.
3. Open "Edit" on an existing stage that already has a non-empty description — confirm the same hint
   still appears (it must not depend on the field being empty, per spec FR-009).
4. Save a stage in both flows — confirm save behavior/API payload is unchanged (no new field is sent).

## 3. Manual behavioral smoke test: replay real conversations via `PlaygroundRunner`

No widget interaction needed — reconstruct each conversation's message history and replay it through
the same runner class the existing Scout Playground UI already uses
(`custom/app/services/custom/scout/playground_runner.rb`), via `rails runner`:

```bash
docker compose exec rails bundle exec rails runner - <<'RUBY'
scout = Scout.find(SCOUT_ID) # the Scout tied to the account/inbox under test

# Reconstruct the message sequence for the conversation being replayed
# (pull message bodies/roles from Conversation#messages for the real display_id,
#  or hand-transcribe them from spec-preview.md's evidence transcript).
message_history = [
  { role: 'user', content: '...lead message 1...' },
  { role: 'assistant', content: '...prior Scout reply...' },
  # ...
]
final_lead_message = '...the lead message whose outcome should trigger a stage move...'

result = Custom::Scout::PlaygroundRunner.new(
  scout: scout,
  message: final_lead_message,
  message_history: message_history
).perform

puts result[:reply]
puts result[:tool_calls].inspect
RUBY
```

**Expected outcome per scenario** (per spec79.md's Testes section and this spec's Acceptance
Scenarios):

- **Refusal/postponement scenario** (mirrors real conversation display_id 19, Opportunity #10):
  `result[:tool_calls]` includes a `move_opportunity_stage` (or `manage_opportunity` with a `stage_id`
  change) call targeting the Scout's `unqualified_stage_id`.
- **Confirmation-with-all-data scenario** (mirrors display_id 18/20, Opportunities #9/#11):
  `result[:tool_calls]` includes a `move_opportunity_stage`/`manage_opportunity` call targeting the
  Scout's `qualified_stage_id`, with no `handover_to_human` call in the same result.
- **False-capability-gap scenario** (mirrors display_id 46, Opportunity #36): `result[:tool_calls]`
  includes a `manage_opportunity`/`move_opportunity_stage` call carrying the schedule/date the lead
  provided, with no `handover_to_human` call citing a missing tool.
- **Pacing/confirmation checks** (User Stories 3–5, any scenario): `result[:reply]` contains at most
  one `?`-terminated question, does not end abruptly after presenting new information (unless the
  transcript's last lead turn was a pause/closing signal), contains no digits-only opportunity ID or
  raw field-key text (e.g. no `interesse`, `origem_da_oportunidade`), and does not enumerate a
  list-valued field's full allowed-values list as a menu.
- **Multi-stage tie-break scenario** (FR-001's closest-match clause, clarified in `/speckit-clarify`):
  build a transcript whose final outcome could plausibly read as matching two configured stage
  descriptions at once (e.g. a lead who hesitates in a way that partially resembles both a
  data-collection stage and the disqualification stage). `result[:tool_calls]` should target whichever
  stage's description is the closest, most specific textual match — confirm by eye that the chosen
  `stage_id` corresponds to the more specific description, not a fixed "disqualification always wins"
  or "first stage in list wins" pattern.
- **Forward-only regression guard** (FR-001a/SC-007a, clarified in `/speckit-clarify`): start from an
  opportunity already in the Scout's `qualified_stage_id` (set it up directly, e.g.
  `opportunity.update!(pipeline_stage: scout.qualified_stage)`), then replay a final lead message that
  reads like a refusal/postponement matching the disqualification stage description. `result[:tool_calls]`
  must NOT include a `move_opportunity_stage`/`manage_opportunity` call moving the opportunity out of
  the qualified stage — confirm the opportunity's stage is unchanged after the run.
- **No-description-configured no-op** (FR-010/SC-007): using a Scout/account where the relevant stage
  has no `description` set, replay a transcript whose outcome would otherwise suggest a move into that
  stage. `result[:tool_calls]` should show no forced stage transition attributable to outcome-matching
  for that stage — confirm behavior matches what the same transcript produced before this feature's
  prompt changes (no regression).

This is a smoke test, not a pass/fail gate enforceable in CI — model behavior is stochastic (spec.md
Edge Cases). Re-run a scenario a few times if the first reply looks off before concluding the prompt
change needs adjustment.
