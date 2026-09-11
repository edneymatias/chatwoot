# Phase 0 Research: Scout Commercial Configuration UI

Each decision below resolves a "how do we build this" question left open by the spec (which is
intentionally implementation-agnostic). Nothing here contradicts `spec.md`; it grounds the spec's
requirements in this fork's existing conventions and the Scout backend already shipped in Phases
01-04.

## 1. Where does "qualification fields" data live?

**Decision**: Reuse the existing `CustomAttributeDefinition` + join-table pattern already used by
`PipelineStage.required_custom_attribute_definitions` (table `ichatr_pipeline_stage_required_fields`,
controller helper `sync_required_attributes` in `PipelineStagesController`). Add a new join table
`ichatr_scout_required_fields` (`scout_id`, `custom_attribute_definition_id`, `account_id`) with the
same shape.

**Rationale**: `Scout` has no `qualification_fields` column today (spec60.md's draft field list was
trimmed in the actual Phase 01 migration — confirmed via `db/schema.rb`). Qualification attributes
("Dor principal", "Orçamento estimado", etc.) are conceptually identical to a `PipelineStage`'s
required fields — an admin picks from the account's existing `CustomAttributeDefinition` records.
Reusing the exact pattern already proven in `PipelineStagesController` is the smallest
production-ready change and stays internally consistent (one way to model "required attributes"
in this fork, not two).

**Alternatives considered**: A `jsonb` array of free-text field names on `Scout` — rejected because
it would duplicate `CustomAttributeDefinition` instead of reusing it, and would not integrate with
however qualification data ends up captured on the `Opportunity`/`Contact` (native tools already
write to custom attributes via `UpdateContact`/`ManageOpportunity`, per Phase 02).

**Confirmed divergences from the `PipelineStageRequiredField` precedent** (verified by re-reading
`custom/app/models/pipeline_stage_required_field.rb`/`pipeline_stage.rb`, must be stated explicitly
rather than assumed identical):
- `PipelineStageRequiredField` validates `custom_attribute_definition.attribute_model ==
  'Opportunity'` (an admin cannot require a Contact-scoped attribute on a stage). `ScoutRequiredField`
  needs its own explicit eligibility rule instead of silently inheriting this one — Scout's
  qualification fields plausibly need to allow `attribute_model == 'Contact'` too (native tools write
  qualification data to both Contact and Opportunity, per Phase 02), so the validation should permit
  both `Contact` and `Opportunity`, not restrict to `Opportunity` only.
