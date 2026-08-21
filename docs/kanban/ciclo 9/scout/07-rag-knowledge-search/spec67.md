# Phase 07 — RAG Knowledge Search (Embeddings)

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §7.2, §11
**Depends on**: Phase 01 (`ScoutKnowledgeSource` model/pipeline), Phase 02 (native tool pattern to
follow for the new retrieval tool), Phase 06 (`docs/kanban/ciclo 10/scout/06-account-llm-config/spec70.md`
— account-level `ScoutAccountConfig`, now complete).

## Goal

Replace blind full-content prompt injection of the knowledge base with on-demand semantic search
(RAG), inspired by Chatwoot's own Captain feature (`enterprise/app/models/captain/assistant_response.rb`,
`enterprise/lib/captain/tools/faq_lookup_tool.rb` — read-only reference, not reused/copied per
§3 licensing guidelines).

## This is a refactor, not new ground

The knowledge extraction pipeline already exists and ships unchanged from Phase 01/02. Nothing
below duplicates it:

- `ScoutKnowledgeSource` (`custom/app/models/scout_knowledge_source.rb`, table
  `ichatr_scout_knowledge_sources`) — `kind` enum (`url`/`document`/`faq`), `status` enum
  (`pending`/`ready`/`failed`), validations, `reprocess!` (extended below). **Otherwise unchanged.**
- `Custom::Scout::KnowledgeSources::ProcessJob` (`custom/app/jobs/custom/scout/knowledge_sources/process_job.rb`)
  — `process_url` (HTTParty + Html2Text), `process_document` (PDF text extraction), `process_faq`.
  Populates `ScoutKnowledgeSource#content` and sets `status: :ready`. Text extraction itself is
  **unchanged**; this phase adds embedding-generation calls at the point each `process_*` method
  reaches `status: :ready` (see Scope below).
- Phase 05 commercial UI (`05-commercial-ui/spec66.md` §7.2, "Base de Conhecimento Comercial") —
  the URL/document/FAQ management screens. **Unchanged.**

What actually gets refactored/removed:

- `Custom::Scout::AgentRunner#build_knowledge_instructions` and `#format_knowledge_source`
  (`custom/app/services/custom/scout/agent_runner.rb`) — currently loads **every** `status: :ready`
  `ScoutKnowledgeSource` and dumps its full `content` into the system prompt on **every**
  conversation turn, uncapped. Both methods are **removed** and replaced by tool registration (see
  Scope below). `build_system_instructions` keeps persona/catalog/contact/out-of-office sections
  untouched — only the knowledge block changes.

## Prerequisite: drop Anthropic from `ScoutAccountConfig`

Phase 06 shipped `ScoutAccountConfig#provider` as `{ gemini: 0, openai: 1, anthropic: 2 }`, but
Anthropic has no embeddings API. Rather than build provider-degradation logic (registering the
search tool only for some accounts), this fork drops Anthropic as a supported provider entirely —
simplifying both phases at once. No production data exists for `ScoutAccountConfig` yet, so this
is a plain code change, not a migration:

- `ScoutAccountConfig#provider` enum → `{ gemini: 0, openai: 1 }`; remove the `:anthropic` branches
  in `build_llm_context`/`probe_provider_credentials!`.
- `ScoutSettings.vue`: remove the Anthropic option from `providerOptions`.
- `scout_account_config_spec.rb`: remove Anthropic-specific examples.
- `06-account-llm-config/spec70.md`: update provider enum references to `gemini`/`openai` only.

## Scope

- New table `ichatr_scout_knowledge_embeddings`: `account_id`, `scout_id`,
  `scout_knowledge_source_id` (all bigint FK), `question` (string), `answer` (text), `embedding`
  (`vector(1536)`, `ivfflat`/cosine index) — one or more rows derived from each
  `ScoutKnowledgeSource`. Model `ScoutKnowledgeEmbedding`: `belongs_to :account, :scout,
  :scout_knowledge_source`; `has_neighbors :embedding, normalize: true` (via the already-vendored
  `neighbor` gem, same pattern as `Captain::AssistantResponse`); `after_commit :enqueue_embed_job,
  on: :create`.
