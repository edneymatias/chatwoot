# Fase 05 — Escalation, Exits e Desmonte do Auditor (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §4.1, §4.6 (exits e desmonte do auditor), §6 (Fase 1)
**Depends on**: Brief 04 — `open_playbook` já injeta os exits declarados pela playbook; este brief
entrega o mecanismo que os executa, e é o que autoriza o v2 a nascer sem auditor pós-hoc.

---

## 1. Problema

**A mesma regra escrita três vezes.** "Não faça perguntas ao transferir" aparece no bullet global
(`custom/app/services/custom/scout/system_prompts_service.rb:77`), é repetida em
`handoff_closing_reminder_section` (`:190-195`) e é injetada de novo no resultado da tool
(`opportunity_stage_transition_service.rb:9-11`, aplicada em `:47`). O comentário do próprio código
explica o motivo (`system_prompts_service.rb:185-189`): um bullet estático lido muitas mensagens
antes não é saliente o bastante sozinho.

**Correção estocástica empilhada.** Com o auditor ligado, um turno custa: chamada principal +
classificador a `0.0` (`response_auditor.rb:61`) + confirmação independente a `0.7` (`:77-82`) +
consistência de claims (`:29`) + reparo (`:87`) + reclassificação (`:90`) + reverificação (`:93`).
Piso de 3 chamadas de LLM, pior caso ~8. A dupla confirmação existe porque o próprio classificador
alucina: *"a customer picking one of several offered options … gets misread as 'accepted a
human-handoff offer' — confirmed 5/5 times"* (`:46-56`). A dupla confirmação a `0.7` é invenção do
fork — o Captain chama o classificador uma vez (design §1.3).

**Efeito colateral do reparo:** o loop pode disparar handoff e enviar duas mensagens
(`response_auditor.rb:96-103`).

## 2. Contexto técnico

- `custom/app/services/custom/scout/tools/move_opportunity_stage.rb` e
  `tools/handover_to_human.rb` — mutação de CRM e transferência oferecidas como tools em **todo**
  turno (`agent_runner.rb:145-155`), inclusive num turno de dúvida ou de pausa.
- `opportunity_stage_transition_service.rb:9-11,47` — `NO_QUESTION_CLOSING_INSTRUCTION` existe só
  para reforçar, no resultado da tool, uma regra que já está no prompt.
- `response_auditor.rb:29,46-56,61,71-93,96-103` — classificador, confirmação dupla, consistência
  de claims, reparo, reclassificação, reverificação.
- `agent_runner.rb:119-125` — `trigger_handoff` a partir da tool; `:133` — `reasoning` do
  `ResponseSchema` só alimenta log.
- **RubyLLM** (`chat.rb`, design §4.6): `handle_tool_calls` faz `halt_result || complete(&)` — um
  `RubyLLM::Tool::Halt` corta o loop e `ask` devolve o próprio Halt, **sem nova iteração**: o modelo
  nunca escreve a mensagem final e o cliente fica sem resposta.
- Fail-safes de infraestrutura que **não** são compensação de comportamento: quota, API key ausente,
  falha de parse → `perform_fail_safe_handoff`.

## 3. Precedente

- **Botpress**: `Exit` tem schema validado e hook que pode bloquear a saída (`dist/exit.d.ts`);
  `Escalation` é camada própria, com procedimento opcional antes do handoff
  (`llms-full.txt:9855-9859`). Aplica-se integralmente.
- **Captain V2**: `HandoffTool#perform` (`lib/captain/tools/handoff_tool.rb:26-40`) **retorna
  string, nunca `Halt`**, e devolve `failure_result` quando a conversa mudou sob ele — mesma regra
  que este brief prescreve. E o handoff é **sempre-on no agente raiz**
  (`enterprise/app/models/captain/assistant.rb:210-216`). Além disso, os classificadores pós-hoc
  rodam **só no caminho V1**: `jobs/captain/conversation/response_builder_job.rb:22` bifurca, `:45-46`
  roda classificador de ação + reparo de falsa promessa, `:50-61` (V2) não roda nenhum dos dois.
  Confirma que remover auditor ao trocar para desfecho declarado é caminho já percorrido upstream.
- **Literatura**: auto-crítica sem oráculo externo degrada em vez de melhorar (Huang et al., ICLR
  2024; Stechly et al., arXiv:2402.08115) — design §4.10.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | Toda **tool de mutação é escopada**; `move_opportunity_stage` e `handover_to_human` deixam de existir como tool | Transição e transferência são **desfecho**, e desfecho é exit decidido em Ruby; manter a tool ao lado do exit seria manter dois caminhos para o mesmo efeito, escolhidos por sorteio (design decisão 12) |
| 2 | **`exit_handoff` é sempre-on**, junto com a camada `Escalation` | Instrução sempre-on exige mecanismo sempre-on: com `Safety` mandando escalar, um estado sem playbook ativa deixaria o pedido mais literal do cliente ("quero falar com uma pessoa") dependendo de dois saltos estocásticos (`open_playbook` → `exit_handoff`). O Captain V2 faz o mesmo (design §4.1) |
| 3 | O handler de exit **devolve texto, nunca `Tool::Halt`** | Com `Halt`, `ask` retorna sem nova iteração e o cliente fica sem resposta (design §4.6). O efeito é persistido no handler; a mensagem sai da iteração seguinte, dentro do `ResponseSchema` |
| 4 | Payload de exit é **validado em Ruby**; inválido volta como erro de tool | A correção acontece dentro do mesmo `chat.ask`, antes de qualquer coisa chegar ao cliente — sem chamada de topo extra (design §4.6) |
| 5 | **Turno sem exit é o caso normal** | Responder e aguardar o cliente é o `ListenExit` implícito; exit só existe onde há desfecho |
| 6 | **V2 nasce sem auditor pós-hoc** | Não é remoção de verificação: é troca de verificação estocástica por estrutural. Carregar também a compensação estocástica contraria o `AGENTS.md` (*"Do not add speculative guards … unless production has proven it necessary"*). Volta com evidência, e cirúrgica (design decisão 9 e §6.7) |
| 7 | A regra de handoff é entregue **uma única vez**, no resultado do exit | Consolida as três cópias atuais; o Ruby sabe que o turno termina em transferência, o prompt não precisa lembrar disso em todo turno |

