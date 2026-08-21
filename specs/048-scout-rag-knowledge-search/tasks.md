# Tasks: Scout RAG Knowledge Search (Embeddings)

**Feature Branch**: `048-scout-rag-knowledge-search`
**Specification**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

---

## Phase 1: Setup & Prerequisite Alignment

**Purpose**: Align account LLM provider configuration prerequisites by dropping Anthropic (lacks embeddings API) to ensure 100% RAG capability across all accounts.

- [X] T001 [P] Drop `anthropic` from `ScoutAccountConfig` provider enum (`{ gemini: 0, openai: 1 }`) and remove Anthropic branching in `build_llm_context` in `custom/app/models/scout_account_config.rb`
- [X] T002 [P] Remove Anthropic option from `providerOptions` in `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutSettings.vue`
- [X] T003 [P] Update unit specs for `ScoutAccountConfig` in `custom/spec/models/scout_account_config_spec.rb` and `custom/spec/controllers/api/v1/accounts/scout_account_configs_controller_spec.rb`

---

## Phase 2: Foundational (Database & Models)

**Purpose**: Core data layer infrastructure for storing 768-dim vector embeddings with HNSW indexing and pgvector neighbor queries.

**⚠️ CRITICAL**: Must be completed before user story pipeline and tool implementation.

- [X] T004 Create database migration `db/migrate/21260821102500_create_ichatr_scout_knowledge_embeddings.rb` with 768-dim vector column and HNSW cosine index
- [X] T005 [P] Create `ScoutKnowledgeEmbedding` model with `has_neighbors :embedding, normalize: true` and validations in `custom/app/models/scout_knowledge_embedding.rb`
- [X] T006 [P] Add unit specs for `ScoutKnowledgeEmbedding` model in `custom/spec/models/scout_knowledge_embedding_spec.rb`
- [X] T007 [P] Implement `Custom::Scout::EmbeddingConfig` helper resolving 768-dim embeddings for Gemini (`text-embedding-004`) and OpenAI (`text-embedding-3-small`, `dimensions: 768`) in `custom/app/services/custom/scout/embedding_config.rb`
- [X] T008 [P] Add unit specs for `Custom::Scout::EmbeddingConfig` in `custom/spec/services/custom/scout/embedding_config_spec.rb`

**Checkpoint**: Foundation ready - vector table, model, and embedding configuration helper operational.

---

## Phase 3: User Story 2 - Automated Knowledge Ingestion and Indexing (Priority: P1)

**Goal**: Ingesting or adding knowledge sources (documents, URLs, FAQs) automatically generates structured Q&A pairs and computes 768-dim vector embeddings without manual intervention.

**Independent Test**: Create a URL/document knowledge source, verify that `GenerateFaqsJob` creates `ScoutKnowledgeEmbedding` rows via `FaqGeneratorService`, and verify `EmbedEntryJob` computes and persists the vector.

- [X] T009 [P] [US2] Implement `Custom::Scout::KnowledgeSources::FaqGeneratorService` with 12k char safety cap in `custom/app/services/custom/scout/knowledge_sources/faq_generator_service.rb`
- [X] T010 [P] [US2] Add unit specs for `FaqGeneratorService` in `custom/spec/services/custom/scout/knowledge_sources/faq_generator_service_spec.rb`
- [X] T011 [P] [US2] Implement `Custom::Scout::KnowledgeSources::GenerateFaqsJob` in `custom/app/jobs/custom/scout/knowledge_sources/generate_faqs_job.rb`
- [X] T012 [P] [US2] Implement `Custom::Scout::KnowledgeSources::EmbedEntryJob` in `custom/app/jobs/custom/scout/knowledge_sources/embed_entry_job.rb`
- [X] T013 [US2] Update `Custom::Scout::KnowledgeSources::ProcessJob` to enqueue `GenerateFaqsJob` on `:ready` for URLs/documents and create embedding directly for FAQs in `custom/app/jobs/custom/scout/knowledge_sources/process_job.rb`
- [X] T014 [P] [US2] Add specs for `GenerateFaqsJob`, `EmbedEntryJob`, and updated `ProcessJob` in `custom/spec/jobs/custom/scout/knowledge_sources/`

**Checkpoint**: Knowledge sources are automatically synthesized into Q&A vectors in the background upon extraction.

---

## Phase 4: User Story 1 - On-Demand Knowledge Retrieval During Conversations (Priority: P1) 🎯 MVP

**Goal**: The Scout agent searches the knowledge base on-demand using `search_knowledge_base` during live conversations, eliminating full-text prompt dumping and cutting token usage by >60%.

**Independent Test**: Send a question to a Scout with indexed knowledge, verify that `search_knowledge_base` is invoked with the relevant query, and confirm the system prompt no longer contains raw knowledge source dumps.

