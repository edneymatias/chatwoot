# Research: Scout Opportunity Value Estimation

No `NEEDS CLARIFICATION` markers remain in the Technical Context — the feature's source design
doc (`docs/kanban/ciclo 10/scout/26-scout-opportunity-value-estimation/spec91.md`) and the two
`/speckit-clarify` answers already settled every open decision. This document records the
investigation that grounds those decisions in the actual codebase, so Phase 1 design and
`/speckit-tasks` can proceed without re-deriving them.

## Decision: Reuse the `any_of`/`null` RubyLLM::Schema pattern for the classifier's optional enum

- **Rationale**: `Custom::Scout::ActionClassifierSchema`
  (`custom/app/services/custom/scout/action_classifier_schema.rb`) already solves the exact same
  problem — OpenAI's Structured Outputs strict mode rejects a plain `required: false` string
  field, so the gem's documented workaround is `any_of` with a `string enum:` branch and a `null`
  branch, keeping the field required while allowing null. `Custom::Scout::ReferralInterestClassifierSchema`
  reuses this verbatim, parameterized by the Scout's own `interest_attribute_definition.attribute_values`
  instead of a fixed constant list (via a `self.for_options(options)` class factory, since the
  valid options differ per account).
- **Alternatives considered**: A boolean `identified` flag plus a separate string field — rejected,
  it duplicates what `any_of`/`null` already expresses in one field and diverges from the
  established pattern for no benefit.
- **Verified 2026-09-11** (codebase stress-test + context7 + gh_grep): CONFIRMED WITH CAVEATS.
  - The `any_of`/`null` idiom is the gem's own canonical, documented pattern (`crmne/ruby_llm-schema`
    README; `schematist` specs cover the exact `any_of` + `enum` + `null` shape, including class
    inheritance). It's also the pattern the gem's *own* codebase and `ruby_llm`'s tool-parameter DSL
    use internally — not a fork-specific workaround.
  - `Class.new(self) { ... }` for the dynamic `for_options(options)` factory is mechanically
    identical to the gem's internal `Schema.create(&block)` (`Class.new(Schema); class_eval(&block)`)
    and each anonymous subclass gets its own isolated `@properties`, so concurrent classification
    calls across different accounts/option sets never collide. This is a reasonable extrapolation of
    the gem's documented "Class Inheritance"/"Factory Method" mechanisms, not a literally-documented
    recipe — acceptable given it mirrors the gem's own implementation.
  - **Caveat (minor, worth fixing during implementation)**: `with_schema(SchemaClass)` calls
    `SchemaClass.new` with no arguments, and `Schema#initialize` defaults `@name` to
    `self.class.name || "Schema"`. An anonymous class from `Class.new(self)` has `self.class.name ==
    nil`, so the schema sent to the LLM provider is named generically `"Schema"` instead of something
    traceable like `"ReferralInterestClassifierSchema"`. Harmless functionally, but a small
    observability loss — pass an explicit `name:` when instantiating for `with_schema` if the gem's
    `Schema#initialize` accepts one (confirm during implementation task).
  - **Caveat (accepted latent debt, not actionable now)**: the installed `ruby_llm-schema` is
    `0.3.0` (pre-2.0); `with_params(temperature:)` and `RubyLLM::Schema` are both still correct for
    this version. The gem's `main`-branch docs already describe a 2.0 rename
    (`with_temperature`, `Schematist::Schema`) that would require updating every existing classifier
    (including `ActionClassifierSchema`, unrelated to this feature) on a future upgrade — noted here
    for awareness, no action needed for this feature.

## Decision: Run ad-content classification synchronously at Opportunity-creation time

- **Rationale**: `Custom::Scout::Tools::ManageOpportunity#create_opportunity`
  (`custom/app/services/custom/scout/tools/manage_opportunity.rb:53-66`) already performs a
  synchronous `Custom::ReferralAttributionService.process(opp, referral_message)` call in the same
  code path right after creation. Adding one more synchronous LLM call
  (`Custom::Scout::ReferralInterestClassifierService#classify`) at the same call site keeps the
  guarantee spec Success Criterion SC-002 requires — the value must be populated *before* the lead
  sends a first reply, which only holds if classification finishes before `create_opportunity`
  returns.
- **Alternatives considered**: Deferring classification to a background job — rejected: it
  reintroduces exactly the race SC-002 exists to prevent (a fast-replying lead could get a
  qualification question before classification lands), and there is no existing precedent for
  making Scout tool calls partially asynchronous.
