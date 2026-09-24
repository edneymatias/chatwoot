# Fase NN — [Título da fase, ex.: "Deduplicação de Envio no Worker de Notificação"] (Brief)

**Nota**: preenchido pelo operador (com apoio do agente) durante a investigação/design, antes do
`/speckit-specify`. Os comentários `<!-- -->` abaixo são andaime de preenchimento — apague cada um
ao concluir a seção correspondente; não devem sobreviver no documento final (mesma convenção do
`spec-template.md` do speckit: uma seção de exemplo/instrução existe para ser substituída, não para
ficar ao lado do conteúdo real).

**Status**: `[Preview | Draft | Pronto para speckit]`
**Data**: `[AAAA-MM-DD]`
**Master doc**: `[link para o doc mestre do ciclo/épico, ex.: "docs/planejamento/ciclo-3/roadmap.md §4" — remova esta linha se não houver doc mestre]`
**Depends on**: `[fase/doc relacionado + o porquê, ex.: "Fase 07 — introduziu o mecanismo questionado aqui" — remova se não houver dependência]`

---

## 1. Problema *(mandatory)*

<!--
  ACTION REQUIRED: evidência real, nunca hipotética. Formato mínimo: identificador rastreável
  (ticket/ID de request/conta/timestamp) + o que aconteceu, com trecho literal (log, mensagem,
  resposta) quando disponível. Para feature nova sem bug, troque o identificador de ocorrência por
  uma métrica objetiva de dor (ex.: contagem de commits/churn num arquivo, tempo gasto num fluxo).

  Exemplo (formato ilustrativo, não um caso real): "Ticket #4821, conta X, 14/03 09:10–09:14: o
  sistema de notificação enviou o e-mail de boas-vindas duas vezes ao mesmo usuário, 2 segundos de
  diferença entre os envios — log da fila mostra dois jobs enfileirados com o mesmo
  idempotency_key."
-->

[identificador rastreável (ticket/request/conta) + data/hora — o que foi observado, com trecho literal de conversa/log/query quando houver]

## 2. Diagnóstico / Causa raiz *(mandatory quando corrige comportamento existente; renomeie para "Contexto técnico" em feature greenfield)*

<!--
  ACTION REQUIRED: referência `arquivo:linha` para cada afirmação sobre o que o código faz hoje.
  Se houver mais de um caminho possível para o sintoma, elimine os outros por evidência (grep de
  log, comparação de campo persistido) antes de apontar a causa — não assuma a mais óbvia.

  Exemplo (formato ilustrativo): "NotificationDispatcher#enqueue
  (app/services/notification_dispatcher.rb:42) não verifica se já existe um job pendente com o
  mesmo idempotency_key antes de enfileirar — a checagem só acontece no worker, não no enqueue,
  então dois enqueues quase simultâneos passam pelo mesmo intervalo sem barreira."
-->

[arquivo.rb:linha — o que o código faz hoje e por que isso produz o problema da seção 1]

## 3. Precedente *(opcional — inclua só se houver arquitetura de referência valendo comparação)*

<!--
  ACTION REQUIRED: outro módulo do mesmo sistema, um padrão já estabelecido no codebase, ou
  produto/biblioteca externa. Declare o que é reaproveitável e o que não se aplica, e por quê —
  comparação inconclusiva é resultado válido e deve ser registrado como tal.

  Exemplo (formato ilustrativo): "O módulo de pagamentos do mesmo sistema já resolve duplicidade de
  requisição com uma chave de idempotência checada na escrita, não na leitura — mesmo padrão se
  aplica aqui; a diferença é que lá a checagem é síncrona (bloqueia a resposta HTTP) e aqui precisa
  ser assíncrona (o enqueue não pode esperar o worker)."
-->

[o que o precedente resolve, o que dele se aplica aqui, o que não se aplica e por quê]

## 4. Decisões *(mandatory)*

<!--
  ACTION REQUIRED: substitua a linha de exemplo pela(s) decisão(ões) real(is) da fase. Uma decisão
  por linha; inclua a alternativa rejeitada só quando houve uma real de fato considerada — não
  invente uma alternativa de palha para preencher a coluna. Use `[A CONFIRMAR: pergunta]` na célula
  de Justificativa quando a decisão ainda não está fechada (ver seção "Convenções" no rodapé).
