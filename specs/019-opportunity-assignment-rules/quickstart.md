# Quickstart: Validating Opportunity Assignment Rules

Prerequisites: dev stack running (`docker compose up -d`), a seeded account with at least one pipeline stage, two agents/administrators, and an inbox with a conversation. See root `CLAUDE.md` for exact seed commands.

## Scenario 1 — Automation-driven assignment (User Story 1, FR-001/002/003)

1. In Settings → Automation, create a rule with a `create_opportunity` action.
2. Configure a pipeline stage and set assignee to a specific agent. Save and trigger the rule (e.g. send a matching conversation event).
3. **Expect**: an opportunity is created (previously it silently failed every time — this is the regression check for the bug fix), landed in the configured stage, owned by the configured agent.
4. Repeat with assignee set to "Mesmo da conversa" ("same as the conversation") on a conversation that has an assignee.
5. **Expect**: the created opportunity's owner matches the conversation's current assignee.
6. Repeat again on a conversation with **no** assignee.
7. **Expect**: opportunity is still created, with no owner (no fallback).

Reference: [contracts/create-opportunity-automation-action.md](./contracts/create-opportunity-automation-action.md)

## Scenario 2 — Manual reassignment (User Story 2, FR-004/006)

1. Open an existing opportunity's edit modal (kanban card → edit).
2. Set the new "Assignee" field to an agent, save.
3. **Expect**: the opportunity's owner updates immediately; reopening the modal shows the new assignee pre-filled.
4. Repeat, clearing the field back to "Sem dono".
5. **Expect**: opportunity becomes unassigned.
6. Confirm this works when performed by any agent/administrator account, not just the opportunity's current owner (no permission gate).
7. **Expect (FR-008)**: the Assignee `<select>` in this modal offers only real agents/administrators plus the unassigned option — it does NOT include a "same as the conversation" choice (that option is exclusive to the automation action's config UI from Scenario 1).

Reference: [contracts/opportunity-assignee-field.md](./contracts/opportunity-assignee-field.md)

## Scenario 3 — Assign at creation time (User Story 3, FR-007)

1. Open the opportunity creation modal (currently reachable only via direct component usage / dev tooling, since no new UI entry point is added by this feature).
2. Pick an assignee before submitting.
3. **Expect**: the created opportunity is owned by that assignee.
4. Submit again leaving assignee unset.
5. **Expect**: opportunity created with no owner.
6. **Expect (FR-008)**: the Assignee `<select>` in this modal offers only real agents/administrators plus the unassigned option — no "same as the conversation" choice, same as Scenario 2.

## Regression checks

- Reopen an automation rule that was configured before this feature (old `{ id, name }` shape). **Expect**: pipeline stage and assignee fields both show as unset — not an error, not auto-filled.
- An automation rule with `assign_agent` (to a fixed agent) placed before a `create_opportunity` (`same_as_conversation`) action in the same rule: trigger it. **Expect**: the created opportunity is owned by that same fixed agent, since the conversation is reloaded before each action runs.
- Confirm no notification is generated/queued for any of the above assignment/reassignment paths.

## Automated coverage pointers

- Backend: `spec/services/automation_rules/action_service_spec.rb` (`#perform with create_opportunity action`) — extend for assignee resolution and the stage-id fix.
- Frontend: no new automated tests planned; verify manually via the scenarios above, per this project's no-TDD-by-default convention.
