# Contract: `search_knowledge_base` Tool

## Overview

`Custom::Scout::Tools::SearchKnowledgeBase` is a native tool registered with the Scout's `RubyLLM` chat instance. When invoked during a conversation, it converts the search query into a vector embedding, performs a cosine distance similarity query against the Scout's indexed knowledge embeddings, and returns the top 5 relevant question-and-answer pairs.

## Tool Definition

- **Class**: `Custom::Scout::Tools::SearchKnowledgeBase < Custom::Scout::Tools::BaseTool`
- **Tool Identifier**: `search_knowledge_base`
- **Description**: `Search knowledge base for relevant questions and answers using semantic similarity`

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `query` | `string` | Yes | The natural language question or topic to look up in the knowledge base |

## Return Payload

### On Successful Matches (1 to 5 results)
Plain text formatted list of question-and-answer pairs (no source URLs or metadata, per specification):

```text
Pergunta: Qual é o prazo de entrega padrão?
Resposta: Nosso prazo padrão de entrega para capitais é de 2 a 3 dias úteis.

Pergunta: Quais são as formas de pagamento aceitas?
Resposta: Aceitamos cartão de crédito em até 12x, PIX com 5% de desconto e boleto bancário à vista.
```

### On No Matches Found
```text
Nenhuma informação relevante encontrada na base de conhecimento para: <query>
```

### On Error / Provider Failure
```text
Erro ao consultar base de conhecimento: <error_message>
```

## Behavior & Execution Rules

1. **Scoping**: Queries are strictly scoped to the active `scout_id` and `account_id`.
2. **Top-K**: Retrieves at most 5 nearest neighbors using cosine distance.
3. **Playground Mode**: When executed within the playground environment, performs the actual vector search against the Scout's real embeddings and records the tool invocation in the runner's execution trace.