- `PipelineStageRequiredField` enforces **account-wide exclusivity** on the underlying unique index
  (one `CustomAttributeDefinition` can be required by at most one `PipelineStage` at a time).
  `ScoutRequiredField`'s currently-planned unique index is `(scout_id,
  custom_attribute_definition_id)` only, which allows the same attribute to be required by multiple
  Scouts simultaneously. This is an intentional divergence, not an oversight: Scouts are independent
  qualification flows (unlike pipeline stages, which are steps of one shared funnel), so reuse across
  Scouts is the correct behavior — stated here explicitly so it isn't mistaken for a bug during
  implementation.

## 2. Where does knowledge base data live (URLs, documents, FAQs)?

**Decision**: Promote `knowledge_sources` from the existing `jsonb` column on `Scout` to a proper
table, `ichatr_scout_knowledge_sources` (`scout_id`, `account_id`, `kind` enum
`url`/`document`/`faq`, `url`, `question`, `answer`, `status` enum `pending`/`ready`/`failed`,
`error_message`, plus an `ActiveStorage` `document_file` attachment for the `document` kind).
Processing (crawl / PDF extraction) runs in a background job that transitions `status`.

**Rationale**: FR-004's edge cases (failed crawl/processing must show an error state, not silently
drop the source) and the upload constraint clarified during `/speckit-clarify` (PDF only, 10MB max,
mirroring `Captain::Document`) both need per-entry status tracking and a real file attachment —
neither fits cleanly in a `jsonb` array. `Captain::Document` (`enterprise/app/models/captain/document.rb`)
already solves this exact problem (PDF attachment validation, `perform_sync_job`/`crawl_job`
pattern) and is the closest existing precedent in the codebase; mirroring its shape (new table +
`ActiveStorage` + background job) is more consistent than force-fitting file storage into a jsonb
blob.

**Alternatives considered**: Keep `knowledge_sources` as `jsonb` and store an `ActiveStorage`
attachment reference by key inside the JSON — rejected as unnecessarily indirect and harder to
query/validate than a normal association; Rails' `ActiveStorage` is designed to attach to a real
`ActiveRecord` row.

**Confirmed against `enterprise/app/jobs/captain/documents/crawl_job.rb`**: Captain's real
processing pipeline is more elaborate than "one job" — it branches into a PDF path
(`Captain::Llm::PdfProcessingService`), a Firecrawl path (gated by an `InstallationConfig` API key,
an Enterprise/licensing-flavored concept), and a fallback simple-crawl path that fans out into
per-page jobs (`Captain::Tools::SimplePageCrawlService` → `Captain::Tools::SimplePageCrawlParserJob`).
Scout's `Scout::KnowledgeSources::ProcessJob` (custom/) must **not** call these `Captain::*` classes
directly — they live under `enterprise/`, assume Enterprise-only concerns (plan/usage limits,
`InstallationConfig`), and would create a hard runtime dependency on Enterprise being loaded, which
this fork's `custom/` tree must not have. Scout should implement its own minimal single-job
processing (PDF text extraction for `document`, a single-page fetch for `url`, no Firecrawl/no
multi-page crawl fanout) under `custom/`, mirroring only the *status-tracking pattern*
(pending→ready/failed), not Captain's crawl architecture. Single-page fetch (not a multi-page
crawler) is the correct scope for FR-004 as specified — matches Principle II.

**Required follow-up not yet in `plan.md`**: `custom/app/services/custom/scout/agent_runner.rb:85`
currently reads `@scout.knowledge_sources` as a jsonb hash to build RAG context. Once this decision
ships, that line must be updated to read from the new `ScoutKnowledgeSource` association
(`where(status: :ready)`) instead — otherwise the LLM silently stops receiving knowledge-base
context after this migration. This must be an explicit task in `/speckit-tasks`, not an incidental
side effect of the migration.

## 3. Where does product catalog data live?

**Decision**: Keep `product_catalog` as the existing `jsonb` array column on `Scout`. Each entry
gets a server-generated UUID (`SecureRandom.uuid`) so individual add/edit/remove operations (FR-003)
can address one entry without re-sending the whole array. No new table.

**Rationale**: Product entries are plain structured data (name, price/plan text, value-prop
summary) with no file upload, no async processing, and no need for relational queries across
Scouts — the exact profile `jsonb` is a good fit for, and the column already exists from Phase 01.
Adding a table here would be a heavier change than the requirement justifies (Principle II,
Smallest Production-Ready Change).

**Alternatives considered**: A dedicated `ichatr_scout_products` table, matching the knowledge-base
approach — rejected as unnecessary complexity given the No. 2 decision above hinges on file/async
concerns that don't apply here.

## 4. How does the Playground avoid creating/mutating real Chatwoot records?

**Decision (revised)**: Add `Scout::PlaygroundRunner`, reusing `Scout::AgentRunner`'s context-building
and tool-dispatch internals, but **not** by feeding it unpersisted `Contact.new`/`Conversation.new`
objects. Instead, thread an explicit `playground: true` flag through `AgentRunner#perform` and each
mutating native tool's `#call`. Each mutating tool (`CreatePrivateNote`, `UpdateContact`,
`ManageOpportunity`, `MoveOpportunityStage`, `HandoverToHuman`) checks the flag and, when true, skips
its `.save!`/`.create!`/`.update!` call entirely, returning a simulated/echoed result shaped exactly
like its real return value (e.g. `{ note: "...", persisted: false }`) instead. `CallCustomApi` is
untouched and always performs the real external call, per the clarified spec behavior.
`AgentRunner#perform`'s existing `conversation_pending?` gate (`agent_runner.rb:16`,
`agent_runner.rb:33-35`) must also be bypassed under `playground: true`, since there is no real
conversation to check the status of.

