# Fase 35 — Laço de Repair do Auditor Vaza Narrativa Interna para o Cliente e Duplica a Chamada de Handoff (Preview)

**Status**: Preview — problema real identificado em simulação de teste (conversation_id 134 /
display_id 133, conta 1 "Acme Inc", Scout "VItória"); especificação completa e implementação ficam
para o momento oportuno, a critério do operador.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 12 (`12-response-auditor/spec78.md`) — introduziu o `ClaimConsistencyService` e
o laço `execute_repair`/`reverify_consistency` (`response_auditor.rb`) que é o objeto desta fase.
Fase 20 (`20-automatic-handoff-reevaluation/spec80.md`) — estabeleceu que o texto de encerramento
que o próprio modelo escreve deve virar a mensagem pública de handoff (`message: reply_text` em
`AgentRunner#trigger_handoff`); esta fase mostra um caso onde esse texto, na prática, não é mais o
que o modelo escreveu para o cliente, e sim um artefato do laço de repair interno. **Relacionado,
mas causa raiz distinta** da Fase 33 (`33-response-auditor-handoff-message-quality/spec-preview.md`):
a Fase 33 é sobre o `ActionClassifierService` (motivo de 4 valores fechados, caminho
`ResponseAuditor#execute_handoff`) classificar errado um `out_of_scope_commercial_request`; esta
fase é sobre o caminho 1 de handoff (tool `handover_to_human`, chamado pelo modelo principal) sendo
corrompido *depois* de já ter decidido corretamente transferir — o classificador da Fase 12 nunca
roda neste caminho (`evaluate_action` retorna `nil` quando `handoff_already_flagged`,
`response_auditor.rb:57-59`).

---

## Contexto: pergunta de preço vira handoff correto, mas a mensagem final é uma confissão de confusão que nunca existiu

Reproduzido na conversa 134 (display_id 133, conta 1 "Acme Inc", Scout "VItória", inbox de teste do
widget): cliente informa nome e telefone, depois pergunta `"quanto tá a limpez de vcs?"` (msg 293,
13:58:50). A resposta entregue (msg 294, 13:59:13) é:

> *"Gandalf, o sábio, obrigado por aguardar e desculpe pela confusão antes. Já deixei seu
> atendimento a cargo da nossa equipe humana, que vai continuar a conversa com você e informar
> direitinho o valor da limpeza e demais detalhes que precisar. [...]"*

E a nota interna de transferência (msg 295, mesmo timestamp):

> *"📋 Transferência para atendimento humano: Encaminhar para equipe humana para informar valores de
> limpeza, conforme política da conta. Correção de turno anterior: garantir que a transferência
> seja de fato executada."*

Do ponto de vista do cliente, essa foi a **primeira e única** resposta do assistente ao pedido de
preço — não existiu nenhum "turno anterior" confuso na conversa real. O "desculpe pela confusão
antes" e a "correção de turno anterior" não têm nenhum referente visível no histórico.

## Evidência do problema

### 1. A decisão de transferir, na primeira chamada ao modelo, estava correta e já registrada

Log do `AgentRunner` (Sidekiq, job `859ac9c6295823b90f381151`) mostra o `reasoning` capturado logo
após a primeira resposta estruturada ser parseada (`AgentRunner#parse_structured_response`,
`agent_runner.rb:133`, chamado **antes** de `process_audited_reply`/`ResponseAuditor#audit`):

```
13:59:05 [Scout AgentRunner] reasoning: Usuário fez pergunta pontual de preço (limpeza). Pelas
instruções, dúvidas administrativas como valores devem ser encaminhadas para humano via
handover_to_human, já acionado. Agora preciso apenas encerrar cordialmente, sem novas perguntas.
```