- **Verified 2026-09-11** (codebase stress-test): CONFIRMED, but the precedent cited above needed
  correction. `Custom::ReferralAttributionService.process` *is* a synchronous call at the same call
  site, but it does **not** itself make an LLM call — it only parses and persists referral payload
  fields. It's evidence that a second synchronous step at this call site is architecturally normal,
  not evidence that a synchronous *LLM* call specifically is already tolerated there.
  The real precedent for a synchronous LLM call within the same execution is
  `Custom::Scout::ActionClassifierService`, invoked via `Custom::Scout::ResponseAuditor` inside
  `Custom::Scout::AgentRunner#process_audited_reply`
  (`custom/app/services/custom/scout/agent_runner.rb:68,85`) — after the main chat reply, in the
  same job run. More importantly: `ManageOpportunity`'s entire execution happens inside
  `Custom::Scout::ProcessMessageJob` → `Custom::Scout::AgentRunner#perform`, a debounced **Sidekiq
  job**, not a synchronous web request or webhook handler. So there is no HTTP response deadline at
  risk from adding one more LLM call here — only the job's own overall latency budget, which already
  accommodates a second synchronous LLM call (the response-auditor classification) later in the same
  run.

## Decision: Store `interest_attribute_definition_id` and `value_by_interest` directly on `ichatr_scouts`

- **Rationale**: Confirmed against `db/migrate/21260910145200_add_audience_to_ichatr_scouts.rb`,
  which added a `jsonb` `audience` column directly to `ichatr_scouts` for a similarly small,
  Scout-scoped configuration blob. The new `interest_attribute_definition_id` FK
  (`belongs_to :interest_attribute_definition, class_name: 'CustomAttributeDefinition', optional: true`,
  `on_delete: :nullify`) and `value_by_interest` jsonb column (`{ option => value }`) follow the
  same shape. `CustomAttributeDefinition#attribute_values` (jsonb) already stores a `list`
  attribute's fixed option set (`app/models/custom_attribute_definition.rb`), confirming the
  option strings the value table keys off of already exist and don't need to be duplicated
  elsewhere.
- **Alternatives considered**: A separate `ScoutValueMapping` model/table with one row per
  option → rejected per the source doc's explicit design decision ("uma única tabela de dinheiro
  ... sem duplicar configuração") — a plain jsonb hash is materially simpler than a full
  CRUD-backed association for what is, in practice, a short static price list per Scout.
- **Verified 2026-09-11** (codebase stress-test + context7 + gh_grep): CONFIRMED WITH CAVEAT on
  migration mechanics; the jsonb-on-parent shape itself is well-supported prior art.
  - `on_delete: :nullify` combined with an `optional: true` `belongs_to` is an established idiom
    both in this fork (5 prior occurrences in `db/migrate/`, e.g.
    `21260819000001_create_ichatr_scouts.rb`) and in the wild (extensively used in
    `mastodon/mastodon`, no reported gotchas found). A small jsonb config hash directly on a parent
    row (vs. a normalized child table) is likewise idiomatic Rails, confirmed in production
    codebases (`forem/forem`, `discourse/discourse`, `loomio/loomio`, `maybe-finance/maybe`) —
    though none of those is an exact "value-by-option price map" analog; the closest exact analog
    remains this fork's own `audience` jsonb column.
  - **Caveat requiring a design correction**: this repo's `add_reference` calls (all 4 of them,
    across every migration) never combine `foreign_key: { to_table:, on_delete: }` inline the way
    the source doc's migration snippet does — every `add_reference`/`add_column` that needs a
    foreign key follows a **two-statement** idiom: add the column/reference first, then a separate
    `add_foreign_key :ichatr_scouts, :custom_attribute_definitions, on_delete: :nullify` (see
    `21260907000000_add_rescue_stage_and_follow_up_delays_to_ichatr_scouts.rb`, which does exactly
    this for `rescue_stage_id`). The inline `foreign_key: { to_table:, on_delete: }` form is Rails-
    valid (confirmed against the official Rails 7.2 migration guide) and *is* used elsewhere in this
    repo, but only via `t.references` inside `create_table` blocks for brand-new tables — never via
    a standalone `add_reference` altering an existing table. Since this feature alters the existing
    `ichatr_scouts` table, the migration must follow the two-statement idiom to match established
    convention (Constitution Principle III), not the source doc's condensed one-statement example.
  - **Caveat, version marker**: the source doc's migration snippet used
    `ActiveRecord::Migration[7.1]`. The actual installed Rails is `7.2.3.1` (`Gemfile.lock`), but
    this repo does not consistently bump migration version markers to match — the two most recent
    prior migrations touching `ichatr_scouts` both use `ActiveRecord::Migration[7.0]`
    (`add_audience_to_ichatr_scouts.rb`, `add_rescue_stage_and_follow_up_delays_to_ichatr_scouts.rb`).
    For minimal diff and consistency with that migration family, this feature's migration should
    also use `ActiveRecord::Migration[7.0]`, not `[7.1]`.

## Decision: One centralized sync point (`Custom::Scout::ValueEstimationService#sync!`)

