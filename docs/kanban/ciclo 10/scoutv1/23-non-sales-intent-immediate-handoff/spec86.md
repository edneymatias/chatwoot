# Fase 23 — Reconhecimento de Intenção Fora de Prospecção e Handoff Imediato

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 04 (`Custom::Scout::Tools::CallCustomApi`/`ScoutTool` — mecanismo genérico de
ferramenta externa, reaproveitado aqui sem nenhuma mudança), Fase 12 (Response Auditor —
`ActionClassifierService`/`out_of_scope_commercial_request`, mecanismo reativo complementar que
permanece como rede de segurança, não é substituído).

---

## Objetivo

Hoje o Scout não tem nenhuma regra proativa que reconheça quando o contato não é um lead comercial
buscando avaliação/tratamento, mas sim alguém com outra necessidade — cliente existente com dúvida
de suporte, reagendamento, cancelamento, reclamação, ou qualquer questão que não seja prospecção. Ele
tenta ajudar como se fosse sempre qualificação, sem transferir de imediato.

## Contexto de investigação (por que este desenho)

- `identity_section` (`system_prompts_service.rb`) hoje instrui explicitamente "tirar dúvidas sobre
  produtos e serviços" sem distinguir se o contato é prospecção ou não — na prática convida o Scout a
  tentar ajudar mesmo quando não deveria.
- Os guardrails atuais só preveem handoff **reativo**: *"Fallback para humano: Se você não souber a
  resposta, se o contexto for insuficiente ou se o lead solicitar atendimento humano..."* — três
  gatilhos de "Scout travou ou foi pedido", nenhum de "reconheci que isto não é prospecção".
- O único mecanismo próximo, `Custom::Scout::ActionClassifierService` (Fase 12, categoria
  `out_of_scope_commercial_request`), tem três limitações que não cobrem o caso: é **opt-in**
  (`@scout.feature_response_auditor?`), é **reativo** (roda só depois do modelo já ter gerado uma
  resposta), e seu critério ("fora do escopo comercial") é mais estreito que "cliente existente com
  outra necessidade" — uma pergunta de reagendamento ainda é comercial/da clínica, só não é uma nova
  prospecção.
- Evidência real de produção: em conversas de teste recentes, o próprio modelo já pergunta
  espontaneamente "você quer tirar uma dúvida rápida ou está buscando informações sobre um tratamento
  específico?" — comportamento emergente, sem nenhum guardrail instruindo isso — mas não existe regra
  nenhuma para agir sobre a resposta do cliente a essa pergunta.
- Avaliado e descartado: usar uma API do ERP capaz de indicar com certeza se um telefone já pertence
  a um cliente (comprou / tratamento em andamento) como **gatilho mecânico automático** de handoff.
  Decisão explícita do operador: esse sinal ajuda como reforço, mas a transferência depende do que a
  pessoa efetivamente diz na conversa, não é automática só por já ser cliente (alguém com tratamento
  concluído pode estar voltando para comprar de novo, uma prospecção legítima).
