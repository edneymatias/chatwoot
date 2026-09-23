# Quickstart: Validating the Response Auditor Repair Loop Fix

## Prerequisites

- Stack running: `docker compose up -d` (see root `AGENTS.md`).
- No migrations required — this feature adds no schema.

## 1. Targeted spec run (primary validation)

Per Constitution Principle IX, scope test execution to the modified file
during iteration:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/response_auditor_spec.rb
```

Expected new coverage (added under TDD, red before the fix, green after —
see `contracts/response_auditor.md` for the exact behavior each proves):

- **US1 (FR-001/002/003)**: `audit` called with `handoff_already_flagged: true`
  returns `{ action: :proceed, reply: response_text }` unchanged, and neither
  `ClaimConsistencyService#check` nor `chat.ask` is invoked. Assert via
  `expect(claim_service).not_to receive(:check)` and
  `expect(fake_chat).not_to receive(:ask)`, matching this spec file's
  existing double-based conventions (e.g. the "does not call
  ClaimConsistencyService if conversation is no longer pending" example).
- **Regression (FR-004, Scenario 3)**: the existing "triggers one internal
  repair on false_completed_action..." example (constructed with the default
  `handoff_already_flagged: false`) continues to pass unmodified.
- **Regression (FR-005, Scenario 4)**: the existing "signals handoff instead
  of dispatching a second reply when the repair call itself triggers a
  handoff" example continues to pass unmodified.
- **US2 (FR-006)**: when a repair call runs, `Rails.logger.info` receives a
  message containing the repaired call's reasoning content — assert with
  `expect(Rails.logger).to receive(:info).with(/repair reasoning/)` (or
  equivalent) around the existing false_completed_action repair example.

## 2. Full-file regression confirmation

The same command as step 1 also re-runs every pre-existing example in the
file (US1 safe/repair/escalate/handoff/error/non-pending paths, US2 action
classifier + confirmation-temperature paths) — confirms SC-003 (no
regression in the genuine-repair and repair-discovers-new-handoff cases).

## 3. Caller-level confirmation (agent_runner_spec.rb)

`agent_runner_spec.rb` already asserts
`ResponseAuditor.new` is constructed with
`handoff_already_flagged: true` when a handoff tool ran
(`agent_runner_spec.rb:226-231`); no caller-side change is needed, but re-run
it to confirm the contract at the call boundary is untouched:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/agent_runner_spec.rb
```

## 4. End-to-end behavioral replay (SC-001)

`Custom::Scout::PlaygroundRunner` cannot be used for this replay: it never
constructs or calls `Custom::Scout::ResponseAuditor` (only
`Custom::Scout::AgentRunner`, the production path, does — confirmed in
`docs/kanban/ciclo 10/scout/12-response-auditor/spec78.md:148`), so it cannot
exercise the claim-consistency/repair-loop behavior this feature changes.
Replay through `AgentRunner` directly instead, against a disposable dev
conversation — never a real customer's live conversation, since
`AgentRunner#perform` dispatches a real outgoing message and can trigger a
real handoff:

```bash
docker compose exec rails bundle exec rails runner \
  "conversation = Conversation.find_by(display_id: <dev_conversation_display_id>); \
   scout = conversation.inbox.scout; \
   Custom::Scout::AgentRunner.new(scout: scout, conversation: conversation).perform"
```

Pick or create a `pending`-status dev conversation whose message history ends
with a pricing question the persona isn't allowed to answer directly (so the
model calls `handover_to_human` and writes its own closing message in the
same turn). This call mutates the conversation (dispatches a real message,
may call `bot_handoff!`/assign a human) — use a scratch conversation seeded
for this purpose, not conversation history you need to preserve.

**Expected outcome**: the customer-facing message
(`conversation.reload.messages.last.content` after the run) and the internal
transfer note both match exactly what the model wrote in its first
structured response (visible in the `[Scout AgentRunner] reasoning:` log
line preceding delivery) — no "correção de turno anterior", "desculpe pela
confusão", or any other reference to a prior turn.

## 5. Log verification (SC-004)

Tail logs during step 4, or during any conversation that genuinely triggers
repair (a reply promising an action with no backing tool call), and confirm a
`[Scout][ResponseAuditor] repair reasoning: ...` line is present — the
repair outcome must be diagnosable from logs alone, without correlating raw
request/response data.

```bash
docker compose logs -f rails | grep -i "ResponseAuditor"
```
