# Phase 1: Backend Core — Opportunities & Pipeline Stages

**Depends on**: nothing (first phase, foundation for all others)
**Feeds**: Phase 2 (automation), Phase 3 (frontend), Phase 4 (realtime/menu)

## Context

This replaces the `001-kanban-conversas` design (Kanban lanes derived from a Conversation custom attribute) with a proper domain model: `Opportunity`, belonging to a `Contact` (not a `Conversation`), moving through admin-configurable `PipelineStage`s. This phase builds the persisted data model and manual CRUD only — no automation, no frontend, no realtime.

The entire module lives in an isolated `custom/` tree at the repo root, mirroring the existing `enterprise/` overlay convention, so that pulling future upstream Chatwoot changes never produces a merge conflict in this module's own files. `custom/` is not paywalled or Enterprise-gated — it reuses a currently-unwired extension point already present in `lib/chatwoot_app.rb` (`ChatwootApp.custom?` / `ChatwootApp.extensions`).

Database tables use a `matias_` prefix (`matias_opportunities`, `matias_pipeline_stages`) to guarantee no future collision if Chatwoot upstream ever ships a native "Opportunities" feature with the same table names.

## Dev Environment

There is no host-level Ruby/Node dev environment for this project — everything runs via the Docker Compose stack (`docker-compose.yaml` + `docker-compose.override.yaml`, Podman-backed `docker compose` CLI). All commands in this and every other phase's Completion Criteria MUST be run inside the appropriate container, not on the host:
- Backend (Rails console, rspec, rails runner, migrations): `docker compose exec rails <command>`
- Frontend (pnpm, eslint, vitest): `docker compose exec vite <command>`
Containers are expected to already be running (`docker compose up -d`); do not add host-only fallback instructions.

## Functional Requirements

**FR-001**: `config/application.rb` MUST register `custom/app/**` in `config.eager_load_paths`, following the exact same pattern already used for `enterprise/app/**` (three lines: `enterprise/lib`, `enterprise/listeners`, `enterprise/app/**` → add equivalent `custom/lib`, `custom/app/**`). This is the only line-level edit to a core file in this phase.

**FR-002**: A `PipelineStage` model MUST exist at `custom/app/models/pipeline_stage.rb`, table `matias_pipeline_stages`, with fields: `id`, `account_id` (FK → `accounts`), `name` (string), `position` (integer), timestamps. `belongs_to :account`. Ordered scope by `position`.

**FR-003**: An `Opportunity` model MUST exist at `custom/app/models/opportunity.rb`, table `matias_opportunities`, with fields: `id`, `account_id` (FK → `accounts`), `contact_id` (FK → `contacts`, no uniqueness constraint — a Contact may have multiple simultaneous Opportunities), `pipeline_stage_id` (FK → `matias_pipeline_stages`), `origin_conversation_id` (FK → `conversations`, nullable, immutable after creation — no update path exists for this field once set), `assignee_id` (FK → `users`, nullable), `title` (string), `status` (enum: `open` default, `won`, `lost` — independent of `pipeline_stage_id`), timestamps.

**FR-004**: `Opportunity` validations: `title`, `contact_id`, `pipeline_stage_id`, `account_id` presence required. `pipeline_stage` MUST belong to the same `account` as the `Opportunity` (cross-account assignment is invalid).

**FR-005**: When an account has zero `PipelineStage` records and an admin opens the Pipeline Stages settings screen (or hits the stages API) for the first time, the system MUST lazily seed two default stages: "Leads Recebidos" (position 0) and "Em Contato" (position 1). This is NOT a global data migration — it happens per-account, on-demand, via a service/controller `before_action`.

**FR-006**: An `OpportunityPolicy` (Pundit) MUST exist at `custom/app/policies/opportunity_policy.rb`. Administrators can view/edit all Opportunities in the account. Agents can view/edit an Opportunity if they are the `assignee`, OR if they have access to the `origin_conversation` per the existing `ConversationPolicy` inbox/team scoping (reused, not reimplemented).

**FR-007**: A `PipelineStagePolicy` MUST exist, admin-only (mirrors other Settings policies like `custom_attribute_definition_policy.rb`).