- `Custom::Scout::EmbeddingConfig` — resolves the embedding model/key from the account's own
  `ScoutAccountConfig` (same key already used for chat, via `Scout#llm_chat`), **not** a separate
  system-wide `InstallationConfig`. Uses fixed embedding models per provider for now (no per-account
  override): `gemini-embedding-001` (Gemini, requested at 1536 dimensions) and `text-embedding-3-small`
  (OpenAI, native 1536 dimensions) — exposing this as an account-level config is deferred to a
  future phase.
- `Custom::Scout::KnowledgeSources::FaqGeneratorService` — LLM call via `scout.llm_chat` (the
  account's own chat model) that synthesizes Q&A pairs from a `url`/`document` source's
  already-extracted `content` (single call, no pagination — content is truncated at a size cap for
  v1). `faq`-kind sources skip synthesis (already atomic Q&A).
- `Custom::Scout::KnowledgeSources::GenerateFaqsJob` — enqueued directly from `ProcessJob#process_url`/
  `#process_document` immediately after each sets `status: :ready` (not via a model callback); runs
  the synthesis service and creates `ScoutKnowledgeEmbedding` rows. `ProcessJob#process_faq` creates
  its single embedding row directly instead of going through this job.
- `Custom::Scout::KnowledgeSources::EmbedEntryJob` — enqueued via `ScoutKnowledgeEmbedding`'s
  `after_commit :enqueue_embed_job, on: :create`, calls `EmbeddingConfig.for(account).embed(...)`
  and persists the vector.
- `Custom::Scout::Tools::SearchKnowledgeBase` — new native tool (same `RubyLLM::Tool` /
  `Custom::Scout::Tools::BaseTool` pattern as `ManageOpportunity`/`HandoverToHuman`), embeds the
  query and runs `nearest_neighbors(:embedding, ..., distance: 'cosine')` scoped to the Scout,
  returns top-5 formatted Q&A pairs.
- `AgentRunner` changes: remove blind knowledge injection (`build_knowledge_instructions`,
  `format_knowledge_source`), register `SearchKnowledgeBase` unconditionally in `build_tools` (no
  provider check needed now that Anthropic isn't selectable), and add a short system-prompt line
  pointing the assistant at the tool, only when the scout has ready knowledge sources.
- `ScoutKnowledgeSource#reprocess!` extended to `destroy_all` its `scout_knowledge_embeddings`
  before re-triggering `ProcessJob` (requires adding the `has_many :scout_knowledge_embeddings`
  inverse association), so reprocessing doesn't leave stale/duplicate Q&A pairs.

## Out of scope

- No PDF pagination via provider-native file upload (Captain's `PaginatedFaqGeneratorService`
  pattern) — large PDFs are truncated at a size cap for the synthesis call, not paginated.
- No change to how `url`/`document`/`faq` sources are created, crawled, or uploaded (Phase 05 UI
  and Phase 01/02 pipeline are untouched).
- No verbatim-preservation guarantee for exact figures (prices, dates, warranty terms) inside
  synthesized FAQs beyond prompt-level instruction to avoid paraphrasing numbers — flagged as a
  known limitation of LLM synthesis, not solved in this phase.
- No per-account embedding model override — the fixed model-per-provider mapping in
  `EmbeddingConfig` is a deferred config surface, not built here.
- No support for Anthropic-only accounts running RAG search — Anthropic is dropped from
  `ScoutAccountConfig#provider` as a prerequisite (see above) rather than worked around.
- No handling for stale-dimension embeddings if an account's provider changes without reprocessing
  its knowledge sources — provider changes are rare (BYOK, set once) and reprocessing is a manual
  action already available; not automated here.

## Acceptance criteria

- Creating/reprocessing a `url` or `document` source produces one or more
  `ScoutKnowledgeEmbedding` rows with populated `embedding` vectors, without any manual step.
- Creating a `faq` source produces exactly one `ScoutKnowledgeEmbedding` row (no synthesis call).
- A Scout conversation no longer receives the full knowledge base in its system prompt; instead,
  the assistant calls `search_knowledge_base` and receives only the top-5 semantically relevant
  Q&A pairs for a given query.
- `reprocess!` on a source clears its previous embeddings before regenerating — no duplicate or
  stale Q&A pairs remain searchable afterward.
- `ScoutAccountConfig#provider` only accepts `gemini`/`openai`; the account-config settings screen
  no longer offers Anthropic.
- Token usage per turn for Scouts with a non-trivial knowledge base drops measurably compared to
  the current full-injection baseline (qualitative check via Playground, not a hard numeric gate).
