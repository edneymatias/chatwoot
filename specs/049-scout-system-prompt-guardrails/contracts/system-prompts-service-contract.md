# Contract: System Prompts Service

**Feature**: Scout System Prompt Guardrails Architecture (`049-scout-system-prompt-guardrails`)  
**Service**: `Custom::Scout::SystemPromptsService`  
**Location**: `custom/app/services/custom/scout/system_prompts_service.rb`

---

## 1. Interface Definition

```ruby
module Custom::Scout
  class SystemPromptsService
    def self.build(scout:, contact: nil, inbox: nil, catalog_instructions: nil, knowledge_available: false)
      # Returns formatted system prompt String
    end
  end
end
```

### 1.1 Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :---: | :--- |
| `scout` | `Scout` | Yes | Scout instance containing identity, custom prompt, and catalog. |
| `contact` | `Contact` | No | Contact record containing attributes and profile context. |
| `inbox` | `Inbox` | No | Inbox record for checking working hours / out-of-office status. |
| `catalog_instructions` | `String` | No | Formatted product catalog instructions. |
| `knowledge_available` | `Boolean` | No | Flag indicating if knowledge base search tool instruction should be included. |

### 1.2 Output

- Returns a single, cohesive `String` containing the assembled system prompt.

---

## 2. Prompt Section Structure

The prompt must include the following logical sections in order:

1. **[Identidade e Papel]**:
   - Agent name (`scout.name` or default `'Scout'`).
   - Role: Commercial/lead qualification assistant for the account.
   - Domain Boundary: The agent must ONLY discuss products, services, policies, and information provided in the context or accessible tools. Explicit instruction to politely decline unrelated or out-of-scope topics.

2. **[Diretrizes de Resposta e Segurança]**:
   - Anti-hallucination: Never invent information or use general pre-training assumptions for account/product details.
   - Anti-false-promise: Never make unverified promises of future asynchronous actions ("vou verificar amanhã", "enviaremos um email depois") unless executed now via an available tool.
   - Human Handoff Fallback: If context is insufficient to answer or if the customer requests human assistance, call `handover_to_human`.
   - Conversational flow: Natural, polite, clear Portuguese (or detected customer language).

3. **[Contexto Adicional]**:
   - Product Catalog (if present via `catalog_instructions`).
   - Knowledge Base Tool notice (if `knowledge_available` is true).
   - Contact Context (if `contact` is present).
   - Out of Office notice (if `inbox&.out_of_office?` is true).

4. **[Instruções Personalizadas da Conta]** *(Subordinadas)*:
   - If `scout.system_prompt` is present, wrapped in `<account_custom_instructions>` tags with explicit subordination instructions.

5. **[Formato de Resposta Obrigatório]**:
   - Instructs the model to ALWAYS respond strictly in a valid JSON object:
     ```json
     {
       "reasoning": "Breve justificativa interna",
       "response": "Texto da resposta ao cliente"
     }
     ```