-->

| # | Decisão | Justificativa |
|---|---|---|
| _ex._ | Checar `idempotency_key` na escrita (constraint UNIQUE na tabela de jobs), não só no worker | Fecha a janela de corrida entre dois enqueues quase simultâneos; alternativa considerada (lock distribuído via Redis) rejeitada por adicionar uma dependência nova a um problema que uma constraint de banco já resolve |
| 1 | [decisão] | [por quê — e alternativa rejeitada, se houve] |

## 5. Escopo preliminar *(mandatory)*

<!--
  ACTION REQUIRED: arquivos/áreas prováveis, concreto o bastante para o `/plan` ancorar — mas é
  preliminar por definição, quem fecha a lista definitiva é o `/plan`, não este doc.
-->

- [`app/services/arquivo.rb`: o que muda]

## 6. Fora de escopo *(mandatory)*

<!-- ACTION REQUIRED: exclusões explícitas — contém tanto o próprio entusiasmo do operador quanto scope creep do agente implementador. -->

- [o que fica de fora e por quê]

## 7. Critérios de aceite (rascunho) *(mandatory)*

<!--
  ACTION REQUIRED: observável/testável do ponto de vista de quem usa o sistema, não de
  implementação interna. É a matéria-prima que `/specify` transforma em User Story + Acceptance
  Scenarios (Given/When/Then) + Success Criteria; `/clarify` resolve qualquer ambiguidade que
  sobrar daqui.
-->

- [comportamento observável esperado]

## 8. Testes (rascunho) *(opcional, recomendado — Constitution VI/VIII: TDD não-negociável no projeto)*

<!-- ACTION REQUIRED: arquivo de spec provável + comportamento a fixar, não a implementação. -->

- [`custom/spec/.../arquivo_spec.rb`: comportamento a cobrir]

## 9. Questões em aberto *(opcional — só quando há bifurcação real ainda não decidida)*

<!--
  ACTION REQUIRED: registre a tensão dos dois lados, não uma decisão disfarçada de pergunta.
  Diferente de `[A CONFIRMAR: ...]` (seção 4) — isto é usado quando falta uma *decisão* entre
  opções conhecidas, não quando falta um *fato*.

  Exemplo (formato ilustrativo): "Vale adicionar um índice único de banco (mais simples, mas trata
  só duplicidade dentro do mesmo processo) ou migrar para uma fila com deduplicação nativa (mais
  robusto entre processos, troca de infraestrutura maior do que o problema justifica agora)? A
  favor do índice: resolve o caso observado com o menor blast radius. Contra: não cobre duplicidade
  entre workers de filas diferentes, se isso vier a acontecer."
-->

[pergunta em aberto + argumento dos dois lados]

---

> **Nota de proveniência**: `[como foi diagnosticado — simulação, consulta a produção, grep de log,
> etc.]`. Próximo passo: `[normalmente "Próxima entrega via speckit (/speckit-specify)"]`.

---

## Convenções deste template

<!-- Esta seção final é regra de preenchimento do documento, não conteúdo do brief — mantenha-a
     apenas no template, apague-a de cada brief preenchido. -->

- `[colchetes]` marcam campo a preencher; substitua pelo conteúdo real, não deixe o colchete.
- `[A CONFIRMAR: pergunta]` é o marcador sentinela deste template (equivalente ao `NEEDS
  CLARIFICATION` do speckit) — usa-se dentro de qualquer seção quando falta um fato para fechar a
  decisão. Não bloqueia o preenchimento do resto do doc; `/speckit-clarify`, ou uma revisão sua
  antes de rodar `/speckit-specify`, varre e resolve cada ocorrência.
- Seção marcada `*(mandatory)*` no heading sempre existe no doc preenchido, mesmo curta. Seção
  `*(opcional)*` que não se aplica **some** do documento final — nunca fica como heading vazio ou
  "N/A".
- Comentários `<!-- ACTION REQUIRED -->` e a linha `_ex._` da tabela de Decisões são andaime:
  apague-os ao preencher a seção correspondente.
