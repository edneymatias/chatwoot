# Fase 14 — Detecção de Continuidade de Oportunidade

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 02 (Ferramentas Nativas — `manage_opportunity`), Phase 08 (System Prompt
Guardrails — ponto de extensão do contexto operacional), Phase 09 (Estágios & Qualificação — já
estabelece o padrão de expor contexto estruturado no prompt).
**Precedido por**: `spec-preview.md` (mesma pasta) — registra o problema original e os três
cenários concretos que motivaram esta fase (Maria/dúvida financeira, João/continuidade sem
vínculo, Pedro/conversa nova). Este documento é a solução, resultado de brainstorming dedicado.

## Goal

Dar ao Scout (e ao `Custom::AutomationRules::ActionService`) uma forma determinística de decidir,
toda vez que uma Oportunidade for criada ou referenciada, se deve reaproveitar uma Oportunidade
aberta já existente do mesmo contato ou criar uma nova — eliminando duplicação silenciosa de cards
no Kanban para o mesmo negócio.

## Contexto resumido (ver `spec-preview.md` para os exemplos completos)

- Hoje, tanto `Custom::Scout::Tools::ManageOpportunity` quanto
  `Custom::AutomationRules::ActionService#create_opportunity` só reconhecem uma Oportunidade
  existente se ela nasceu exatamente da conversa atual (`origin_conversation_id`). Nenhuma busca
  por contato existe.
- `Contact has_many :opportunities` é intencionalmente sem escopo — múltiplas Oportunidades por
  contato são um cenário legítimo (cliente recorrente), então a solução não pode ser uma
  constraint simples de unicidade.
- O mecanismo de memória do Scout (`Custom::Scout::ContactNotesService` → `contact.notes` →
  `LlmFormatter::ContactLlmFormatter` → `contact.to_llm_text`, já injetado em todo system prompt
  via `Custom::Scout::SystemPromptsService.build`) já dá ao Scout, em toda conversa, uma narrativa
  acumulada sobre o contato — mas sem ponteiro estruturado para IDs de Oportunidade específicos.

## Solução

A detecção de "conversa evoluiu de geral para comercial" (sub-problema original 2, ver
`spec-preview.md`) **não exige mecanismo novo** — já é responsabilidade normal do Scout decidir
quando chamar `manage_opportunity`; a única mudança necessária é reforçar essa instrução nos
guardrails do system prompt (Fase 08), garantindo que o Scout chame a tool assim que perceber
interesse comercial, em qualquer ponto da conversa, não só no início.

O que resta (sub-problemas 1 e 3 — classificar nova/em-andamento e decidir anexar-vs-criar) é
resolvido por um funil de 3 partes, seguindo o padrão determinístico validado na pesquisa de
mercado feita para esta fase (Odoo CRM, crowd.dev — ver `spec-preview.md`):

1. **Candidatos, busca determinística e escopada**: `Opportunity.where(contact_id: contact.id,
   status: :open)` — nunca busca sem escopo. Mesmo princípio do `Crm::Leadsquared::LeadFinderService`
   já existente no core (`app/services/crm/leadsquared/lead_finder_service.rb`, busca por
   identificador antes de criar) e do filtro "não perdido/não ganho" do Odoo CRM.
2. **Contexto estruturado exposto ao Scout**: a lista desses candidatos (`id`, `title`,
   `pipeline_stage`) é injetada no system prompt como contexto operacional — mesmo padrão já usado
   na Fase 09 para estágios do funil — ao lado (não em substituição) da narrativa de memória já
   existente via `contact.to_llm_text`/`contact.notes`.
3. **Declaração explícita e validação determinística**: `manage_opportunity` passa a aceitar um
   parâmetro `opportunity_id` (opcional). Quando existem candidatos abertos:
   - **0 candidatos** → cria nova Oportunidade, autônomo.
   - **Scout declara um `opportunity_id` presente na lista de candidatos** → válido, anexa/atualiza
     autonomamente (alta confiança).
   - **Scout declara um `opportunity_id` que não está na lista de candidatos válidos** → inválido,
     cai no caminho ambíguo.
   - **Scout não declara `opportunity_id`, mas existem candidatos abertos** (1 ou mais) → ambíguo,
     não decide sozinho.

A validação do `opportunity_id` é sempre feita no backend contra a query real — nunca se confia
cegamente na declaração do LLM.

## Caminho ambíguo (nunca decide sozinho)

Quando o funil não resolve deterministicamente (candidato inválido, ausência de declaração com
candidatos existentes), o Scout **não cria nem anexa** — registra uma nota privada explicando a
ambiguidade (mesmo padrão de nota amarela de alerta já usado no fail-safe,
`AgentRunner#perform_fail_safe_handoff`) e segue a conversa normalmente nos demais aspectos. A
resolução fica para um humano, via Kanban — consistente com o princípio já estabelecido na Fase 9
("Scout nunca marca oportunidade como perdida/ganha — sempre ação humana", ver
`09-required-qualification-attributes/`).

## Scope

- Alteração em `Custom::Scout::Tools::ManageOpportunity`: busca por `contact_id` + `status: open`,
  novo parâmetro `opportunity_id`, validação determinística, caminho ambíguo (nota privada).
- Mesma alteração em `Custom::AutomationRules::ActionService#create_opportunity` — mesmo gap, mesma
  correção (ver `spec-preview.md`, cenário 1: o vínculo via `OpportunityConversation` já existe
  para a UI da Fase 10, mas nenhum dos dois pontos de criação de Oportunidade o enxerga).
- Contexto estruturado de Oportunidades abertas do contato exposto via
  `Custom::Scout::SystemPromptsService.build` (ao lado do já existente `contact.to_llm_text`).
- Reforço de instrução nos guardrails do system prompt (Fase 08) sobre chamar `manage_opportunity`
  a qualquer momento da conversa, não só no início.

## Out of scope

- Qualquer novo campo em `Opportunity` — a solução reaproveita a memória de contato já existente
  (`contact.notes`) em vez de duplicar esse dado num campo próprio.
- UI para o humano resolver o caso ambíguo além da nota privada + Kanban já existentes — nenhuma
  tela nova.
- Mudança no mecanismo de geração de notas (`ContactNotesService`) além do que já existe — não é
  necessário enriquecer as notas com ponteiros de Oportunidade, já que o contexto estruturado do
  item 2 do funil acima já cobre o ponteiro determinístico separadamente.

## Acceptance criteria

- Cenário 2 do `spec-preview.md` (João): contato com 1 Oportunidade aberta de conversa anterior,
  conversa nova sem vínculo prévio — ao mencionar o mesmo negócio, o Scout anexa à Oportunidade
  existente em vez de criar uma duplicada.
- Cenário 1 do `spec-preview.md` (Maria): mesma correção vale quando o vínculo de conversa já
  existe via `OpportunityConversation`, mas a tool é chamada numa conversa diferente da origem.
- Cenário com 2+ Oportunidades abertas pro mesmo contato, candidato inválido, ou ausência de
  declaração quando existem candidatos: nenhuma Oportunidade é criada/alterada automaticamente;
  uma nota privada de alerta é criada explicando a ambiguidade.
- Cenário 3 (Pedro, contato novo): comportamento inalterado — 0 candidatos, cria normalmente.
- `Custom::AutomationRules::ActionService#create_opportunity` aplica a mesma lógica de busca por
  contato (não só `origin_conversation_id`).