**Rationale for the revision**: The originally-considered "unpersisted ActiveRecord objects" approach
is unsafe. Rails' `belongs_to` associations autosave an unpersisted associated record the moment the
owning record is saved (e.g. assigning `note.conversation = Conversation.new` and then calling
`note.save!` will silently `INSERT` the unpersisted `Conversation` too). Several native tools call
`.save!`/`.create!` directly on objects reachable from the fed-in unpersisted conversation/contact,
so an unpersisted-object approach cannot actually guarantee "no real record is created" — it depends
on no tool ever triggering an autosave, which is not a property the codebase enforces or tests today
and would silently break as tools evolve. An explicit `playground: true` branch in each tool is the
only approach that provides an actual, auditable guarantee: no tool contains a code path that can
call `.save!` when the flag is set.

**Alternatives considered**: A permanent hidden "sandbox" `Contact`/`Conversation` per Scout,
reused across Playground sessions — rejected because it leaves real (if hidden) rows behind that
need their own lifecycle/cleanup story, and native tools writing to a hidden-but-real Opportunity
could still surface in reports/automations. Feeding unpersisted ActiveRecord objects (the original
decision) — rejected per the Rationale above; superseded by the explicit-flag approach.

## 5. How is the Scout primary-menu section gated and does an inbox belong to only one Scout?

**Decision**: Add `FEATURE_FLAGS.SCOUT` (mirroring `FEATURE_FLAGS.OPPORTUNITIES`, an
account-level flag toggled the same way as this fork's existing Kanban module — not Captain's
plan-gated `PREMIUM_FEATURES` style) to gate the "Scout" sidebar entry and its routes.
`ScoutInbox` keeps its existing unique index on `inbox_id` (`ichatr_scout_inboxes`), so an inbox can
be attached to at most one Scout at a time; the inbox-association UI (FR-002) must surface and block
attaching an inbox that is already linked to a different Scout, offering to move it instead.

**Rationale**: This fork already has a working, non-Captain precedent for a new primary-menu module
(`Opportunities`, gated by `FEATURE_FLAGS.OPPORTUNITIES`, wired directly into
`dashboard.routes.js` and `Sidebar.vue`) — Scout should follow that pattern instead of Captain's
enterprise-licensing-flavored one, since Scout is a fork-owned feature like Opportunities, not an
upstream Enterprise feature. The one-Scout-per-inbox constraint already exists at the DB level from
Phase 01; the UI must respect it rather than silently failing on a unique-index violation.

**Alternatives considered**: Mirror Captain's `PREMIUM_FEATURES`/installation-type gating exactly —
rejected because Scout has no licensing/plan dimension in this fork (per spec60.md §6, BYOK today,
no billing), so that machinery would be dead weight.

**Confirmed backend registration requirement (was missing from `plan.md`)**: `FEATURE_FLAGS.OPPORTUNITIES`
is not solely a frontend constant — it is backed by a `config/features.yml` entry consumed by the
`Featurable`/`FlagShihTzu` bitfield concern, exposed to the frontend via
`Account#enabled_features`/`all_features`, and read by `isFeatureEnabledonAccount`
(`app/javascript/dashboard/store/modules/accounts.js`). A `scout` entry must be added to
`config/features.yml` (e.g. `- name: scout, display_name: Scout, enabled: false`) as part of this
feature's backend work — this was absent from `plan.md`'s Project Structure and must be added as an
explicit task.

## 6. Backend routing/controller conventions

**Decision**: New controllers live under `custom/app/controllers/api/v1/accounts/`, following the
exact shape of `PipelineStagesController`: subclass `Api::V1::Accounts::BaseController`, use
`Current.account` scoping, `check_authorization` + a `*Policy` class under `custom/app/policies/`,
strong params via `permit`, and `render json:` (no Jbuilder views used elsewhere in `custom/`).
Routes are added to the existing fork-owned block in `config/routes.rb` (the only new-file location
outside `custom/`, consistent with the constitution's migration exception for fixed Rails
locations).

**Rationale**: Every existing fork-owned controller (`PipelineStagesController`,
`OpportunitiesController`, etc.) already follows this shape; introducing a different one (e.g.
Jbuilder, GraphQL) for Scout alone would be inconsistent with Principle III (Adhere to Established
Conventions).

**Alternatives considered**: None seriously considered — this is a direct continuation of an
established, unambiguous local pattern.
