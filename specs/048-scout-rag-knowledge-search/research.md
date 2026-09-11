# Research: Scout RAG Knowledge Search (Embeddings)

## 1. Vector Storage & Nearest Neighbor Querying

### Decision
Use a new PostgreSQL table `ichatr_scout_knowledge_embeddings` with `embedding` column (`vector(768)`) and `hnsw` index with cosine distance operators (`opclass: :vector_cosine_ops`). Model `ScoutKnowledgeEmbedding` uses `has_neighbors :embedding, normalize: true` via the vendored `neighbor` gem.

### Rationale
- Standardizing on 768 dimensions provides 100% cross-provider compatibility between Gemini (`text-embedding-004`, native 768 dimensions) and OpenAI (`text-embedding-3-small` configured with `dimensions: 768` via Matryoshka embeddings, retaining >99% semantic retrieval precision while halving storage size).
- HNSW (`using: :hnsw, opclass: :vector_cosine_ops`) builds a hierarchical navigable small world graph that performs flawlessly from an empty table without needing manual `REINDEX` or centroid clustering (unlike `ivfflat`).
- Cosine distance similarity search via `.nearest_neighbors(:embedding, vector, distance: 'cosine').limit(5)` operates directly within ActiveRecord relations, respecting tenant (`account_id`) and agent (`scout_id`) scoping.

### Alternatives Considered
- *1536 dimensions fixed*: Incompatible with Gemini's `text-embedding-004` (which natively outputs 768 dimensions and cannot upscale to 1536), resulting in PostgreSQL dimension mismatch errors.
- *IVFFlat index*: Prone to severe recall degradation when initialized on empty tables because centroid lists cannot be properly formed without upfront training data.

---

## 2. Multi-Provider Embedding Configuration (`EmbeddingConfig`)

### Decision
Implement `Custom::Scout::EmbeddingConfig` to resolve the embedding model and credentials directly from the account's existing `ScoutAccountConfig` (Phase 06).
- For `gemini`: uses `text-embedding-004` (native 768 dimensions) with `config.gemini_api_key`.
- For `openai`: uses `text-embedding-3-small` with `dimensions: 768` and `config.openai_api_key`.
- Prerequisite alignment: Drop `anthropic` from `ScoutAccountConfig#provider` enum (`{ gemini: 0, openai: 1 }`) and frontend `ScoutSettings.vue` since Anthropic lacks a native vector embeddings API, eliminating the need for fragmented fallback keys or silent tool omissions.

### Rationale
- Reuses BYOK (Bring Your Own Key) credentials already configured at the account level.
- Provides consistent 768-dimensional embeddings across all supported accounts.
- `RubyLLM.context` isolates credential execution per call without thread-safety risks or global state mutation.

### Alternatives Considered
- *Secondary global embedding key (`InstallationConfig`)*: Rejected because the Scout subsystem is designed around account-level BYOK.
- *Keeping Anthropic and disabling search for Anthropic accounts*: Dropping Anthropic simplifies both Phase 06 and Phase 07, guaranteeing that 100% of configured accounts have full RAG capabilities.

---

## 3. Knowledge Ingestion & Q&A Synthesis Pipeline

### Decision
Split knowledge processing into a robust multi-stage asynchronous pipeline:
1. `ProcessJob` (existing): Extracts raw text from URLs and PDFs, and parses FAQs.
2. For `url` and `document` sources: `ProcessJob` marks source as `:ready` and enqueues `Custom::Scout::KnowledgeSources::GenerateFaqsJob`.
   - `GenerateFaqsJob` invokes `Custom::Scout::KnowledgeSources::FaqGeneratorService` (using `scout.llm_chat`) to synthesize atomic Q&A pairs (truncating raw content to a safety limit if oversized).
   - Each synthesized Q&A pair creates a `ScoutKnowledgeEmbedding` record.
3. For `faq` sources: `ProcessJob` creates a single `ScoutKnowledgeEmbedding` directly without LLM synthesis.
4. `Custom::Scout::KnowledgeSources::EmbedEntryJob`: Triggered after `ScoutKnowledgeEmbedding` creation to compute the 768-dim vector embedding and persist it.

### Rationale
- Decouples raw text extraction from LLM synthesis and vector computation.
- Keeps jobs lightweight and retriable independently.
- Ensures fast ingestion for structured FAQs while extracting structured semantic units from unstructured documents and URLs.

### Alternatives Considered
- *Synchronous embedding generation inside ProcessJob*: Rejected because LLM synthesis and embedding API requests can take several seconds and should not block the initial extraction job.
- *Whole-document single embedding*: Querying a single embedding for an entire 10-page document produces poor similarity scores; atomic Q&A chunks provide vastly superior retrieval precision.

---

## 4. Native Retrieval Tool (`SearchKnowledgeBase`)

### Decision
Create `Custom::Scout::Tools::SearchKnowledgeBase < Custom::Scout::Tools::BaseTool`:
- Exposes `query` parameter (string).
- Embeds query using `EmbeddingConfig.for(account).embed(query)`.
- Scopes search to `scout.scout_knowledge_embeddings.nearest_neighbors(:embedding, query_vector, distance: 'cosine').limit(5)`.
- Formats retrieved results as concise `Question: ...\nAnswer: ...` blocks without source URL metadata (per Session 2026-08-21 clarification) to minimize prompt token overhead.

### Rationale
- Implements standard `RubyLLM::Tool` pattern consistent with other Scout tools (`ManageOpportunity`, `HandoverToHuman`, `CallCustomApi`).
- Allows the LLM to autonomously decide when knowledge lookup is needed and incorporate relevant answers naturally into its conversational response.

### Alternatives Considered
- *Automatic search before every prompt turn*: Incurs unnecessary embedding latency and cost for casual conversational turns (greetings, simple confirmations).

---

## 5. Reprocessing & Lifecycle Cleanup

### Decision
- Add `has_many :scout_knowledge_embeddings, dependent: :destroy` to `ScoutKnowledgeSource` and `Scout`.
- In `ScoutKnowledgeSource#reprocess!`, explicitly destroy existing associated `scout_knowledge_embeddings` before resetting status to `:pending` and enqueueing `ProcessJob`.

### Rationale
- Prevents stale, duplicate, or conflicting Q&A pairs from lingering in vector search results when source documents or website contents change.
- Guarantees complete cascading cleanup upon knowledge source or Scout deletion.
