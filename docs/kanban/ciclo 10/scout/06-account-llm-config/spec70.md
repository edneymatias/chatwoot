# Phase 06 — Account-Level LLM Configuration

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §7 (UI placement), §9.1 (`Scout` fields)
**Depends on**: Phase 01 (`Scout` core data model), Phase 05 (commercial UI, sidebar/menu structure).
**Depended on by**: Phase 07 (RAG Knowledge Search — reads the same account config for the embedding
provider/key).

## Goal

Replace per-Scout LLM provider/model/API-key (BYOK) with a single, shared, account-level
configuration used by every Scout in the account. This fork's customers pick one provider
(Gemini/OpenAI/Anthropic) for their whole account — per-Scout provider choice is unused complexity,
not a real requirement.

## This supersedes prior BYOK design

Phase 01/05 shipped `Scout#provider`, `Scout#model_name`, `Scout#api_key_override` (per-Scout,
encrypted) plus a Settings-module screen (`accounts/:accountId/settings/scout`) to edit them per
Scout. `spec66.md` (§"UI placement & permissions") already flagged this as an interim design:
*"When BYOK is later replaced by ... this is the screen that changes."* This phase is that change —
resolved as a single account-level config, not super-admin-provisioned credits.

No production data exists yet for these fields (Scout is still pre-launch) — no backfill/migration
of existing values is needed.

## Scope

- New table `ichatr_scout_account_configs`: `account_id` (bigint, unique index, FK to `accounts`),
  `provider` (integer enum: `gemini`/`openai`/`anthropic`), `model_name` (string), `api_key`
  (string, `encrypts :api_key` — same encryption approach as the `Scout#api_key_override` it
  replaces).
- New model `ScoutAccountConfig` (flat naming, matching `Scout`/`ScoutKnowledgeSource`),
  `belongs_to :account`, validates presence of `provider`/`model_name`/`api_key`. One row per
  account (enforced by the unique index).
- `app/models/account.rb` (core) is **not** touched — no `has_one` added there, per this fork's
  convention of minimizing contact surface with core files from `custom/`. Lookups go through
  `ScoutAccountConfig.find_by(account_id:)` directly.
- Migration drops `Scout#provider`, `Scout#model_name`, `Scout#api_key_override` and their enum.
- `Scout#llm_chat` (`custom/app/models/scout.rb`) is refactored to build the `RubyLLM` context from
  the account's `ScoutAccountConfig` instead of its own columns.
- New controller (e.g. `Api::V1::Accounts::Scouts::AccountConfigsController`, singular resource,
  `show`/`update`), admin-only policy, mirroring existing Scout controllers/policies.
- Frontend:
  - New page under `dashboard/scout/pages/` (moved out of the Settings module entirely) — a single
    form: provider `Select`, model `Input` (free text, matching current UX), API key `Input`
    (password, write-only, blank-if-configured like today's placeholder pattern). No scout picker —
    there is only one config per account.
  - New route `scout_settings` in `dashboard/scout/scout.routes.js`, `permissions:
    ['administrator']` only (unchanged permission split from `spec66.md`).
  - Old `settings/scout/scout.routes.js` + `Index.vue` deleted.
  - `ScoutList.vue`'s create-Scout dialog drops the provider/model/API-key fields — no longer
    stored per Scout.
  - `Sidebar.vue`: the top-level **Scout** entry becomes an expandable item with `children`:
    **Agentes** (→ `scouts_index`), **Configurações** (→ `scout_settings`), **Ferramentas** (→
    `scout_tools`, moved out of the header-button on `ScoutList.vue` into this submenu).
  - i18n: `en.json`/`pt_BR.json` updated synchronously (new submenu labels, settings page strings);
    obsolete per-Scout provider strings removed.

## Out of scope

- No support for mixed providers within one account (e.g. one Scout on Gemini, another on OpenAI) —
  explicitly rejected; one provider per account.
- No secondary/embedding-only API key for Anthropic accounts — see Phase 07 for how RAG search
  degrades (tool not registered) when `provider == 'anthropic'`.
- No super-admin-provisioned credits/billing flow — this phase only relocates and consolidates BYOK,
  it doesn't change who pays for API usage.

## Acceptance criteria

- An account has exactly one `ScoutAccountConfig`; every Scout in that account uses it for chat via
  `Scout#llm_chat`, with no per-Scout override possible.
- Creating/editing a Scout no longer exposes provider/model/API-key fields.
- The Scout submenu shows **Agentes**, **Configurações**, and **Ferramentas** as sibling entries;
  **Configurações** is reachable only by administrators and lives outside the Settings module.
- No bare user-facing strings; `en.json`/`pt_BR.json` both updated.