- [X] T015 [P] [US1] Implement `Custom::Scout::Tools::SearchKnowledgeBase` tool returning top-5 Q&A pairs in `custom/app/services/custom/scout/tools/search_knowledge_base.rb`
- [X] T016 [P] [US1] Add unit specs for `SearchKnowledgeBase` tool in `custom/spec/services/custom/scout/tools/search_knowledge_base_spec.rb`
- [X] T017 [US1] Refactor `Custom::Scout::AgentRunner` to remove `build_knowledge_instructions` prompt dumping, register `SearchKnowledgeBase` in `build_tools`, and add brief prompt guidance in `custom/app/services/custom/scout/agent_runner.rb`
- [X] T018 [US1] Refactor `Custom::Scout::PlaygroundRunner` to remove `build_knowledge_instructions` prompt dumping and register `SearchKnowledgeBase` in `custom/app/services/custom/scout/playground_runner.rb`
- [X] T019 [P] [US1] Update `AgentRunner` and `PlaygroundRunner` specs in `custom/spec/services/custom/scout/agent_runner_spec.rb` and `custom/spec/services/custom/scout/playground_runner_spec.rb`

**Checkpoint**: End-to-end RAG conversational flow operational with zero blind prompt injection.

---

## Phase 5: User Story 3 - Clean Reprocessing and Stale Data Eviction (Priority: P2)

**Goal**: Reprocessing or deleting a knowledge source purges existing embeddings cleanly to prevent stale or duplicate Q&A pairs in search results.

**Independent Test**: Reprocess an existing knowledge source, verify that all previous embeddings for that source are destroyed before new embeddings are indexed.

- [X] T020 [P] [US3] Add `has_many :scout_knowledge_embeddings, dependent: :destroy` association to `ScoutKnowledgeSource` in `custom/app/models/scout_knowledge_source.rb` and `Scout` in `custom/app/models/scout.rb`
- [X] T021 [US3] Update `ScoutKnowledgeSource#reprocess!` to call `scout_knowledge_embeddings.destroy_all` before status reset in `custom/app/models/scout_knowledge_source.rb`
- [X] T022 [P] [US3] Add regression specs for `ScoutKnowledgeSource#reprocess!` cascading deletion in `custom/spec/models/scout_knowledge_source_spec.rb`

**Checkpoint**: Stale embeddings are purged cleanly on reprocessing or source deletion.

---

## Phase 6: User Story 4 - Graceful Degradation for Unsupported Embedding Providers (Priority: P2)

**Goal**: Accounts with unconfigured credentials or temporary API failures are handled gracefully without breaking conversational workflows.

**Independent Test**: Simulate an embedding provider failure or unconfigured account during conversational search and verify the Scout falls back safely according to fail-safe policy.

- [X] T023 [US4] Implement defense-in-depth provider checks in `Custom::Scout::EmbeddingConfig#supported?` in `custom/app/services/custom/scout/embedding_config.rb`
- [X] T024 [P] [US4] Add edge case specs for missing account config or embedding errors during tool execution in `custom/spec/services/custom/scout/tools/search_knowledge_base_spec.rb`

**Checkpoint**: Robust error handling and defense-in-depth across edge cases.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, linting standards, and comprehensive test suite validation.

- [X] T025 [P] Run RuboCop auto-fix and verify 100% clean check across all files (`docker compose exec rails bundle exec rubocop`)
- [X] T026 [P] Run ESLint on frontend (`docker compose exec vite pnpm eslint`)
- [X] T027 Run full test suite for Scout RAG knowledge search per `specs/048-scout-rag-knowledge-search/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies
- **Phase 1 (Setup)**: Can start immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1 — BLOCKS all user stories.
- **Phase 3 (User Story 2 Ingestion)**: Depends on Phase 2.
- **Phase 4 (User Story 1 Retrieval)**: Depends on Phase 2 and Phase 3.
- **Phase 5 (User Story 3 Eviction)**: Depends on Phase 2 and Phase 3.
- **Phase 6 (User Story 4 Degradation)**: Depends on Phase 2 and Phase 4.
- **Phase 7 (Polish)**: Depends on all user story phases completion.

### Parallel Opportunities
- T001, T002, T003 can be developed in parallel in Phase 1.
- T005, T006, T007, T008 can be developed in parallel in Phase 2 once migration T004 is defined.
- T009, T010, T011, T012 can be developed in parallel in Phase 3.
- T015, T016 can be developed in parallel in Phase 4.
- T020, T022 can run in parallel in Phase 5.
- T025, T026 can run in parallel in Phase 7.

---

## Implementation Strategy

### MVP First (Phases 1, 2, 3, 4)
1. Complete Phase 1: Setup (Prerequisites & Anthropic removal).
2. Complete Phase 2: Foundational (Migration, `ScoutKnowledgeEmbedding` model, `EmbeddingConfig`).
3. Complete Phase 3: Ingestion pipeline (`GenerateFaqsJob`, `EmbedEntryJob`, `FaqGeneratorService`).
4. Complete Phase 4: Retrieval tool & runner refactor (`SearchKnowledgeBase`, `AgentRunner`).
5. **STOP and VALIDATE**: Run User Story 1 & 2 tests. (MVP complete!).

### Incremental Delivery (Phases 5, 6, 7)
6. Add Phase 5: Clean reprocessing & cascade eviction.
7. Add Phase 6: Edge case defense-in-depth.
8. Complete Phase 7: Full linting and test suite verification.
