# Phase 05 — Commercial Configuration UI

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §7
**Depends on**: Phase 01 (data model), Phase 04 (`ScoutTool` for the tools tab).

## Goal

Give account admins a dashboard UI (Vue 3 + Tailwind, `components-next/` where relevant per
project conventions) to configure Scouts end to end without touching the console.

## UI placement & permissions

Mirror Chatwoot's existing Captain feature exactly — do not invent a new pattern:

- **Business/commercial config → primary menu, not Settings.** Scout list/create/edit, product
  catalog, knowledge base, funnel/qualification config, `ScoutTool` CRUD, and the Playground all
  live under a new primary-menu section (`accounts/:accountId/scout/...`), matching how Captain's
  assistant config (guidelines, guardrails, scenarios, tools, playground, inboxes) lives under
  `accounts/:accountId/captain/...` — never under `accounts/:accountId/settings/captain`.
- **LLM/provider config → Settings, admin-only.** The current BYOK flow (each account configures
  its own `provider`/`model_name`/`api_key_override`) belongs under
  `accounts/:accountId/settings/scout`, mirroring `accounts/:accountId/settings/captain`
  (`routes/dashboard/settings/captain/captain.routes.js`), which restricts `permissions:
  ['administrator']`. **Superseded by Phase 06** (`06-account-llm-config/spec70.md`): per-Scout BYOK
  is replaced by one account-level `ScoutAccountConfig`, and the settings screen moves out of the
  Settings module into a "Configurações" entry in the Scout primary-menu submenu.
- **Permission split.** Primary-menu Scout routes (list/create/edit, product catalog, knowledge
  base, funnel config, tools, playground) use `permissions: ['administrator', 'agent']`, matching
  Captain's `assistantRoutes` meta. The Settings LLM/provider screen uses `permissions:
  ['administrator']` only, matching Captain's settings route meta. Do not put LLM/API key
  configuration behind the `agent` role.

## Scope

- Scout list/create/edit screens, inbox association (`ScoutInbox`).
- §7.1 Products/Services/Offers tab (`product_catalog`).
- §7.2 Commercial knowledge base tab (`knowledge_sources`) — URL crawling and document upload for
  RAG; FAQ/objection-handling entries.
- §7.3 Funnel & qualification config tab — stage selection (`default_pipeline_stage_id`,
  `qualified_stage_id`, `unqualified_stage_id`), required qualification fields.
- `ScoutTool` CRUD screen (external API/webhook tools from Phase 04).
- Playground endpoint/screen to simulate tool calls without a real WhatsApp conversation
  (spec60.md §5, "Playground de Teste" row).
- i18n: bare strings avoided, `en.json`/`pt_BR.json` updated synchronously per project convention.

## Out of scope

- No in-conversation UI components (badge, pause/resume button) — Phase 09.
- No billing/plan-gating UI — quota is set via `responses_quota` directly (console/seed or a simple
  numeric field on this screen), no subscription flow.

## Acceptance criteria

- An admin can create a Scout, attach it to an inbox, configure product catalog/knowledge
  sources/qualification stages, and add an external tool, entirely from the dashboard, in the
  primary menu (not Settings).
- An agent (non-admin) can access the same business-config screens (list/edit, product catalog,
  knowledge base, funnel config, tools, playground) but cannot access the Settings LLM/provider
  screen — matching Captain's permission split.
- The Playground screen can trigger a real tool-calling round-trip and display the result without
  needing an actual WhatsApp message.
- No bare user-facing strings; `en.json`/`pt_BR.json` both updated.
