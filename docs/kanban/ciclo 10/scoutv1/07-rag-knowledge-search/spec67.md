# Phase 07 — RAG Knowledge Search (Embeddings)

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §7.2, §11
**Depends on**: Phase 01 (`ScoutKnowledgeSource` model/pipeline), Phase 02 (native tool pattern to
follow for the new retrieval tool), Phase 06 (`ScoutAccountConfig` — the provider/model/key the
embedding call and the tool's provider gate both read from).

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
  (`pending`/`ready`/`failed`), validations, `reprocess!`. **Unchanged.**
- `Custom::Scout::KnowledgeSources::ProcessJob` (`custom/app/jobs/custom/scout/knowledge_sources/process_job.rb`)
  — `process_url` (HTTParty + Html2Text), `process_document` (PDF text extraction), `process_faq`.
  Populates `ScoutKnowledgeSource#content` and sets `status: :ready`. **Unchanged** — it remains
  the sole source of raw extracted text; this phase only adds a consumer downstream of it.
- Phase 05 commercial UI (`05-commercial-ui/spec66.md` §7.2, "Base de Conhecimento Comercial") —
  the URL/document/FAQ management screens. **Unchanged.**

What actually gets refactored/removed:

- `Custom::Scout::AgentRunner#build_knowledge_instructions` and `#format_knowledge_source`
  (`custom/app/services/custom/scout/agent_runner.rb`) — currently loads **every** `status: :ready`
  `ScoutKnowledgeSource` and dumps its full `content` into the system prompt on **every**
  conversation turn, uncapped. This method is **removed** and replaced by tool registration (see
  Scope below). `build_system_instructions` keeps persona/catalog/contact/out-of-office sections
  untouched — only the knowledge block changes.

## Scope

- New table `ichatr_scout_knowledge_embeddings` (account/scout/source-scoped `question`/`answer`
  pairs + `vector` column, `ivfflat`/cosine index) — one or more rows derived from each
  `ScoutKnowledgeSource`.
- `Custom::Scout::KnowledgeSources::FaqGeneratorService` — LLM call that synthesizes Q&A pairs from
  a `url`/`document` source's already-extracted `content` (single call, no pagination — content is
  truncated at a size cap for v1). `faq`-kind sources skip synthesis (already atomic Q&A).
- `Custom::Scout::KnowledgeSources::GenerateFaqsJob` — enqueued after `ProcessJob` marks a
  `url`/`document` source `ready`; runs the synthesis service and creates embedding rows.
- `Custom::Scout::KnowledgeSources::EmbedEntryJob` — enqueued on `ScoutKnowledgeEmbedding#create`,
  calls `RubyLLM.embed` and persists the vector.
- `Custom::Scout::EmbeddingConfig` — resolves the embedding provider/model/key from the account's
  `ScoutAccountConfig` (Phase 06). Since Anthropic has no embeddings API (confirmed: `ruby_llm`'s
  Anthropic provider raises on `embed`), `EmbeddingConfig` only supports `gemini`/`openai` accounts;
  for `anthropic` accounts it signals "unsupported" and the tool is not registered (see `AgentRunner`
  changes below) — no secondary/embedding-only key is introduced.
- `Custom::Scout::Tools::SearchKnowledgeBase` — new native tool (same `RubyLLM` `chat.with_tool`
  pattern as `ManageOpportunity`/`HandoverToHuman`), embeds the query and runs
  `nearest_neighbors(:embedding, ..., distance: 'cosine')` scoped to the Scout, returns top-5
  formatted Q&A pairs.
- `AgentRunner` changes: remove blind knowledge injection, register `SearchKnowledgeBase` in
  `build_tools` only when the account's `ScoutAccountConfig#provider` supports embeddings (not
  `anthropic`), and add a short system-prompt line pointing the assistant at the tool when it's
  registered.
- `ScoutKnowledgeSource#reprocess!` extended to destroy its existing `scout_knowledge_embeddings`
  before re-triggering `ProcessJob`, so reprocessing doesn't leave stale/duplicate Q&A pairs.

## Out of scope

- No PDF pagination via provider-native file upload (Captain's `PaginatedFaqGeneratorService`
  pattern) — large PDFs are truncated at a size cap for the synthesis call, not paginated.
- No change to how `url`/`document`/`faq` sources are created, crawled, or uploaded (Phase 05 UI
  and Phase 01/02 pipeline are untouched).
- No verbatim-preservation guarantee for exact figures (prices, dates, warranty terms) inside
  synthesized FAQs beyond prompt-level instruction to avoid paraphrasing numbers — flagged as a
  known limitation of LLM synthesis, not solved in this phase.

## Acceptance criteria

- Creating/reprocessing a `url` or `document` source produces one or more
  `ScoutKnowledgeEmbedding` rows with populated `embedding` vectors, without any manual step.
- Creating a `faq` source produces exactly one `ScoutKnowledgeEmbedding` row (no synthesis call).
- A Scout conversation no longer receives the full knowledge base in its system prompt; instead,
  the assistant calls `search_knowledge_base` and receives only the top-5 semantically relevant
  Q&A pairs for a given query.
- `reprocess!` on a source clears its previous embeddings before regenerating — no duplicate or
  stale Q&A pairs remain searchable afterward.
- Token usage per turn for Scouts with a non-trivial knowledge base drops measurably compared to
  the current full-injection baseline (qualitative check via Playground, not a hard numeric gate).
- For an account whose `ScoutAccountConfig#provider` is `anthropic`, Scouts have no
  `search_knowledge_base` tool registered (knowledge sources can still be created/managed, just not
  searched by the assistant) — no error, no crash, just an absent tool.
