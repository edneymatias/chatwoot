# Fase 14 — Detecção de Continuidade de Oportunidade (Preview)

> **Resolvido**: ver `spec75.md` (mesma pasta) para o design final, resultado da sessão de
> brainstorming ancorada por este documento. Este arquivo permanece como registro histórico do
> problema e dos exemplos que o motivaram.

**Status**: ~~Preview~~ Resolvido — ver `spec75.md`. Este documento existia para ancorar uma sessão
de brainstorming dedicada; problema registrado durante o brainstorming da Fase 10.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 02 (Ferramentas Nativas & Pipeline — `manage_opportunity`,
`Custom::AutomationRules::ActionService`), Phase 10 (In-Conversation UI — onde o gap foi
identificado; o link do Kanban dessa fase depende, sem corrigir, do vínculo `OpportunityConversation`
que este problema afeta).

---

## Este preview não tem arquitetura de referência no Captain

Diferente da Fase 12 (Auditor de Resposta), que tem um mecanismo análogo direto no Captain
(`V1ActionClassifier`/`V1FalsePromiseHandler`) para usar como referência de leitura, **o Captain
não tem noção nenhuma de Oportunidade/Kanban** — é um problema original deste fork, sem
precedente upstream para se apoiar. A especificação completa, quando for escrita, parte do zero.

## O problema, em termos concretos

Durante o brainstorming da Fase 10 (link do Kanban na conversa), identificamos que **nada no Scout
hoje decide, de forma determinística, se a conversa atual deveria estar associada a uma
Oportunidade nova, a uma Oportunidade em andamento, ou a nenhuma**. Tanto
`Custom::Scout::Tools::ManageOpportunity#execute` quanto
`Custom::AutomationRules::ActionService#create_opportunity` só verificam
`Opportunity.find_by(origin_conversation_id: conversation.id)` — ou seja, só reconhecem uma
Oportunidade já existente se ela nasceu **exatamente desta conversa**. Não existe checagem por
contato, nem qualquer heurística de "este é o mesmo negócio continuando em outro canal/conversa".

Isso não é necessariamente um bug de validação — o schema permite de propósito múltiplas
Oportunidades por contato (`Contact has_many :opportunities`, sem escopo, sem constraint de "uma
aberta por contato"), porque um mesmo cliente pode legitimamente ter mais de um negócio ao longo do
tempo. O problema é que o Scout nunca *decide* — ele nunca olha.

### Exemplos que motivaram o registro (ver `../10-in-conversation-ui/spec68.md` para o contexto completo)

1. **Conversa geral que menciona uma oportunidade já em andamento** — Maria fala com o Scout sobre
   uma dúvida de cobrança (assunto financeiro, sem relação comercial aparente) e, no meio da
   conversa, menciona interesse em algo que já é uma Oportunidade aberta no Kanban (criada por uma
   conversa anterior, em outro canal). Mesmo com o vínculo já existente via
   `OpportunityConversation` (então o link somente-leitura da Fase 10 mostra certo), a ferramenta
   `manage_opportunity`, se chamada nesta conversa, não enxerga esse vínculo — só olha
   `origin_conversation_id` — e criaria uma Oportunidade duplicada.
2. **Continuidade sem vínculo prévio nenhum** — João já tem uma Oportunidade aberta ("Plano
   Empresarial", estágio "Proposta Enviada") de uma conversa anterior, já encerrada. Ele abre uma
   conversa **nova** (nova sessão, novo registro de `Conversation`, zero vínculo) perguntando sobre
   o mesmo negócio. O Scout, sem nenhuma noção de que essa Oportunidade já existe, cria uma
   segunda — dois cards no Kanban para o mesmo negócio, sem que ninguém decida se deveriam ser um
   só.
3. **Conversa genuinamente nova** — Pedro nunca conversou antes; não existe Oportunidade alguma
   para ele. Este é o caso simples que já funciona hoje (o Scout cria quando qualifica).

## Perguntas em aberto (para a sessão de brainstorming)

1. Como definir, de forma determinística, se a conversa atual trata de **(a)** uma oportunidade
   nova, **(b)** uma oportunidade em andamento já existente para o mesmo contato, ou **(c)** é uma
   conversa geral, sem relação comercial nenhuma?
2. Como o Scout detecta, de forma determinística, o momento em que uma conversa geral (categoria
   **c** acima) **evolui** para uma discussão de oportunidade no meio do próprio diálogo — deixando
   de ser "geral"?
3. Uma vez identificado interesse comercial, como decidir entre **anexar** a conversa a uma
   Oportunidade em andamento já existente vs. **abrir uma Oportunidade nova** — seja porque não
   existe nenhuma para aquele contato, seja porque o interesse mencionado é diferente do que já
   está registrado na Oportunidade existente?

## Fora de escopo deste preview

- Qualquer decisão de arquitetura, prompt, heurística ou modelo de dados — este documento só
  registra o problema e os exemplos que o motivaram.
- Mudanças em `manage_opportunity`, `ActionService`, ou qualquer código de produção — nada aqui é
  implementado até a especificação completa ser escrita e aprovada.

## Critérios de aceite (rascunho — só valem quando a fase avançar)

- Os três exemplos acima (ou equivalentes) passam a ter comportamento decidido e testável: cada um
  resulta em anexar à Oportunidade certa, criar uma nova, ou não tocar em Oportunidade nenhuma —
  nunca em duplicação silenciosa.
- A decisão é auditável (o motivo da escolha — anexar/criar/ignorar — fica registrado, não é um
  efeito colateral silencioso de uma chamada de tool).
