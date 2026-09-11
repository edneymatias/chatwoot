# Phase 08 — Funnel Intelligence: Stage Enforcement & Qualification Fields (Preview)

**Status**: Preview — a ser especificado antes da implementação  
**Master doc**: `docs/kanban/ciclo 9/scout/spec60.md` §4.1 (Goal-Driven + Tool Calling)  
**Depends on**: Phase 02 (`manage_opportunity` / `move_opportunity_stage` tools), Phase 05 (UI da aba Funil).

---

## Contexto: o que já existe

A infraestrutura de funil **já está implementada**, mas o `AgentRunner` ignora tudo isso:

### No modelo `PipelineStage`
- `has_many :pipeline_stage_required_fields` → campos obrigatórios **por estágio** (já existe, já tem controller e model: `PipelineStageRequiredField` / tabela `ichatr_pipeline_stage_required_fields`)
- `has_many :required_custom_attribute_definitions` (join via `pipeline_stage_required_fields`)
- Esses campos são atributos de **oportunidade** (`opportunity_attribute`), não de contato

### No modelo `Scout`
- `default_pipeline_stage_id` → onde a oportunidade é criada
- `qualified_stage_id` → estágio de "lead qualificado"
- `unqualified_stage_id` → estágio de "lead desqualificado/sem fit" (field existe, semântica a definir)
- `handover_team_id` → time de handoff humano

### No modelo `Opportunity`
- `enum status: { open: 0, won: 1, lost: 2 }` — os status são: aberto / ganho / perdido
- `lost_reason` — motivo do fechamento como perdido (campo existe no model)
- `attr_accessor :missing_required_fields` — infraestrutura para campos faltantes (usado no Kanban UI)

### Na ferramenta `MoveOpportunityStage`
- Aceita `stage_id` e `lost_reason`, mas o LLM escolhe `stage_id` livremente (sem contexto dos estágios configurados)
- Seta `status: :lost` quando `lost_reason` está presente — mas nunca injeta `won` ou fecha como `lost` de forma semântica

---

## Problemas identificados

### 1. AgentRunner não injeta configuração de estágios no system prompt
O LLM não sabe quais IDs correspondem a "qualificado" e "desqualificado". Move para estágios ao acaso ou nunca move. Correção: injetar seção no system prompt com os IDs configurados e seus significados semânticos.

### 2. AgentRunner não injeta campos obrigatórios por estágio
`PipelineStage` já tem `pipeline_stage_required_fields` — atributos de oportunidade obrigatórios para entrar naquele estágio. O Scout não lê isso, portanto nunca orienta a conversa para coletar esses dados antes de mover o card. Correção: ao registrar os estágios configurados no system prompt, incluir a lista de campos exigidos em cada estágio relevante.

### 3. Estágio "desqualificado" vs. status "perdido" — decisão de design pendente
Dois modelos possíveis:

**Opção A — Estágio de triagem humana ("Sem fit identificado")**  
O Scout move para um estágio específico de desqualificação (status ainda `open`). Um humano confirma e então marca como `lost`. Vantagem: revisão humana antes de encerrar. Desvantagem: estágio extra que pode poluir o funil.

**Opção B — Status lost direto**  
O Scout fecha a oportunidade como `lost` com `lost_reason` preenchido. Sem revisão humana. Mais ágil, menos controle.

**Recomendação para especificação**: decidir por **Opção A** como padrão (alinhada ao conceito human-in-the-loop da spec60) — o Scout move para o estágio desqualificado, que serve como fila de revisão para humanos. O operador configura esse estágio na aba Funil. Formalizar na especificação completa.

### 4. Campos obrigatórios ao marcar como perdido
O `lost_reason` já existe no model, mas:
- A ferramenta `MoveOpportunityStage` recebe `lost_reason` como parâmetro livre — o LLM pode omitir
- Não há enforcement de que o LLM **peça o motivo** antes de fechar como perdido
- Cada conta pode ter `PipelineStageRequiredField` no estágio de desqualificação que o Scout também deve respeitar

### 5. Campos de qualificação globais do Scout (aba Funil) vs. campos por estágio
Há duas fontes de campos obrigatórios:
- `Scout#required_attribute_ids` — selecionados na aba Funil do Scout (global, independente de estágio)
- `PipelineStage#pipeline_stage_required_fields` — configurados por estágio no Kanban

Ambos devem guiar o Scout. A especificação deve definir como reconciliá-los (union? precedência?).

---

## Escopo preliminar para a Fase 08

### Backend — `AgentRunner#build_funnel_instructions`
Nova seção no system prompt injetando:
- IDs e nomes dos estágios configurados no Scout (default, qualificado, desqualificado)
- Campos obrigatórios de cada estágio relevante (via `pipeline_stage_required_fields`)
- Campos obrigatórios globais (via `scout.required_attribute_ids`)
- Semântica do status `lost`: quando usar vs. quando mover para estágio de desqualificação

### Backend — `MoveOpportunityStage` com enforcement
- Verificar campos obrigatórios do estágio de destino antes de mover
- Se campos faltantes: retornar erro descritivo ao LLM para retomar coleta
- Se destino é estágio desqualificado e `lost_reason` não fornecido: exigir motivo

### Decisão de design a formalizar
- Estágio desqualificado = estágio de funil (status `open`) ou status `lost` direto?
- Como o Scout deve se comportar ao mover para estágio desqualificado: encerrar conversa? criar nota? handoff?

---

## Fora de escopo desta fase
- UI para configurar campos obrigatórios por estágio (já existe no Kanban)
- UI para configurar campos globais do Scout (já existe na aba Funil)
- Criação do estágio de desqualificação em si (é configuração de conta, não do Scout)
- Integração Meta CAPI ao qualificar (spec60 §2.4 — fase futura)

---

## Critérios de aceite (rascunho)
- LLM recebe no system prompt os IDs e significados dos estágios configurados, e a lista de campos obrigatórios de cada um
- `MoveOpportunityStage` bloqueia a movimentação para estágio qualificado se houver campos do estágio não preenchidos, retornando quais faltam
- `MoveOpportunityStage` exige `lost_reason` ao mover para estágio desqualificado
- Após preencher todos os campos exigidos, a movimentação ocorre normalmente

---

> **Nota**: Preview expandido após análise do código existente. Os modelos `PipelineStage`, `PipelineStageRequiredField` e `Opportunity` já têm toda a infraestrutura necessária — esta fase é puramente de conectar a configuração existente ao `AgentRunner`. Decisões de design (especialmente estágio vs. status para desqualificação) devem ser resolvidas na sessão de especificação completa.
