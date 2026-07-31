# Phase 0 Research: Kanban Backend Core

All items below were resolved either by direct repository inspection (this is an established
Rails codebase with existing conventions to mirror, not a greenfield technology choice) or by the
`/speckit-clarify` session already run against `spec.md`. No open `NEEDS CLARIFICATION` markers
remain.

## 1. `custom/` autoloading wiring (FR-001)

- **Decision**: Add exactly the same three lines used for `enterprise/` in
  `config/application.rb`, targeting `custom/lib` and `custom/app/**`:
  ```ruby
  config.eager_load_paths << Rails.root.join('custom/lib')
  config.eager_load_paths += Dir["#{Rails.root}/custom/app/**"]
  ```
  (No `custom/listeners`, `custom/config/initializers`, or `custom/app/views` wiring — this
  phase has no listeners, initializers, or views.)
- **Rationale**: `config/application.rb:43-53` shows the exact existing pattern for
  `enterprise/`; reusing it verbatim is the smallest possible core-file edit (constitution
  Principle I) and guarantees Zeitwerk autoloads `custom/app/models`, `custom/app/policies`,
  `custom/app/controllers` the same way it already autoloads `enterprise/app/**`.
- **Alternatives considered**: A Rails Engine (`custom/` as a mountable engine) — rejected as
  disproportionate engineering for a same-repo, same-database feature; Chatwoot's own
  `enterprise/` overlay does not use an Engine, so an Engine would be an inconsistent pattern.

## 2. Reusing `Contact` association without editing `contact.rb` (FR-011)

- **Decision**: `app/models/contact.rb` already ends with
  `Contact.include_mod_with('Concerns::Contact')`. Define
  `custom/app/models/custom/concerns/contact.rb`:
  ```ruby
  module Custom::Concerns::Contact
    extend ActiveSupport::Concern
    included do
      has_many :opportunities, dependent: :destroy
    end
  end
  ```
- **Rationale**: Confirmed by reading `app/models/contact.rb` directly — the `include_mod_with`
  call already exists and is unwired to any current module, so this is a zero-edit extension
  point exactly as described in the source design doc.
- **Alternatives considered**: Editing `contact.rb` directly to add `has_many :opportunities` —
  rejected, violates constitution Principle I (touching a core file that upstream also edits
  regularly would create recurring merge conflicts).

## 3. Feature flag shape and per-account activation (FR-012, clarified)

- **Decision**: Add to `config/features.yml`:
  ```yaml
  - name: opportunities
    display_name: Opportunities (Kanban)
    enabled: true
    column: feature_flags_ext_1
  ```
  Per `config/features.yml`'s own header comment, the main `feature_flags` column is full
  (63/63 slots) — new flags MUST use `column: feature_flags_ext_1`. `enabled: true` makes the
  flag available platform-wide by default (not premium-gated), matching the clarified answer:
  the *flag* is on by default, but the *functionality* only activates per-account once the
  account's `feature_flags_ext_1` bit for `opportunities` is actually turned on via the standard
  `Account#enable_features!`/`disable_features!` (from `app/models/concerns/featurable.rb`).
  Toggling off simply stops matching `Current.account.feature_enabled?('opportunities')` checks
  in controllers/policies — no data is deleted, so reactivating immediately resumes with prior
  Pipeline Stages/Opportunities intact, satisfying the clarified reactivation behavior with zero
  extra code (the existing bitset toggle already behaves this way for every other flag).
- **Rationale**: Reuses the existing `Featurable` concern exactly as every other optional feature
  in the app already does (e.g. `branded_email_templates`, `captain_tasks` per
  `app/models/concerns/account_captain_auto_resolve.rb` and
  `app/models/concerns/inbox_branded_email_layoutable.rb`) — no new activation mechanism needed.
- **Alternatives considered**: A bespoke `custom_settings` JSON column on `Account` for
  activation — rejected as unnecessary duplication of the already-existing, already-conventional
  feature-flag bitset mechanism.

## 4. Admin-only policy pattern (FR-007, PipelineStagePolicy)

- **Decision**: Mirror `app/policies/custom_attribute_definition_policy.rb` exactly — every
  action (`index?`, `show?`, `create?`, `update?`, `destroy?`) delegates to
  `@account_user.administrator?`.
- **Rationale**: Confirmed by reading the file directly; it is the closest existing analogue
  (admin-only Settings-style resource).

## 5. Reusing conversation-access scoping for `OpportunityPolicy` (FR-006)

- **Decision**: `OpportunityPolicy` grants access when `@account_user.administrator?`, or
  `record.assignee_id == user.id`, or (when `record.origin_conversation_id.present?`) delegating to
  `Pundit.policy!(user, opportunity.origin_conversation).show?`, which reuses
  `ConversationPolicy#show?` (already covering administrator, agent bot, inbox access, and team
  access) as a public entry point.
- **Rationale**: `app/policies/conversation_policy.rb` implements `inbox_access?` and
  `team_access?` as private instance methods; FR-006 explicitly says "reused, not reimplemented."
  `Pundit.policy!(user, record)` is the standard Pundit mechanism for invoking another model's
  policy publicly, so delegating to `ConversationPolicy#show?` satisfies FR-006 with zero edits to
  `conversation_policy.rb` and no duplication of its private access-check logic.
- **Alternatives considered**: Reimplementing inbox/team lookups inline in `OpportunityPolicy` —
  rejected per FR-006's explicit instruction and constitution Principle II (avoid duplicating
  existing logic).

## 6. Controller/route shape (FR-008, FR-009)

- **Decision**: Nest both resources under the existing `resources :accounts` member block in
  `config/routes.rb` (same block containing `resources :macros`, `resources
  :custom_attribute_definitions`), as standard RESTful resources:
  ```ruby
  resources :pipeline_stages, only: [:index, :create, :update, :destroy]
  resources :opportunities, only: [:index, :show, :create, :update, :destroy]
  ```
- **Rationale**: Matches the existing nested-under-account API shape used throughout
  `app/controllers/api/v1/accounts/*`; both controllers inherit from
  `Api::V1::Accounts::BaseController` per FR-008/FR-009's controller paths.

## 7. Migration mechanics (FR-010)

- **Decision**: Two standard `create_table` migrations under `db/migrate/`, using the current
  schema version (`db/schema.rb` is at `2026_07_28_000001`) as the floor for new migration
  timestamps. Both use plain `create_table` (implicitly reversible) — no custom `up`/`down`
  needed.
- **Rationale**: `create_table` migrations are reversible via Rails' automatic inverse
  (`drop_table`) without hand-written `down` blocks, satisfying FR-010's reversibility
  requirement with the least code.

## 8. Position auto-assignment (FR-002, clarified)

- **Decision**: `PipelineStage.create!` computes `position` server-side as
  `account.pipeline_stages.maximum(:position).to_i + 1` when not explicitly provided (only the
  lazy-seed path and any future reorder feature would set it explicitly); the `create` API
  parameter list for `PipelineStagesController` does not require callers to pass `position`.
- **Rationale**: Directly reflects the clarified answer (auto-append to end; explicit reordering
  deferred).
