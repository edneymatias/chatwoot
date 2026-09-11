# Quickstart: Validating the Natural Handoff Message

This guide validates the feature end-to-end once implemented, per the acceptance scenarios in
[spec.md](./spec.md) and the object collaboration in [data-model.md](./data-model.md). It assumes
the container stack is already up (`docker compose up -d`) per this repo's standard dev workflow.

## Prerequisites

- A Scout-enabled account/inbox in the dev environment with at least one existing conversation
  (or the ability to create one via the standard chat widget/API flow).
- `Custom::Scout::PlaygroundRunner` available for behavioral replay (already used for this pattern
  in Phase 18, `spec79.md`).
- The historical conversation referenced by the source design doc: `conversation_id 43` /
  `display_id 41` — the original evidence for the generic-message complaint.

## Automated checks

Run the targeted Scout spec files (existing suite, updated by this feature — see `tasks.md` for the
exact edits expected in each):

```sh
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/tools/handover_to_human_spec.rb \
  custom/spec/services/custom/scout/handoff_service_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb
```

**Expected outcome**: All examples pass, including the new/updated examples that assert:
- `HandoverToHuman#execute` outside the playground no longer calls `HandoffService` directly — it
  only sets `handoff_needed`/`handoff_assignee_id`/`handoff_team_id`/`handoff_reason` and returns an
  instruction string to the model (User Story 1).
- `HandoffService#perform` uses `message:` as the public handoff content when present, and falls
  back to the fixed `I18n` string when `message` is blank/nil (User Story 3).
- `AgentRunner` scenarios: handoff via `handover_to_human` shows the model's parsed `response` text
  as the public message (User Story 1); handoff via automatic stage qualification shows the same
  (User Story 2); handoff via `ActionClassifierService` still shows the fixed text (User Story 5).
- `SystemPromptsService#guardrails_section` includes the extended "Fallback para humano" directive
  (supports User Story 4).

## Manual / behavioral validation

1. **Assistant-initiated handoff (User Story 1)**
   - Start a fresh conversation and steer it so the assistant decides a human is needed (e.g., ask
     something outside its knowledge, or explicitly ask for a human).
   - **Expect**: the customer-visible closing message is a natural sentence referencing what was
     discussed, not the old generic sentence — and it is the *only* handoff message shown.

2. **Automatic qualification handoff (User Story 2)**
   - Continue a conversation until the associated opportunity is moved into the qualified pipeline
     stage (via `manage_opportunity`/`move_opportunity_stage` tool activity in the conversation).
   - **Expect**: the customer sees a natural closing message sourced from that turn's response, not
     the generic sentence, with no behavior change in *when* the handoff itself fires.

3. **Fallback safety net (User Story 3)**
   - Force an unparseable/blank model response on a turn that ends in handoff (e.g., via a stubbed
     LLM response in a lower environment, or by reviewing the code path directly).
   - **Expect**: the customer still receives the existing fixed `I18n` sentence — no blank or
     broken message.

4. **No trailing question (User Story 4) — replay verification**
   - Using `Custom::Scout::PlaygroundRunner`, replay `conversation_id 43` / `display_id 41` (the
     original evidence conversation from the preview doc).
   - **Expect**: the resulting closing message does not end in a question directed at the customer,
     and no longer repeats the old generic sentence verbatim.

5. **Unaffected path — consistency-review handoff (User Story 5)**
   - Drive a conversation to a state where `ActionClassifierService`/`ResponseAuditor` decides a
     handoff independently of the current turn (Phase 12 behavior).
   - **Expect**: the customer still sees the existing fixed generic sentence — no regression, no
     model-authored text on this path.

6. **Playground/simulation unaffected**
   - Run the same `handover_to_human` scenario from the Scout playground (simulated mode).
   - **Expect**: the existing `"[Simulado] Atendimento transferido para humano..."` confirmation
     text is unchanged.

## Sign-off criteria

All items in spec.md's **Success Criteria** section (SC-001 through SC-005) are observable via the
automated checks and manual scenarios above; no additional tooling is required.