**FR-008**: `Api::V1::Accounts::OpportunitiesController` (`custom/app/controllers/api/v1/accounts/opportunities_controller.rb`) MUST support `index` (scoped/paginated per policy), `show`, `create`, `update` (including moving `pipeline_stage_id`), `destroy`. Manual creation requires `contact_id` + `pipeline_stage_id` in params; `origin_conversation_id` is optional and, if present, only settable at `create` time (the controller MUST reject any attempt to change `origin_conversation_id` on `update`).

**FR-009**: `Api::V1::Accounts::PipelineStagesController` MUST support `index`, `create`, `update` (name/position), `destroy` — admin-only per FR-007.

**FR-010**: Two additive migrations MUST be created in `db/migrate/` (Rails does not support loading migrations from any path other than `db/migrate/`, so this is the one unavoidable exception to "everything lives in `custom/`"): `create_matias_pipeline_stages` and `create_matias_opportunities`. Both must be fully reversible (`drop_table` on `down`). Neither migration touches any existing core table (`conversations`, `contacts`, etc.).

**FR-011**: `Contact has_many :opportunities` MUST be added without editing `app/models/contact.rb`. Confirmed technique: `app/models/contact.rb` already ends with `Contact.include_mod_with('Concerns::Contact')`. Create `custom/app/models/custom/concerns/contact.rb` defining `module Custom::Concerns::Contact; extend ActiveSupport::Concern; included do has_many :opportunities, dependent: :destroy end; end`. This is auto-discovered by the existing `include_mod_with` call — zero edits to `contact.rb`.

**FR-012**: A new non-premium feature flag entry (e.g. `opportunities`) MUST be added to `config/features.yml`, following the same shape as the existing `MACROS` flag. This gates visibility of the Pipeline Stages settings screen and the Opportunities API (out of scope for this phase's UI, but the flag plumbing belongs here since it's backend config).

## Out of Scope (this phase)

- Automatic Opportunity creation via Automation Rules (Phase 2).
- Any Vue/frontend code (Phase 3).
- Realtime broadcast of Opportunity changes (Phase 4).
- Multiple pipelines per account (single implicit pipeline via `PipelineStage.account_id` only).
- Reassigning `origin_conversation_id` after creation.

## Completion Criteria

This phase has no UI — verify entirely via `docker compose exec rails rails console` (or `rails runner`) and request specs, run inside the `rails` container.

1. **Migration runs cleanly**:
   ```
   docker compose exec rails bundle exec rails db:migrate
   docker compose exec rails bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?('matias_opportunities')"
   docker compose exec rails bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?('matias_pipeline_stages')"
   ```
   Both must print `true`. Then confirm reversibility: `docker compose exec rails bundle exec rails db:rollback STEP=2` followed by `docker compose exec rails bundle exec rails db:migrate` succeeds without error.

2. **`custom/` autoloading works** (proves FR-001 wiring is correct):
   ```
   docker compose exec rails bundle exec rails runner "puts Opportunity"
   docker compose exec rails bundle exec rails runner "puts PipelineStage"
   ```
   Both must resolve without `NameError`.

3. **Model + association sanity** (proves FR-002–FR-004, FR-011), run inside `docker compose exec rails rails console`:
   ```ruby
   account = Account.first
   contact = account.contacts.first
   stage = account.pipeline_stages.create!(name: "Leads Recebidos", position: 0)
   opp = Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: "Teste")
   puts opp.persisted?          # true
   puts contact.opportunities.include?(opp)   # true — proves FR-011 without touching contact.rb
   ```

4. **Lazy seed** (FR-005): on an account with zero `PipelineStage` rows, `GET /api/v1/accounts/:id/pipeline_stages` (e.g. `docker compose exec rails curl -s http://localhost:3000/api/v1/accounts/:id/pipeline_stages -H "..."`, or the equivalent service call run inside `docker compose exec rails rails console`) must create exactly the two default stages and return them, and a second call must NOT create duplicates.

5. **Policy enforcement** (FR-006): `docker compose exec rails bundle exec rspec spec/policies/opportunity_policy_spec.rb` — cover admin (full access), assignee-agent (access), unrelated-agent-with-no-conversation-access (denied).

6. **API contract** (FR-008, FR-009): `docker compose exec rails bundle exec rspec spec/requests/api/v1/accounts/opportunities_controller_spec.rb spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb` — CRUD paths pass, including the FR-008 rejection test (`update` with a changed `origin_conversation_id` must not change the persisted value).

7. **Cross-account guard** (FR-004): attempting to create an `Opportunity` with a `pipeline_stage` from a different account must raise a validation error, verified via a model spec.