- Confirmado: `Custom::Scout::Tools::CallCustomApi` (Fase 04) já expõe dinamicamente qualquer
  `ScoutTool` configurado pela conta (nome/descrição/schema) na própria descrição da tool que o LLM
  lê. Uma consulta de status de cliente no ERP **não exige nenhum código novo** — é só o operador
  cadastrar um `ScoutTool` (mesmo mecanismo já usado para "buscar horários disponíveis"/"encontrar
  cliente por telefone", que o operador já está testando para o fluxo de agendamento).

## Decisões de desenho

1. **Handoff por reconhecimento de intenção é julgamento do modelo, baseado no que o cliente diz** —
   não é um gatilho mecânico disparado automaticamente por status de ERP.
2. **A consulta a uma ferramenta externa de status de cliente é reforço opcional**, nunca
   obrigatória — um sinal claro na fala do cliente já é suficiente para decidir a transferência, com
   ou sem essa ferramenta configurada.
3. **Nenhuma ferramenta nativa nova, nenhuma tabela, nenhuma migration** — o único artefato desta
   fase é uma adição de texto ao `guardrails_section`.
4. **O mecanismo reativo existente (Fase 12) permanece como rede de segurança complementar**, não é
   substituído — a nova regra proativa deve reduzir a frequência com que ele precisa agir, mas não o
   torna redundante (mesmo princípio de camadas em duas fases já usado no Scout: mecanismo primário +
   auditoria como rede de segurança).

## Escopo

### 1. Novo guardrail em `Custom::Scout::SystemPromptsService#guardrails_section`

Inserir logo após o bullet "Fallback para humano" (`custom/app/services/custom/scout/system_prompts_service.rb`):

```ruby
'- Reconhecimento de intenção fora de prospecção: Se em qualquer momento ficar claro que o contato ' \
  'não busca uma nova avaliação/tratamento — ex.: afirma já ser cliente, menciona tratamento em ' \
  'andamento, quer reagendar/cancelar, tem uma reclamação, ou responde a uma pergunta de triagem ' \
  'indicando ser "só uma dúvida rápida" não relacionada a agendar avaliação — não tente resolver a ' \
  'questão por conta própria, mesmo que pareça simples. Utilize `handover_to_human` imediatamente. ' \
  'Se houver uma ferramenta externa configurada para verificar o status do contato (cliente ' \
  'existente, tratamento em andamento) e o telefone já estiver disponível, consulte-a para reforçar ' \
  'a decisão — mas um sinal claro na própria fala do cliente já é suficiente para transferir, sem ' \
  'exigir confirmação do ERP.'
```

### 2. Nenhuma mudança de código além do texto do guardrail

Confirmado explicitamente: nenhuma tool nativa nova, nenhum model ou migration. A capacidade de
consultar o ERP já existe via `ScoutTool`/`call_custom_api` (Fase 04) — cabe ao operador cadastrar a
ferramenta externa correspondente na aba "Ferramentas" já existente; isso é configuração de conta,
fora do escopo de código desta fase.

## Fora de escopo

- Cadastro do `ScoutTool` de verificação de status no ERP — configuração do operador na UI já
  existente (Fase 04), não faz parte do código desta fase.
- Handoff automático/mecânico disparado só por status de ERP — descartado explicitamente (Decisão de
  desenho #1); a leitura de intenção continua vindo do julgamento do modelo sobre a fala do cliente.
- Qualquer alteração no `ActionClassifierService`/Response Auditor (Fase 12) — o mecanismo reativo
  continua como está, servindo de rede de segurança complementar.

## Testes

- `custom/spec/services/custom/scout/system_prompts_service_spec.rb`: novo `it` confirmando a
  presença do bullet "Reconhecimento de intenção fora de prospecção" em `guardrails_section`.
- Verificação comportamental (mesmo padrão de outras fases): replay via
  `Custom::Scout::PlaygroundRunner` de uma conversa onde o contato indica ser cliente existente com
  tratamento em andamento, ou responde "só uma dúvida rápida" a uma pergunta de triagem — a resposta
  final deve chamar `handover_to_human` sem tentar resolver a questão por conta própria.

## Critérios de aceite

- Um contato que indica claramente não estar buscando prospecção (cliente existente, tratamento em
  andamento, reagendamento, cancelamento, reclamação, "dúvida rápida" não relacionada a tratamento)
  recebe handoff imediato, sem o Scout tentar resolver a questão por conta própria.
- Quando uma ferramenta externa de status de cliente estiver configurada e o telefone disponível, o
  Scout pode consultá-la para reforçar a decisão — mas a ausência dela, ou a falta de confirmação
  positiva, não impede o handoff quando o próprio cliente já sinalizou intenção fora de prospecção.
- O mecanismo reativo do Response Auditor (Fase 12) continua funcionando sem alteração, como rede de
  segurança complementar.