- **Rationale**: The spec's Assumptions/Clarifications require the lookup to be deterministic and
  never dependent on the calling code remembering to re-run it. Centralizing the
  attribute-key → value-table lookup in one service, called from both
  `create_opportunity` (after auto-classification) and `apply_opportunity_fields` (the update
  path used whenever `custom_attributes` change, including the lead's own qualification answer),
  guarantees both call sites in `ManageOpportunity` stay in sync automatically as the tool
  evolves.
- **Alternatives considered**: Inlining the table lookup separately in both call sites — rejected,
  duplicated logic that would silently drift if only one call site were updated later.
- **Verified 2026-09-11** (codebase stress-test): CONFIRMED, no conflicting callback exists.
  `Opportunity`'s only relevant callback is `before_save :reset_closing_required_attributes,
  if: :status_changed?` (`custom/app/models/opportunity.rb:88-101`), which only clears
  `PipelineClosingRequiredField`-configured attributes when reopening a `won`/`lost` deal back to
  `open` — it doesn't run on the `custom_attributes`-merge path this feature hooks into, and
  `sync!` runs as a plain pre-`save!` method call, not a model callback, so there's no ordering
  ambiguity between the two. **Edge case noted but explicitly out of scope**: if an admin ever
  configures the same custom attribute as both this feature's "interest" attribute *and* a
  pipeline-closing required field, a simultaneous reopen + interest update in one call could see
  `reset_closing_required_attributes` clear the value `sync!` just set. This combination isn't
  covered by the spec and doesn't change this feature's design; it's a candidate for a future
  edge-case spec if it ever proves to matter in practice.

## Decision: Enforce "list-type only" at both the config UI and the data layer

- **Rationale**: Per the `/speckit-clarify` answer, the Scout settings screen (extending
  `ScoutFunnelTab.vue`, which already filters `customAttributes` by `attribute_model` for the
  existing required-fields picker) must only offer `attribute_display_type === 'list'` attributes
  as selectable "interest" options — this is the same filtering pattern already used for
  `qualificationAttributes` in that component, just with an additional type predicate.
- **Alternatives considered**: No restriction, silent no-op for non-list types — explicitly
  rejected by the clarification answer as it lets an admin configure something that can never
  work with no feedback.
- **Verified 2026-09-11** (codebase stress-test): CONFIRMED, no backend change needed to support
  the filter. `attribute_display_type` and `attribute_values` are already serialized in
  `app/views/api/v1/models/_custom_attribute_definition.json.jbuilder` and already reach the Vuex
  `attributes` store `ScoutFunnelTab.vue` reads from — the proposed frontend-only filter
  (`attribute_display_type === 'list'`, alongside the existing `attribute_model` predicate) is
  fully viable with data already on hand.

## Decision: Treat classification failures identically to "not identified"

- **Rationale**: Per the `/speckit-clarify` answer, a technical failure (LLM error, timeout) must
  produce the same outcome as an inconclusive classification: no automatic value, normal
  conversation flow, engineer-only visibility. `Custom::Scout::ActionClassifierService` already
  establishes this exact pattern — `rescue StandardError => e` →
  `ChatwootExceptionTracker.new(e, account: @scout.account).capture_exception` → return a
  not-identified-equivalent result. `Custom::Scout::ReferralInterestClassifierService#classify`
  reuses it directly (rescue → track exception → return `nil`, same as an inconclusive answer).
- **Alternatives considered**: Retry-then-give-up, or surfacing a visible flag to the admin — both
  explicitly rejected by the clarification answer in favor of silent parity with "not identified".
- **Verified 2026-09-11** (codebase stress-test): CONFIRMED exact match. `ChatwootExceptionTracker`'s
  real signature is `initialize(exception, user: nil, account: nil)`; `ActionClassifierService`
  already calls it exactly as `ChatwootExceptionTracker.new(e, account: @scout.account).capture_exception`,
  which is precisely the call `ReferralInterestClassifierService#classify` reuses.

## Verification Summary (2026-09-11)

Three independent passes stress-tested every decision above: (1) a fresh re-read of the actual
codebase (not the paraphrase in this document), (2) official documentation via context7 for the
`ruby_llm`/`ruby_llm-schema` gems and Rails migrations, (3) a GitHub-wide search for prior art.
**Net result: all 6 decisions confirmed.** Two corrections were required and are folded into the
decisions above rather than listed separately:

1. The synchronous-classification decision cited the wrong precedent for "an LLM call already
   runs synchronously here" — corrected to `ActionClassifierService`/`ResponseAuditor`, and
   clarified that the call site is a Sidekiq job, not a web request (no HTTP timeout at stake).
2. The migration design in the source doc's snippet used an inline `foreign_key: {...}` form and
   an `ActiveRecord::Migration[7.1]` marker that don't match this repo's actual convention for
   `add_reference` on an existing table or for the `ichatr_scouts` migration family — corrected to
   the two-statement idiom and `[7.0]` marker. `data-model.md`/`plan.md`'s migration file entry
   should follow the corrected form; no consumer of this research document needs further changes.

One accepted, non-blocking caveat carried forward into implementation tasks: give the dynamically
built classifier schema an explicit `name:` (instead of leaving it to default to the generic
`"Schema"`) for instrumentation traceability, matching the descriptive names already used by
`ActionClassifierSchema` and other static schemas.
