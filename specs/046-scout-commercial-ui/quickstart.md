# Quickstart: Validating Scout Commercial Configuration UI

Prerequisites: stack running (`docker compose up -d`), an account with the `scout` feature flag
enabled and at least one `PipelineStage`, one `CustomAttributeDefinition`, and one connected inbox
seeded (`bundle exec rails db:seed` or `Seeders::AccountSeeder`).

## 1. Admin configures a Scout end to end (User Story 1 / SC-001)

1. Log in as an account admin, open the **Scout** primary-menu section
   (`/app/accounts/:id/scout`).
2. Create a new Scout (name, provider, model, API key — provider fields required at creation only).
3. From the Scout's detail view, attach an inbox (Scout ↔ Inbox tab).
4. Add one product/offer entry on the **Products** tab.
5. Add one knowledge source (a URL) on the **Knowledge Base** tab; confirm it shows `pending` then
   `ready` (or `failed` with a visible reason) once the background job runs.
6. On the **Funnel** tab, set the triage/qualified/unqualified stages and pick at least one
   qualification field from the account's custom attributes.
7. Reload the Scout — confirm every value set above is still present.

Expected: all steps complete without leaving the dashboard or touching Settings/console.

## 2. Agent/admin permission split (User Story 2 / SC-002)

1. Log in as a non-admin agent. Confirm the same Scout primary-menu screens (list/edit, products,
   knowledge base, funnel, tools, playground) are reachable and editable.
2. Attempt to open the Scout's LLM provider/API key screen (Settings → Scout). Confirm access is
   denied, including via direct URL navigation.
3. Log back in as admin and confirm that screen is reachable and editable.

Expected: 0 successful agent accesses to the provider/API-key screen; 100% success on the
business-config screens for both roles.

## 3. External tool + Playground round trip (User Story 3 / SC-003)

1. As admin, create a `ScoutTool` (Tools screen) pointing at a reachable test endpoint (e.g. a local
   webhook echo service).
2. Open the Scout's **Playground**, send a message expected to trigger that tool.
3. Confirm the tool call and its real result are shown in the Playground, and that no new
   conversation appears in the inbox's live conversation list.
4. Point the tool at an unreachable/erroring endpoint and repeat — confirm the failure is shown in
   the Playground result rather than a silent success.

Expected: Playground always performs a real call to the external endpoint (per the clarified
Playground behavior) and surfaces both success and failure outcomes.

## 4. i18n check (FR-011 / SC-004)

Run `docker compose exec vite pnpm eslint` (catches bare-string lint rules where configured) and
manually switch the dashboard locale to Portuguese; confirm all new Scout screens render translated
copy with no raw English fallback strings or missing-key placeholders.