## 5. Escopo preliminar

- `custom/app/services/custom/scout_v2/exits/handler.rb` + uma classe por espécie: terminal
  (encerra o turno), transição (ativa outra playbook), escalação (dispara `HandoffService`).
- Validação de payload a partir das assinaturas declaradas no frontmatter (`exits:`).
- `custom/app/services/custom/scout_v2/instructions/escalation.rb`: `when_to_escalate` +
  `procedure_before_handoff`, sempre-on.
- `exit_handoff` registrado sempre-on no `TurnRunner`.
- `custom/app/services/custom/scout_v2/response_schema.rb`: sem `reasoning`.
- Tools escopadas do v2: `update_contact`, `manage_opportunity` — sem `move_opportunity_stage`, sem
  `handover_to_human`, sem `call_custom_api`.
- Reuso de `Custom::Scout::HandoffService` e da transição de estágio como **efeito**, chamados do
  handler (sem `NO_QUESTION_CLOSING_INSTRUCTION` no caminho v2).

## 6. Fora de escopo

- Remover ou alterar `ResponseAuditor`, `ActionClassifierService` e `ClaimConsistencyService` **do
  v1**: eles continuam existindo e rodando para scouts em `engine: v1`. O v2 apenas não os chama.
  A remoção física é da depreciação (brief 10).
- Fail-safes de infraestrutura (quota, API key, falha de parse): permanecem, inclusive no v2 —
  são falha de sistema, não compensação de comportamento.
- Rede de segurança **fora do turno** (formato `InboxPendingConversationsResolutionJob` do
  Captain): explicitamente adiado para o item 6.7 do design.
- Diretriz anti-falsa-promessa: continua no prompt (`Safety`), porque promessa futura sem ação ("te
  aviso amanhã") é genuinamente global e não é coberta por exit.

## 7. Critérios de aceite (rascunho)

### US1 — Escalation é camada, e escalar é sempre possível

- O prompt sempre-on contém `when_to_escalate` e `procedure_before_handoff`.
- Um pedido explícito de atendente humano **sem playbook ativa** resulta em transferência no mesmo
  turno, com mensagem ao cliente — sem depender de abrir playbook antes.
- A instrução de como encerrar ao transferir chega ao modelo **uma vez**, no resultado do exit; o
  prompt sempre-on não a repete e o resultado de transição de estágio não a repete.

### US2 — Exit com payload validado em Ruby

- Um exit declarado no frontmatter da playbook ativa está disponível ao modelo como tool.
- Payload que viola a assinatura declarada volta como erro de tool e o modelo corrige **dentro do
  mesmo `chat.ask`**, sem chamada de topo adicional e sem nada enviado ao cliente.
- Payload válido executa o efeito e o handler devolve **texto**; o cliente recebe a mensagem final,
  escrita na iteração seguinte.
- Exit terminal encerra a playbook ativa; exit de transição ativa a playbook de destino com
  `activation_reason: transition`; exit de escalação dispara o handoff.
- Turno que termina sem exit não persiste desfecho nenhum e a playbook ativa permanece.

### US3 — Desfecho em Ruby substitui as tools de mutação

- No v2, `move_opportunity_stage` e `handover_to_human` não são oferecidas ao modelo em nenhum
  turno, com ou sem playbook ativa.
- Transição de estágio só acontece por exit, com os campos obrigatórios validados antes da escrita.
- Uma mensagem de cliente, sozinha, não produz exit — o modo de falha 5/5 do classificador
  ("escolheu uma opção" lido como "aceitou transferência") torna-se estruturalmente impossível.

### US4 — O caminho v2 roda sem auditor

- Um turno v2 completo faz **uma** chamada de LLM de topo (contra 3 no piso e ~8 no pior caso do
  v1 com auditor).
- `ResponseAuditor`, `ActionClassifierService` e `ClaimConsistencyService` não são invocados em
  nenhum ponto do caminho v2.
- O `ResponseSchema` do v2 não tem `reasoning`.
- Quota estourada, API key ausente ou falha de parse continuam levando ao handoff de fail-safe.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/exits/handler_spec.rb`: payload inválido → erro de tool sem
  efeito persistido; payload válido → efeito + retorno de **string** (asserção explícita de que não
  é `RubyLLM::Tool::Halt`); as três espécies de exit.
- `custom/spec/services/custom/scout_v2/turn_runner_spec.rb`: catálogo de tools sem
  `move_opportunity_stage`/`handover_to_human`/`call_custom_api`, com `exit_handoff` presente mesmo
  sem playbook ativa; contagem de chamadas de LLM de topo igual a 1.
- Flow test por exit (com capabilities dubladas): verifica **mensagem final ao cliente além do
  efeito** — é o teste que cobre o risco do `Halt` (design §8).
- Verificação no playground: pedido de humano sem playbook ativa transferindo corretamente.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §4.1, §4.6 e §4.10; as
> contagens de chamadas e o modo de falha 5/5 estão em
> `custom/app/services/custom/scout/response_auditor.rb:29,46-56,61,71-103`; o comportamento de
> `Halt` foi lido em `ruby_llm-1.15.0/lib/ruby_llm/chat.rb`.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