Ou seja: a tool `handover_to_human` já tinha sido chamada com sucesso nesta primeira passada
(`@handoff_needed = true`, `handover_to_human.rb:21-24`), com um motivo coerente ("informar valores
de limpeza, conforme política da conta") e sem nenhuma menção a confusão ou correção. A mensagem
final enviada ao cliente (13:59:13, ~8s depois) já é outra — confirmando que algo rodou **entre** o
log de reasoning e o envio.

### 2. O único lugar que injeta a narrativa "resposta anterior não executada" é a instrução de repair da Fase 12

`ResponseAuditor::REPAIR_INSTRUCTION` (`response_auditor.rb:10-13`):

```ruby
REPAIR_INSTRUCTION = <<~INSTRUCTION
  ATENÇÃO: Sua resposta anterior afirmou que uma ação foi concluída ou prometeu uma ação futura,
  mas a ação não foi executada com sucesso pelas ferramentas disponíveis.
  Por favor, reavalie: se a ferramenta adequada estiver disponível e couber executá-la agora,
  execute-a; caso contrário, responda ao cliente de forma transparente sem afirmar ou prometer
  ações que não foram realizadas.
INSTRUCTION
```

O enquadramento ("sua resposta anterior... a ação não foi executada... garanta que seja executada")
bate exatamente com o texto que acabou saindo ("correção de turno anterior: garantir que a
transferência seja de fato executada"). Isso só é enviado por `execute_repair(chat)`
(`response_auditor.rb:152-155`), chamado de dentro de `perform_repair_and_reverify`
(`response_auditor.rb:84-94`), que só roda quando `check_claim_consistency` (`ClaimConsistencyService`)
classifica a resposta original como não seguro/inconsistente (`consistency_safe_or_unclear?` ==
`false`, `response_auditor.rb:29-32`).

### 3. `evaluate_action` pula o classificador, mas `check_claim_consistency` não é pulado quando o handoff já foi sinalizado por tool

`ResponseAuditor#audit` (`response_auditor.rb:22-35`):

```ruby
def audit(chat:, response_text:, message_history:, recorded_tool_calls:, available_tool_names: [])
  return { action: :proceed, reply: response_text } unless conversation_pending?

  action_outcome = evaluate_action(message_history)   # pulado: @handoff_already_flagged == true
  return action_outcome if action_outcome
  return { action: :proceed, reply: response_text } unless conversation_pending?

  consistency_result = check_claim_consistency(...)    # SEMPRE roda aqui
  return { action: :proceed, reply: response_text } if consistency_safe_or_unclear?(consistency_result)

  perform_repair_and_reverify(...)
```

O segundo `unless conversation_pending?` não protege este caso: `HandoffService.perform` (que muda o
status da conversa e sai de `pending`) só é chamado depois, em `AgentRunner#trigger_handoff`
(`agent_runner.rb:119-125`) — **depois** que `audit()` já retornou. No momento em que
`check_claim_consistency` roda, a conversa ainda está `pending`, mesmo com o handoff já decidido pela
tool. Ou seja: toda vez que o modelo decide um handoff via `handover_to_human` (caminho 1), a
resposta final passa pelo `ClaimConsistencyService` antes de ser entregue — só o classificador de
ação (Fase 12) é pulado, não o verificador de consistência.

### 4. `ClaimConsistencyService` tem acesso à tool call já bem-sucedida, e mesmo assim marcou como inconsistente

`recorded_tool_calls` (via `Custom::Scout::Tools::CallRecorder`, `call_recorder.rb:4-6,30-31`) já
contém o registro da chamada `handover_to_human` com `status: SUCCESS` e o resultado padrão da tool
(`"A transferência será confirmada após sua resposta final..."`, `handover_to_human.rb:26`), e é
passado ao prompt do `ClaimConsistencyService` via `<recorded_tool_calls>`
(`claim_consistency_service.rb:44-46,70-76`). Mesmo com essa informação disponível, o veredito desta
chamada específica foi "inseguro/inconsistente" — disparando o repair. Não há log do conteúdo bruto
desta chamada (nenhuma das duas classes tem logging equivalente ao `reasoning` do `AgentRunner`), e
a resposta da própria chamada de repair também não é logada: `execute_repair`/`parse_repaired_content`
(`response_auditor.rb:152-166`) extrai só o campo `response` do JSON reparado, descartando qualquer
`reasoning` que ele tenha produzido — este caminho é hoje completamente invisível em log, ao
contrário do caminho principal.

### 5. O repair fez o modelo chamar `handover_to_human` uma segunda vez, sobrescrevendo o motivo original

A instância da tool é mutável e persiste no mesmo `chat` entre a chamada original e a chamada de
repair (mesmo objeto, `@handoff_reason` sobrescrito a cada `execute`, `handover_to_human.rb:16-24`).
`AgentRunner#trigger_handoff` (`agent_runner.rb:119-125`) só lê `tool.handoff_reason` e monta a
`HandoffService` **uma vez**, no fim de todo o turno — com o valor que a tool tiver no momento, ou
seja, o da **última** chamada. O motivo final observado ("...conforme política da conta. Correção de
turno anterior: garantir que a transferência seja de fato executada.") é consistente com o modelo,
ao processar o `REPAIR_INSTRUCTION`, reinterpretando "a ação não foi executada" como um convite para
chamar a tool de novo "para garantir" — mesmo a primeira chamada já tendo sido bem-sucedida.
`HandoffService.perform` (`handoff_service.rb:9-17`) só executa de fato uma vez (idempotente por
checar `status == 'pending'`, `handoff_service.rb:32-39`), então não há duplicação de assignment —
mas a mensagem pública e a nota internas usadas são as da chamada reparada, não da original.

## Comportamento correto, para contraste

Comparando com uma pergunta de preço análoga em outra simulação da mesma conta (conversation_id não
capturada no log de forma isolada, mas com `reasoning` distinto no mesmo período de teste):

> *"Sem informação de preço na base; preciso evitar chutar valores. Explico a limitação, reforço
> que o valor é definido na avaliação e mantenho o fluxo comercial [...]"*

Aqui o modelo não chamou `handover_to_human` — respondeu e seguiu qualificando. Essa variância entre
as duas simulações é causada por um problema separado e não-código (ambiguidade da persona
configurável sobre o que conta como "dúvida administrativa" — fora do escopo desta fase, tratável
diretamente pelo operador editando `Scout#persona`). O que esta fase cobre é estritamente o que
acontece **depois** que o modelo decide transferir: o laço de repair corrompendo esse turno.

## Decisões de desenho (a confirmar na especificação completa)

1. **Pular `check_claim_consistency` quando o handoff já foi sinalizado por tool nesta rodada**,
   espelhando exatamente a mesma lógica e o mesmo comentário já usados para pular o classificador de
   ação (`evaluate_action`, `response_auditor.rb:46-56`, `@handoff_already_flagged`): se uma tool já
   decidiu deterministicamente que o turno termina em handoff, não há "promessa não cumprida" a
   verificar — o resultado da tool (`SUCCESS`) já é a prova de execução. Evita tanto a segunda
   chamada ao modelo quanto a narrativa de "correção" vazando pro texto final.
2. Alternativa mais conservadora (se o operador preferir manter alguma verificação pós-handoff):
   manter `check_claim_consistency` rodando, mas **nunca reenviar ao mesmo `chat`** via
   `execute_repair` quando o handoff já foi sinalizado — em vez disso, cair direto no fallback fixo
   já existente (`I18n.t('conversations.scout.handoff')`) se o veredito for inconsistente, sem dar
   ao modelo a chance de chamar a tool de novo. Decisão entre as duas fica para a especificação
   completa — a primeira é mais simples e mais alinhada ao padrão já estabelecido no arquivo.
3. **Logar o resultado de `execute_repair`** (motivo/reasoning, não só o `response`), para que este
   caminho deixe de ser uma caixa-preta em produção — mesmo padrão de observabilidade já usado pelo
   `AgentRunner` (`agent_runner.rb:133`) e pela Fase 17.

## Escopo preliminar (a confirmar na especificação completa)

- `custom/app/services/custom/scout/response_auditor.rb`: condicionar `check_claim_consistency`
  (ou `perform_repair_and_reverify`) a `@handoff_already_flagged`.
- Possível logging adicional em `execute_repair`/`parse_repaired_content`.

## Fora de escopo desta fase (preview)

- Ambiguidade da persona sobre "dúvida administrativa" cobrir ou não perguntas de preço — resolúvel
  diretamente pelo operador editando `Scout#persona` (`custom_instructions_section`), sem mudança de
  código; não é o objeto desta fase.
- `ActionClassifierService`/`out_of_scope_commercial_request` (Fase 33) — caminho de código
  totalmente diferente, nem executado neste cenário.
- Qualquer mudança na mensagem fixa de fallback (`conversations.scout.handoff`) ou no texto padrão de
  nota (`HandoffService#default_handoff_message`) — permanecem como estão.
- Mudanças de código agora — este documento só registra o diagnóstico para tratamento futuro, a
  critério do operador.

## Testes (rascunho)

- `custom/spec/services/custom/scout/response_auditor_spec.rb`: novo `it` cobrindo que, quando
  `handoff_already_flagged: true`, `audit` retorna `{ action: :proceed, reply: response_text }` sem
  chamar `ClaimConsistencyService`/`execute_repair` — mock/expect `check_claim_consistency` nunca
  invocado.
- Regressão: `it` existente cobrindo o caso descrito no comentário de `reverify_consistency`
  (`response_auditor.rb:96-103`, repair triggerando um handoff **novo**, não sinalizado antes) deve
  continuar passando — este caso é de um handoff que só nasce durante o repair, não um handoff já
  sinalizado sendo reprocessado.
- Verificação comportamental via `Custom::Scout::PlaygroundRunner`: replay de uma pergunta de preço
  levando o modelo a chamar `handover_to_human` — mensagem pública final deve ser exatamente o texto
  que o modelo escreveu na primeira resposta, sem menção a "turno anterior"/"correção"/"confusão".

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Um turno em que o modelo chama `handover_to_human` e já escreve uma mensagem de encerramento
  coerente não é mais reprocessado por `ClaimConsistencyService`/repair — a mensagem pública e a nota
  interna usam exatamente o texto e o motivo da chamada original da tool.
- Nenhuma regressão no caminho onde o repair genuinamente precisa rodar (resposta que promete ação
  sem nenhuma tool ter sido chamada) — continua funcionando como hoje.
- O caso descrito em `reverify_consistency` (repair fazendo o modelo decidir handoff que não tinha
  sido sinalizado antes) continua funcionando sem regressão.

---

> **Nota**: Preview criado a partir de simulação real de teste (conversation_id 134 / display_id 133,
> conta 1 "Acme Inc", Scout "VItória"), com diagnóstico de causa raiz confirmado por correlação
> textual entre `REPAIR_INSTRUCTION` e o conteúdo final observado, e por eliminação contra os
> caminhos de handoff possíveis (classificador da Fase 12 não roda neste caminho por desenho; texto
> final não bate com nenhum fallback fixo existente). Sem acesso ao conteúdo bruto da chamada do
> `ClaimConsistencyService` nem da resposta de repair (nenhuma das duas é logada hoje — ponto 3 das
> Decisões de desenho). Tratamento completo adiado para o momento oportuno, a critério do operador —
> ver `spec60.md` §11. Próxima entrega via speckit, mesmo fluxo das fases 26, 23, 29, 32 e 33.
