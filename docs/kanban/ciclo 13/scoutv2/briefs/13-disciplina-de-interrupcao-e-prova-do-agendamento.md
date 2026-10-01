# Fase 13 — Disciplina de Interrupção e Prova Definitiva do Agendamento (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-30
**Master doc**: `docs/kanban/ciclo 13/scoutv2/design.md` §4.4 ("Interrupção por trigger", "A metade
por-trigger é um componente substituível"), §4.3 (redação do `trigger`), §4.9, §6 (Fase 2, prova)
**Depends on**: Brief 11 (interrupção por trigger e takeover), Brief 06 (as playbooks cujos gatilhos e
corpo mudam aqui) e Brief 07 (spec `089-scout-v2-capabilities-scheduling`), aprovado em 2026-09-30
com a prova no playground contra o ERP real (US3-AS14, SC-010, task T054) **transferida para este
brief**.
**Ordem de execução**: depois do 07 e antes do 10. O 10 promove contas reais ao v2 e pressupõe o
agendamento provado.

---

## 1. Problema

Teste manual no playground, conta 1, scout 1, conversa 147 (sessão Langfuse `1_147`), 2026-09-30
18:56–19:03 UTC. Quatro mensagens do lead, e `open_playbook` foi chamada em **três** turnos, nenhuma
delas por um sinal da própria mensagem:

| Turno (trace) | Mensagem do lead | Fixada por estado | Tool calls | Efeito |
|---|---|---|---|---|
| `569ecb22…` 18:56:38 | "olá!" | `identificacao` | `update_contact(name: "")` → `open_playbook(fora_de_prospeccao)` | cumprimento abriu interrupção |
| `185e53a4…` 18:57:00 | "tenho interesse em implantes." | `identificacao` | `open_playbook(duvida_comercial)` → `search_knowledge_base` | takeover tirou o corpo de `identificacao`; nome não pedido |
| `31ac0f84…` 18:59:45 (33,0s) | "tenho um dente faltando lá atrás." | `identificacao` | `update_contact({})` → `exit_identificado` → `manage_opportunity(create)` | saiu da identificação sem pedir nome nem telefone |
| `6f729847…` 19:02:48 | "mastigação." | `qualificacao` | `open_playbook(duvida_comercial)` → `search_knowledge_base` | resposta à pergunta de qualificação tratada como dúvida |

Consequências observadas no banco e no trace:

1. **Dado de qualificação perdido.** "mastigação." respondia literalmente à pergunta do turno anterior
   (*"qual é a principal dificuldade… (mastigar, machucar a gengiva, incomodar esteticamente…)?"*). Com
   a interrupção aberta, `manage_opportunity` saiu do catálogo e `Opportunity#142` ficou só com
   `custom_attributes: {"interesse" => "Implantes"}` — `queixa_principal` não foi gravada.
2. **Desvio do funil.** Sob `duvida_comercial`, o modelo buscou por conta própria
   `"implante dentário, avaliação, agendamento, política comercial"`; a base devolveu *"O agendamento
   é feito por telefone ou WhatsApp"* e a resposta ao lead foi *"Você prefere que eu te passe o número
   de contato da clínica ou deseja que eu te direcione para o WhatsApp de agendamento?"*.
3. **Identificação encerrada sem ter acontecido.** `ScoutConversationState#4`:
   `completed_playbooks: ["identificacao"]`, contato 199 ainda com nome provisório
   (`lindo-peixe-123`) e `phone_number: nil`. Pela regra de "tentado, não recusado" (design §4.4), a
   identificação não volta nesta conversa; `agendamento` nunca é fixada por estado
   (`contact_has_phone`) e, pela transição de `qualificado`, termina em `exit_handoff` por telefone
   ausente.
4. **Latência não atribuível.** O turno de 33,0s teve 4 roundtrips; os intervalos entre eventos do
   trace foram 2,1s / 0,9s / **27,9s** / 2,2s. A demora está inteira no roundtrip que recebeu o corpo
   de `qualificacao` e decidiu criar a oportunidade, mas o trace tem uma única `GENERATION` agregada
   por turno — não há como dizer se foi latência do provedor, retry do RubyLLM
   (`RubyLLM.config.max_retries == 3`) ou outra coisa.

E a prova da Fase 2 (design §6: *"agendamento ponta a ponta no playground, com IDs vindos do hook"*)
não foi executada: o hook `younus` da conta 1 (`Integrations::Hook#4`) tem só `token` e `id_empresa`,
e `Capabilities::Registry.resolve` devolve insatisfeita para `scheduling` e `customer_registry`.

## 2. Diagnóstico / Causa raiz

- **Gatilhos casam por tópico, não por sinal.** `custom/playbooks/duvida_comercial.md:5-8`: *"Um lead
  em prospecção pergunta sobre produto, serviço, preço…"*. Numa clínica, toda mensagem do lead fala de
  um serviço; "mastigação." nem é pergunta. `custom/playbooks/fora_de_prospeccao.md:5-9` inclui
  *"faz uma pergunta puramente informativa sem interesse de compra"*, amplo o bastante para capturar
  um cumprimento. Nenhum dos três gatilhos exclui a resposta a uma pergunta que o próprio assistente
  acabou de fazer.
- **A tool convida o uso.** `custom/app/services/custom/scout_v2/tools/open_playbook.rb:7`:
  *"Open a playbook by name from the playbook index to activate its procedure and tools"* — nenhuma
  condição. `open_playbook` é oferecida em todo turno com interrupção no catálogo
  (`turn_scope.rb:95`, brief 11 decisão 2), e o índice entra nas instruções acima do corpo fixado
  (`turn_runner.rb:80-89`).
- **Falso positivo custa dado, não só um turno.** O takeover (`open_playbook.rb:33-41` →
  `turn_scope.rb:63-66`) troca instruções e catálogo pelo baseline mais a interrupção. É o desenho
  do brief 11 (decisão 4) e continua correto para interrupção legítima; o problema é a taxa de
  aberturas indevidas, que transforma esse custo aceito em perda recorrente.
- **`identificacao` sai sem ter pedido.** O corpo (`custom/playbooks/identificacao.md`, última linha)
  condiciona `exit_identificado` a *"todos os dados faltantes tiverem sido solicitados uma vez"*, mas
  a condição depende da leitura que o modelo faz do histórico. Nos turnos 1 e 2 o corpo nem estava
  nas instruções no momento da resposta (takeover); no turno 3 o modelo leu "já houve conversa
  suficiente" e saiu.
- **Evidência que o design pedia.** O design §4.4 adiou o classificador de intenção porque *"não há
  evidência de que `open_playbook` erre"*. Esta conversa é a evidência: 3 aberturas em 4 turnos,
  nenhuma legítima.
- **Instrumentação por turno, não por roundtrip.** `turn_runner.rb:138-141` envolve o `chat.ask`
  inteiro em um `instrument_llm_call`; o loop de tools do RubyLLM (`chat.rb`, `handle_tool_calls` →
  `complete`) roda dentro dele sem span próprio. O RubyLLM expõe `on_new_message`/`on_end_message`
  (`chat.rb:116-122`), que delimitam cada completion.

## 3. Precedente

- **Design §4.3, redação do `trigger`**: *"Quando duas são semanticamente vizinhas…, o trigger declara a
  exclusão"*. A correção aqui é a mesma convenção, estendida à exclusão que faltou: a resposta do lead
  a uma pergunta do assistente.
- **Captain V2**: o índice de scenarios entra como `- {title}: {description}, use handoff_to_{key}`
  (`assistant.liquid:82-84`) e a `description` é o gatilho (≤ 500 chars). Mesmo formato do nosso
  índice; não há lá regra melhor a copiar — o Captain roteia 100% por LLM e tem o mesmo modo de falha
  em potencial.
- **v1**: `ActionClassifierService` tentou resolver erro de classificação com uma segunda chamada a
  `0.7` e alucinou 5/5 (design §1.1). Não se aplica: a correção aqui é na origem da decisão, não um
  verificador depois dela (design decisão 9).

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | O critério de abertura fica **onde a decisão é tomada**: nos gatilhos do índice e na `description` de `open_playbook`, não no corpo de cada procedimento | Um ponto só cobre `identificacao`, `qualificacao` e `agendamento` (ex.: "terça de manhã" dentro do agendamento). Alternativa considerada — regra de "resposta direta não abre playbook" dentro de `qualificacao.md` — rejeitada por cobrir um procedimento só e por exigir cópia em cada corpo, o padrão de regra repetida que o design §1.1 critica |
| 2 | Regra de abertura: interrupção só abre por **sinal da última mensagem do lead** (uma pergunta, um pedido, uma reclamação, um pedido de pausa); cumprimento e resposta a uma pergunta que o assistente acabou de fazer **nunca** abrem playbook | É a distinção que faltou nos três casos do §1 |
| 3 | Apertar os gatilhos é o **primeiro** remédio; o classificador de intenção (design §4.4, componente substituível) continua fora, com gatilho declarado: se o replay (US1) ou o Langfuse mostrarem abertura indevida persistente depois desta fase, ele é a próxima entrega | O design pediu evidência e agora ela existe, mas o remédio mais barato ainda não foi tentado. O classificador custa uma chamada a mais por turno |
| 4 | `identificacao` ganha condição de saída **observável no histórico**: o nome só conta como pedido se uma mensagem anterior do assistente o pediu; o telefone é pedido na resposta do mesmo turno em que o exit é chamado | Sem essa âncora, "já solicitado" vira juízo do modelo sobre a conversa inteira, que é o que falhou no turno 3 |
| 5 | Sem precondição em Ruby para `exit_identificado` | O pedido do último dado sai na resposta do **mesmo** turno do exit (depois dele), então não existe fato persistido para verificar no momento da chamada. Verificar o texto do histórico seria heurística sobre redação — o tipo de verificação estocástica que o design decisão 9 trocou por estrutural |
| 6 | Instrumentação: **uma `GENERATION` por completion** do loop de tools, filha do span do turno, com latência, tokens e tool calls pedidas | É o que torna os 27,9s do §1 atribuíveis. Fica no `TurnRunner` (arquivo do fork), via callbacks do RubyLLM; `lib/integrations/llm_instrumentation.rb` (upstream) não muda |
| 7 | A prova no playground contra o ERP real do brief 07 (spec 089, US3-AS14, SC-010, T054) é **critério de aceite deste brief** | Decisão do usuário em 2026-09-30: o 07 foi aprovado pelo código e pela verificação roteirizada; a prova definitiva roda aqui, depois de US1 e US2, que são pré-condição para uma conversa chegar ao agendamento com telefone |

## 5. Escopo preliminar

- `custom/playbooks/duvida_comercial.md`, `custom/playbooks/fora_de_prospeccao.md`,
  `custom/playbooks/pausa.md`: gatilhos reescritos com a regra da decisão 2 e as exclusões
  explícitas (cumprimento; resposta a pergunta do assistente).
- `custom/app/services/custom/scout_v2/tools/open_playbook.rb`: `description` com a condição de uso.
- `custom/playbooks/identificacao.md`: condição de saída ancorada no histórico (decisão 4).
- `custom/app/services/custom/scout_v2/turn_runner.rb`: uma geração por completion (decisão 6).
- Specs que fixam invariantes de corpo/gatilho das playbooks entregues (`playbook/catalog_spec.rb` e
  `playground_first_cut_catalog_spec.rb`, ver brief 06/07): cutover para os novos textos.
- Operacional, sem código (pré-requisito da prova herdada, §7):
  - settings do hook `younus` da conta de teste com os sete identificadores (spec 089 FR-010;
    `quickstart.md` §4 passo 1), apontando para empresa/agenda de teste;
  - artigo da base *"Como é o processo de agendamento?"* (hoje: *"O agendamento é feito por telefone
    ou WhatsApp"*) substituído por fonte `kind: faq` autoral coerente com o agendamento pelo
    assistente (design §4.7, "Correção de conteúdo derivado errado").

## 6. Fora de escopo

- Classificador de intenção no lugar de `open_playbook` (decisão 3; design §4.4).
- Mudar a semântica do takeover (brief 11 decisão 4): uma mensagem que responde à qualificação **e**
  traz uma dúvida legítima continua abrindo a interrupção e perdendo a resposta naquele turno. Custo
  aceito pelo design §4.4; volta com evidência de frequência.
- Reduzir a latência do roundtrip lento: esta fase só a torna atribuível. Corrigir sem diagnóstico
  seria chute.
- Qualquer mudança em capabilities, adapter, registry ou `agendamento.md` (brief 07). Se a prova
  herdada achar defeito lá, ele entra nesta fase como correção, com evidência do trace.
- Qualquer alteração no v1.

## 7. Critérios de aceite (rascunho)

### US1 — Interrupção só por sinal da última mensagem

- Com procedimento fixado, uma mensagem que responde a pergunta feita pelo assistente no turno anterior
  ("mastigação.", "faz tempo", "sábado de manhã") não chama `open_playbook`; a resposta é registrada
  pelo procedimento em curso (ex.: `queixa_principal` gravada via `manage_opportunity`).
- Um cumprimento ("olá!", "bom dia") não chama `open_playbook`.
- Pergunta própria do lead ("quanto custa?", "vocês parcelam?") continua abrindo `duvida_comercial`;
  reclamação de cliente existente continua abrindo `fora_de_prospeccao`; "vou pensar" continua
  abrindo `pausa`.
- Replay no playground do roteiro do §1 (as quatro mensagens, na ordem), 5 execuções: 0 chamadas de
  `open_playbook` nos turnos 1, 3 e 4, e `queixa_principal` gravada na oportunidade em todas.

### US2 — Identificação só sai depois de pedir

- Com nome provisório e sem telefone, o nome é pedido antes de qualquer `exit_identificado`, e o
  telefone é pedido em mensagem separada (regra atual do corpo, mantida).
- `exit_identificado` só é chamado no turno em que o último dado faltante é pedido na resposta, ou
  depois dele — nunca antes de o nome ter sido pedido numa mensagem anterior do assistente.
- No replay da US1, a identificação termina com o nome e o telefone pedidos uma vez cada; se o lead os
  fornece, `update_contact` os grava e `contact_has_phone` passa a valer.

### US3 — Roundtrip atribuível no trace

- Um turno com N completions no loop de tools gera N observações `GENERATION` no Langfuse, filhas do
  span do turno, cada uma com início, fim, tokens e as tool calls que pediu.
- A soma das latências das gerações mais as spans de tool explica a latência do turno (sem lacuna
  maior que o overhead de Ruby entre elas).
- Os metadados de roteamento do turno (`playbook`, `activation_reason`, `unsatisfied_flags`) seguem no
  trace como hoje.

### Prova herdada do brief 07 (spec 089, T054 — US3-AS14, SC-010)

Executada depois de US1 e US2, com os pré-requisitos operacionais do §5, conforme
`specs/089-scout-v2-capabilities-scheduling/quickstart.md` §4:

- Caminho feliz: qualificação → `agendamento` pela transição de `qualificado` no mesmo turno →
  cadastro localizado ou criado → no máximo três horários em linguagem natural, só os devolvidos pelo
  ERP → reserva → `exit_agendado` com início e referência; agendamento visível no ERP de teste.
- Cada span `scheduling_*`/`customer_registry_*` carrega `capability_call` com os identificadores do
  hook e o telefone normalizado do contato; nenhum token.
- Caminhos alternativos: data sem horário → data mais próxima (até três dias seguintes) → recusa de
  todas → `exit_sem_horario` com motivo; pedido de pessoa → `exit_handoff`; contato sem telefone →
  handoff citando o telefone ausente, 0 requisições ao ERP; token errado → handoff sem promessa de
  reserva.
- Depois de cada desfecho, a mensagem seguinte não refixa `agendamento` nem oferece horários.
- Regressão: o card de dados do ERP no painel de contato renderiza como antes.

Cumprida a prova, T054 do spec 089 é marcada como concluída com referência a esta fase.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb`: invariantes de gatilho dos três
  playbooks de interrupção (exclusão de cumprimento e de resposta a pergunta do assistente) e da
  condição de saída de `identificacao`, no mesmo estilo de frase-chave dos briefs 06/07. O efeito no
  modelo não é testável sem LLM: é medido pelo replay da US1 (critério de aceite, não spec).
- `custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb`: a `description` declara a
  condição de uso.
- `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` (ou spec de instrumentação dedicada): com
  chat dublado executando duas completions e uma tool call, o exportador de spans em memória recebe
  duas gerações filhas do turno, com as tool calls pedidas em cada uma.

---

> **Nota de proveniência**: diagnosticado a partir dos traces Langfuse da sessão `1_147`
> (`569ecb22…`, `185e53a4…`, `31ac0f84…`, `6f729847…`), de `ScoutConversationState#4`,
> `Opportunity#142`, `Contact#199` e `Integrations::Hook#4` no ambiente de dev, e do
> `log/development.log` (request de 33 037 ms às 18:59:45). A transferência da prova do brief 07 para
> esta fase foi decisão do usuário em 2026-09-30.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
