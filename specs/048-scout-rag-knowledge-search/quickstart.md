# Quickstart Validation Guide: Scout RAG Knowledge Search

## Prerequisites

1. Active Chatwoot development environment running with PostgreSQL (with `vector` extension enabled).
2. An Account with configured `ScoutAccountConfig` (Gemini or OpenAI).
3. A Scout instance belonging to the account.

## Automated Verification

Run the targeted RSpec suite for custom scout models, jobs, services, and tools:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/scout_knowledge_embedding_spec.rb \
  custom/spec/models/scout_knowledge_source_spec.rb \
  custom/spec/services/custom/scout/embedding_config_spec.rb \
  custom/spec/services/custom/scout/knowledge_sources/faq_generator_service_spec.rb \
  custom/spec/services/custom/scout/tools/search_knowledge_base_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb \
  custom/spec/jobs/custom/scout/knowledge_sources/process_job_spec.rb
```

---

## Manual End-to-End Verification Scenarios

### Scenario 1: FAQ Knowledge Ingestion & Direct Vector Generation
1. In the Scout Knowledge tab (or via Rails console), create an FAQ knowledge source with Question: `"Qual o horário de suporte?"` and Answer: `"Nosso suporte funciona das 08h às 18h de segunda a sexta."`.
2. Verify that a `ScoutKnowledgeEmbedding` record is created immediately.
3. Verify that `EmbedEntryJob` populates the `embedding` vector column.

### Scenario 2: Document / URL Q&A Synthesis
1. Create a `url` knowledge source with a web page URL.
2. Allow `ProcessJob` to fetch the webpage content and mark status `:ready`.
3. Confirm that `GenerateFaqsJob` is enqueued and generates multiple `ScoutKnowledgeEmbedding` entries.
4. Confirm each entry receives an embedding vector.

### Scenario 3: On-Demand Retrieval in Conversation & Token Reduction
1. Send an incoming customer message to the Scout: `"Vocês atendem no sábado?"`.
2. Inspect the LLM call logs:
   - Base system prompt does NOT contain raw text of the knowledge base.
   - LLM calls the `search_knowledge_base(query: "horário de atendimento sábado")` tool.
   - Tool returns matching Q&A text.
   - Scout uses the answer to inform the user that support operates Monday-Friday.

### Scenario 4: Clean Reprocessing
1. Update or call `#reprocess!` on a knowledge source.
2. Verify that prior `ScoutKnowledgeEmbedding` rows for that source are deleted.
3. Confirm new embeddings are generated with fresh data and no duplicates exist.
