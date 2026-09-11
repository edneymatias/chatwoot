# Contract: Knowledge Ingestion & Embedding Services

## 1. `Custom::Scout::EmbeddingConfig`

Resolves provider-specific embedding parameters and executes vector generation.

### Interface

```ruby
class Custom::Scout::EmbeddingConfig
  def self.for(account)
    # Returns an instance initialized with the account's ScoutAccountConfig
  end

  def embed(text)
    # Generates a 768-dimensional normalized vector for the provided text.
    # OpenAI: text-embedding-3-small with dimensions: 768
    # Gemini: text-embedding-004 (native 768)
    # Returns: Array<Float> (length 768)
  end

  def supported?
    # Returns true if account has valid Gemini or OpenAI configuration
  end
end
```

---

## 2. `Custom::Scout::KnowledgeSources::FaqGeneratorService`

Generates structured Q&A pairs from raw extracted text using the Scout's chat model.

### Input
- `source`: `ScoutKnowledgeSource` record (with `content` populated)

### Output
- `Array<Hash>` of synthesized question-and-answer pairs:
  ```json
  [
    {
      "question": "Qual é a política de garantia?",
      "answer": "A garantia cobre defeitos de fabricação pelo período de 12 meses."
    },
    {
      "question": "Como solicitar troca de produto?",
      "answer": "A solicitação de troca deve ser feita em até 7 dias corridos após o recebimento."
    }
  ]
  ```

### Truncation Guard
Raw content input is capped at 12,000 characters before sending to the LLM to prevent context overflow.

---

## 3. Background Jobs

### `Custom::Scout::KnowledgeSources::GenerateFaqsJob`
- **Queue**: `:default`
- **Trigger**: Called by `ProcessJob` upon marking a `url` or `document` source `:ready`.
- **Action**: Executes `FaqGeneratorService` and inserts `ScoutKnowledgeEmbedding` records.

### `Custom::Scout::KnowledgeSources::EmbedEntryJob`
- **Queue**: `:default`
- **Trigger**: Called via `after_commit, on: :create` on `ScoutKnowledgeEmbedding`.
- **Action**: Calls `EmbeddingConfig.for(account).embed("#{question}: #{answer}")` and updates the `embedding` column.
