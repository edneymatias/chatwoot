# Implementation Plan: Scout RAG Knowledge Search (Embeddings)

**Branch**: `048-scout-rag-knowledge-search` | **Date**: 2026-08-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/048-scout-rag-knowledge-search/spec.md` and validated research in `specs/048-scout-rag-knowledge-search/research.md`.

## Summary

Replace full-content prompt injection of knowledge base text in Scout agents with on-demand semantic retrieval (RAG). The feature introduces:
1. Prerequisite clean up: `ScoutAccountConfig` provider enum drops `anthropic` (`{ gemini: 0, openai: 1 }`).
2. New table `ichatr_scout_knowledge_embeddings` with `embedding` column (`vector(768)`) and `hnsw` cosine distance index.
3. Multi-provider embedding resolution helper `Custom::Scout::EmbeddingConfig` (OpenAI `text-embedding-3-small` with `dimensions: 768`, Gemini `text-embedding-004` native 768).
4. Asynchronous synthesis and embedding pipeline (`FaqGeneratorService`, `GenerateFaqsJob`, `EmbedEntryJob`).
5. Native retrieval tool `Custom::Scout::Tools::SearchKnowledgeBase` scoped to the Scout and Account.
6. Refactoring `AgentRunner` and `PlaygroundRunner` to remove blind prompt dumping and register the knowledge search tool.
7. Cascade eviction on `ScoutKnowledgeSource#reprocess!`.

## Technical Context

**Language/Version**: Ruby 3.3+ (Rails 7.1), JavaScript/Vue 3 (Composition API `<script setup>`)

**Primary Dependencies**: `neighbor` gem (vendored pgvector client), `ruby_llm` (~> 1.14 / 1.15.0), `ruby_llm-schema` (0.3.0), `pgvector` extension

**Storage**: PostgreSQL with `vector` extension (`ichatr_scout_knowledge_embeddings` table with 768-dim vector column and HNSW index)

**Testing**: RSpec (`env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec ...`), Vitest/pnpm test (`docker compose exec vite pnpm test`)

**Target Platform**: Linux containerized environment (Docker / rootless Podman)

**Project Type**: Custom decoupled backend module (`custom/`) and frontend settings view (`app/javascript/`)

**Performance Goals**: >60% reduction in per-turn system prompt tokens; knowledge vector retrieval < 50ms; indexing SLA < 30s per source.

**Constraints**: Dual-language synchronization (`en` / `pt-BR`); no foreign schema pollution; pure Tailwind utility classes in UI.

**Scale/Scope**: Up to 500 Q&A pairs per Scout knowledge base; top-5 nearest neighbors returned per tool invocation.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **I. Upstream Compatibility First**: All custom tables use the `ichatr_` prefix (`ichatr_scout_knowledge_embeddings`). All new backend services live under `custom/app/`. No core Chatwoot tables or controllers are modified.
- [x] **II. Smallest Production-Ready Change**: Reuses existing `neighbor` gem, `RubyLLM.context`, and `ProcessJob` pipeline without introducing redundant vector stores or speculative pagination frameworks.
- [x] **III. Adhere to Established Conventions**: Follows RuboCop 150-char line limit, compact module definitions, PascalCase Vue components, and Composition API.
- [x] **IV. Safe, Reversible Change Management**: Database migration is purely additive (`create_table :ichatr_scout_knowledge_embeddings`) and reversible.
- [x] **V. Dual-Tree Awareness (OSS + Enterprise)**: Inspects `enterprise/app/models/captain/` for read-only inspiration without copying proprietary code; changes are isolated inside `custom/`.

---

## Project Structure

### Documentation (this feature)

```text
specs/048-scout-rag-knowledge-search/
├── plan.md              # Implementation plan (/speckit-plan command output)
├── research.md          # Phase 0 architectural decisions
├── data-model.md        # Entity definitions and schema
├── quickstart.md        # Validation scenarios and testing guide
├── contracts/           # Tool and service interfaces
│   ├── search-knowledge-base-tool.md
│   └── ingestion-pipeline.md
└── checklists/
    └── requirements.md  # Quality checklist
```

### Source Code (repository root)

```text
custom/
├── app/
│   ├── jobs/
│   │   └── custom/
│   │       └── scout/
│   │           └── knowledge_sources/
│   │               ├── generate_faqs_job.rb             # [NEW]
│   │               ├── embed_entry_job.rb               # [NEW]
│   │               └── process_job.rb                   # [MODIFY] trigger FAQ generation
│   ├── models/
│   │   ├── scout_knowledge_embedding.rb                 # [NEW] pgvector neighbor model
│   │   ├── scout_knowledge_source.rb                    # [MODIFY] has_many + clean reprocess!
│   │   ├── scout_account_config.rb                      # [MODIFY] drop anthropic provider
│   │   └── scout.rb                                     # [MODIFY] has_many embeddings
│   └── services/
│       └── custom/
│           └── scout/
│               ├── embedding_config.rb                  # [NEW] multi-provider embedding helper
│               ├── agent_runner.rb                      # [MODIFY] remove prompt dump, add tool
│               ├── playground_runner.rb                 # [MODIFY] remove prompt dump, add tool
│               ├── knowledge_sources/
│               │   └── faq_generator_service.rb         # [NEW] LLM Q&A synthesis
│               └── tools/
│                   └── search_knowledge_base.rb         # [NEW] native retrieval tool
└── spec/
    ├── models/
    │   ├── scout_knowledge_embedding_spec.rb            # [NEW]
    │   ├── scout_knowledge_source_spec.rb               # [MODIFY]
    │   └── scout_account_config_spec.rb                 # [MODIFY]
    ├── services/
    │   └── custom/
    │       └── scout/
    │           ├── embedding_config_spec.rb             # [NEW]
    │           ├── knowledge_sources/
    │           │   └── faq_generator_service_spec.rb    # [NEW]
    │           └── tools/
    │               └── search_knowledge_base_spec.rb    # [NEW]
    └── jobs/
        └── custom/
            └── scout/
                └── knowledge_sources/
                    ├── generate_faqs_job_spec.rb        # [NEW]
                    └── embed_entry_job_spec.rb          # [NEW]

db/migrate/
└── 21260821102500_create_ichatr_scout_knowledge_embeddings.rb # [NEW] migration

app/javascript/dashboard/routes/dashboard/scout/pages/
└── ScoutSettings.vue                                    # [MODIFY] remove anthropic option
```

**Structure Decision**: Decoupled feature architecture under `custom/` following existing Scout conventions from Phases 01-06.

---

## Complexity Tracking

*No violations identified. Architecture is fully compliant with the Constitution.*
