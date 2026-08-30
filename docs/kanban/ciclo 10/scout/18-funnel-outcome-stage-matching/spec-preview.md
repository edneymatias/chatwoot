# Phase 18 — Correspondência Desfecho-Estágio no Funil (Preview)

**Status**: Preview — problema real observado e diagnosticado; especificação completa e
implementação adiadas para o momento oportuno, a critério do operador. Este arquivo também
registra, na seção final, um segundo tema adjacente (qualidade de engajamento/momentum da
resposta) para análise futura — ver nota ali sobre por que não foi fundido nos critérios de
aceite acima.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 08 (`08-system-prompt-guardrails/spec71.md`) — `SystemPromptsService#funnel_section`,
onde as descrições de estágio já são montadas e enviadas ao modelo. Fase 09
(`09-required-qualification-attributes/...`) — mesmo mecanismo de contexto de funil.

---

## Este preview não tem precedente no Captain

Diferente da maioria das fases anteriores, este problema não tem arquitetura de referência no
Captain — ele não tem noção de Oportunidade/Kanban nem de estágios de funil configuráveis pelo
operador (mesma ressalva já registrada na Fase 14). O diagnóstico e o escopo preliminar abaixo
partem inteiramente da observação de uma conversa real.

## Evidência que motivou este preview

Conversa real (self-hosted dev stack, conta 1, Scout "Vitória", inbox "Acme Support",
conversation_id 21 / display_id 19, 2026-08-29 03:49–03:52 UTC):

1. Lead chega pelo site com interesse em Ortodontia → Scout cria a Oportunidade #10 no estágio
   padrão ("Leads Recebidos").
2. Scout pergunta se o lead quer agendar uma avaliação.
3. Lead pergunta o valor da manutenção mensal; Scout responde honestamente que não tem essa
   informação (comportamento correto — sem alucinar) e reforça o convite para agendar.
4. Lead responde **"não, volto depois."**
5. Scout encerra educadamente. Nenhum erro, nenhuma exceção, nenhum handoff — a conversa
   simplesmente permanece `pending`, e a Oportunidade #10 nunca sai do estágio "Leads Recebidos".

O `reasoning` interno do modelo para o último turno (capturado no log do Sidekiq) mostra a decisão
explícita:

> *"O lead informou que não deseja agendar agora e pretende retornar depois. Não há ação comercial
> adicional a ser tomada neste momento."*

Isso contradiz diretamente a descrição que o operador configurou no estágio de desqualificação
("Falhou", `unqualified_stage_id` deste Scout):

> *"Aqui ficam os leads que **falharam na tentativa de agendar uma avaliação**. O objetivo aqui é
> tentar recuperar o lead antes de marcar como perdido em definitivo..."*

A recusa do lead em agendar é exatamente o critério descrito pelo operador para esse estágio — mas
o modelo nunca comparou o desfecho da conversa contra essa descrição.

### Segunda evidência — mesma lacuna, direção oposta (avançar para qualificado)

Duas outras conversas reais da mesma conta/Scout mostram o problema espelhado: o Scout confirma um
agendamento ao cliente sem nunca mover a Oportunidade para o estágio qualificado
(`qualified_stage_id`), o que também nunca dispara o handoff automático já garantido pela Fase 09
para esse caso.

- **conversation_id 20** (display_id 18, 2026-08-29 01:09–01:12 UTC): lead de próteses via Google
  confirma data/horário; Oportunidade #9 é criada e permanece no estágio padrão ("Leads
  Recebidos"); resposta final ao cliente: *"Sua avaliação para próteses está agendada para
  segunda-feira, 31/08, às 11h. Em breve, nossa equipe confirmará todos os detalhes..."*
- **conversation_id 22** (display_id 20, 2026-08-29 11:26–11:30 UTC): lead de implantes via
  indicação confirma horário para o mesmo dia; Oportunidade #11 avança corretamente de "Leads
  Recebidos" para "Contato estabelecido" no início da conversa, mas nunca chega ao estágio
  "Agendado" (`qualified_stage_id`); resposta final: *"Seu agendamento para avaliação de implantes
  hoje às 12h está reservado! [...] Nos vemos mais tarde!"*

Em ambos os casos, o log do Sidekiq mostra uma chamada final de `manage_opportunity` que resulta em
`changed_attributes: {}` (nenhum campo realmente mudou) e nenhum evento `opportunity_stage_changed`
subsequente — ou seja, o modelo nunca chegou a chamar `move_opportunity_stage`/passar `stage_id`
para o estágio qualificado, apesar de (a) todos os campos obrigatórios de qualificação já estarem
preenchidos e (b) a descrição do estágio "Agendado" configurada pelo operador descrever
exatamente esse desfecho ("o paciente aceitou marcar um horário"). Isso é mais grave que o cenário
de desqualificação: o cliente termina a conversa acreditando ter um horário confirmado, e nenhum
humano da equipe é notificado (sem handoff, sem card no estágio certo do Kanban).

**Mitigação imediata aplicada enquanto a Fase 18 não é tratada**: como esse sintoma exato
(afirmação de ação concluída sem a tool call correspondente) é o que a Fase 12 — Auditor de
Resposta (`12-response-auditor/spec78.md`, já implementada) foi desenhada para detectar,
`feature_response_auditor` foi ativado no Scout "Vitória" (`Scout.find(1)`) em 2026-08-29 como
mitigação de curto prazo, independente do escopo desta fase.

## Causa raiz identificada

`SystemPromptsService#funnel_section` (Fase 08) já inclui a descrição de cada estágio configurado
no contexto do modelo (`format_stage`), incluindo a do estágio desqualificado. Mas as únicas
diretrizes operacionais de funil hoje (`build_funnel_guidelines_lines`) tratam de *como* mover
estágios corretamente (não violar campos obrigatórios, não marcar como ganho/perdido no estágio
desqualificado) — nenhuma diretriz instrui o modelo a *ativamente* comparar o desfecho observável
da conversa (recusa, adiamento, silêncio, etc.) contra as descrições de estágio configuradas para
decidir uma transição. As descrições de estágio são hoje apenas contexto passivo, nunca um gatilho
de decisão explícito. Sem essa instrução, o modelo tende à interpretação conservadora ("nenhuma
ação necessária"), mesmo quando o desfecho bate claramente com a descrição de um estágio.

A relação com a Fase 12 (Auditor de Resposta) depende da direção do problema. Na desqualificação
(evidência original acima, conversation_id 21), a resposta final do Scout não afirma nenhuma ação
concluída nem promete algo — é só uma despedida educada — então o auditor da Fase 12 não teria
como detectar nada ali mesmo que estivesse ativo; a causa raiz é puramente de prompt e só a Fase 18
resolve. Já na direção de avançar para qualificado (segunda evidência acima, conversation_id 20 e
22), a resposta final *afirma* uma ação concluída ("está agendada"/"está reservado") sem a tool
call correspondente — exatamente o padrão `false_completed_action` que a Fase 12 audita; por isso
`feature_response_auditor` foi ativado como mitigação reativa (o auditor tenta forçar o modelo a
de fato chamar `move_opportunity_stage` no reparo, ou escala para humano). Mas o auditor só age
depois que o modelo já decidiu (erradamente) que a ação estava concluída — a causa raiz de o modelo
nunca ter comparado o desfecho contra a descrição do estágio continua sem correção até a Fase 18.

## Escopo preliminar (a confirmar na especificação completa)

- Nova diretriz genérica em `SystemPromptsService#funnel_section` (ou seção dedicada) instruindo o
  Scout a comparar ativamente o desfecho de cada turno contra as descrições dos estágios
  configurados (incluindo, mas não só, o estágio desqualificado) e mover a oportunidade quando o
  desfecho corresponder claramente à descrição de algum estágio — sem hardcode de palavras-chave
  específicas ("volto depois", etc.) nem de um estágio específico, para funcionar em qualquer conta
  com qualquer configuração de funil.
- Possível reforço complementar: instrução para o operador (via UI/placeholder do campo de
  descrição de estágio) sugerindo que a descrição seja escrita de forma acionável, já que ela passa
  a ser lida pelo agente como critério de decisão, não só como nota informativa para humanos no
  Kanban.
- Reavaliar se `stage.description` deveria ser sanitizado (hoje é HTML bruto vindo do editor rico,
  incluído no prompt via `.strip` apenas) antes de ir para o prompt — não é a causa raiz deste
  problema, mas é uma oportunidade de limpeza notada durante a investigação.

## Fora de escopo desta fase (preview)

- Qualquer regra determinística/hardcoded de "se o lead recusar agendar, mover para X" — o
  mecanismo deve continuar sendo o modelo interpretando a descrição configurada pelo operador, não
  uma lista fixa de gatilhos no código.
- Mudança no mecanismo de `unqualified_stage_id`/`qualified_stage_id` em si (Fase 09) — este
  preview é só sobre a ausência de diretriz para *usar* as descrições já disponíveis no contexto.
- Qualquer alteração no pipeline de auditoria de resposta (Fase 12) — o auditor já implementado
  serve como mitigação reativa independente para a direção "avançar para qualificado" (ver segunda
  evidência acima), mas esta fase é sobre a causa raiz (o modelo nunca decidir a transição em
  primeiro lugar), não sobre o mecanismo de auditoria/reparo em si.

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Uma conversa onde o lead recusa/adia a ação principal proposta (ex.: agendar) resulta na
  oportunidade sendo avaliada contra as descrições de estágio configuradas, incluindo o estágio
  desqualificado quando a descrição do operador cobrir esse cenário.
- Uma conversa onde o lead confirma a ação principal proposta (ex.: agendar um horário) e todos os
  campos obrigatórios de qualificação já estão preenchidos resulta na oportunidade avançando para o
  estágio qualificado (e no handoff automático correspondente, já garantido pela Fase 09) antes ou
  junto da resposta que confirma o agendamento ao cliente — nunca depois, e nunca sem a transição
  real ter acontecido.
- Contas sem descrição configurada para nenhum estágio mantêm o comportamento atual (sem regressão,
  mesmo padrão de omissão gradual já estabelecido na Fase 09/FR-014).
- Nenhuma regra específica de negócio (palavras-chave, frases) fica hardcoded no prompt ou no
  código — a diretriz é genérica e depende só da descrição que o operador já escreve hoje.

---

## Tema adjacente registrado para análise futura: momentum conversacional da resposta

Discutido em sessão de brainstorming da Fase 12 (Auditor de Resposta), mas **não é o mesmo
problema** — nem da Fase 12 (que audita veracidade/consistência com tool calls, não qualidade de
condução da conversa), nem, a rigor, do problema de descasamento desfecho-estágio acima (que é
sobre *decisão de mover a oportunidade*, não sobre *como a pergunta/resposta é formulada*).
Registrado aqui por ser a mesma família de causa raiz (diretriz de prompt ausente em
`SystemPromptsService`) e por ainda não ter especificação própria.

### Sintoma 1 — múltiplas perguntas empilhadas numa única resposta

Exemplo real observado em teste:

> *"Ótimo, você tem interesse em próteses! Para te ajudar melhor, você pode me contar como
> conheceu a nossa clínica? Foi pelo Facebook/Instagram, Google, Site, Fachada, Indicação ou de
> forma orgânica? E aproveitando, você gostaria de agendar uma avaliação ou tem alguma dúvida
> específica sobre próteses?"*

Três perguntas numa única mensagem (origem do lead, intenção de agendar, dúvidas específicas). O
efeito observado é o oposto do pretendido: o lead percebe a abordagem como complicada,
inquisitiva e demorada, em vez de manter o engajamento.

**Segunda evidência** (conta 1, Scout "Vitória", modelo `gpt-5.2`, conversation_id 42 / display_id
40, 2026-08-30 12:48–12:50 UTC): lead diz **"alinhadores."**; Scout confirma corretamente o
registro do interesse (guardrail de confirmação de ação funcionando), mas empilha na mesma
resposta a pergunta de origem **e** duas perguntas de agendamento (dia e turno):

> *"Perfeito — já registrei sua oportunidade com interesse em **Alinhadores**. Pra eu dar
> sequência: como você encontrou a gente? [...] E você quer **agendar uma avaliação**? Se sim, me
> diga por favor **qual dia** você prefere [...] e se prefere **manhã ou tarde**."*

Confirma o padrão como recorrente (não é caso isolado). Restante da conversa não teve outro
problema: o handoff final (lead perguntou valor de manutenção, não estava na base, Scout escalou
para humano em vez de inventar) foi correto.

### Sintoma 2 — resposta inerte, sem pergunta de avanço

Padrão espelhado: o Scout apresenta uma informação relevante (ex.: descrição de um
produto/serviço) e encerra o turno sem propor um próximo passo ou pergunta que mantenha a
qualificação avançando — a conversa "esfria" por falta de gancho, não por erro ou recusa do lead.

### Sintoma 3 — insistência na mesma pergunta após o lead sinalizar pausa/encerramento

Exemplo real observado (conta 1, Scout "Vitória", modelo `gpt-5.2`, conversation_id 36 /
display_id 34, 2026-08-29 17:24–17:30 UTC): lead confirma interesse (Implantes) e origem
(Facebook/Instagram) logo no início; a Oportunidade #21 é criada corretamente. O lead então diz
**"tá bom, eu vou ver um dia e aí retorno."** — sinal claro de pausa. O Scout responde educadamente
mas repete a mesma pergunta de qualificação ("é para 1 dente, alguns dentes ou a arcada toda?"). O
lead reforça o encerramento — **"vejo e te aviso. obrigado."** — e o Scout **repete a mesma
pergunta pela segunda vez seguida**, ignorando o sinal já dado duas vezes; só para de insistir no
terceiro "obrigado." do lead.

Mesma família causal dos Sintomas 1 e 2: nenhuma diretriz em `guardrails_section` instrui o modelo
a reconhecer um sinal de pausa/encerramento do lead e parar de reintroduzir perguntas de
qualificação pendentes. O efeito é o oposto do Sintoma 2 (aqui o Scout não "esfria" cedo demais,
insiste tarde demais), mas a causa raiz é a mesma ausência de diretriz sobre como conduzir o ritmo
da conversa.

### Sintoma 4 — narração de ações internas de CRM ao cliente

Exemplo real observado (screenshot do widget do site, conta 1, Scout "Vitória", Oportunidade #28,
Ortodontia via Site — conversation_id/display_id a confirmar nos logs se necessário para o ajuste
completo):

> *"Perfeito — atualizei a oportunidade **#28** com **Interesse: Ortodontia** e **Origem: Site**.
> Para próxima semana à tarde, tenho estes horários livres na segunda (31/08): [...] Qual desses
> você prefere?"*

O Scout expõe ao cliente detalhes puramente internos do CRM: o ID numérico da oportunidade (`#28`),
nomes técnicos de atributos (`Interesse`, `Origem`) e a narração da própria ação de atualização
("atualizei a oportunidade... com..."). Nada disso tem valor para o cliente — o efeito é o oposto
de uma conversa natural, soa como um log de sistema em vez de uma resposta humana.

Mesma família causal dos Sintomas 1-3: ausência de diretriz em `guardrails_section` instruindo o
modelo a nunca expor identificadores internos, nomes de campos/atributos do CRM, ou linguagem de
"log de sistema" ("atualizei o registro com X"), e a comunicar-se sempre em linguagem natural
voltada ao cliente — confirmação de que a ação foi feita, sem narrar *como* foi feita
internamente, e focada no próximo passo da conversa (que aqui, à parte, funcionou corretamente —
os horários oferecidos são relevantes e a pergunta final avança a conversa).

### Sintoma 5 — enumeração de valores permitidos ao cliente, em vez de pergunta aberta

Exemplo real observado (mensagem de abertura, conta 1, Scout "Vitória", inbox "Acme Support"):

> *"Oi! Eu sou a Vitória 😊 Pra eu te ajudar direitinho: você tem interesse em qual tratamento —
> Implantes, Próteses, Ortodontia, Alinhadores ou Outros? E você encontrou a gente por onde
> (Google, Facebook/Instagram, Site, Fachada, Indicação ou Orgânico)?"*

O Scout recita literalmente todos os valores configurados (`attribute_values`) de dois campos de
lista (`Interesse`, `Origem`) na mesma pergunta, como se fosse um menu de múltipla escolha, em vez
de perguntar de forma aberta e deixar o lead responder com as próprias palavras. Tem sobreposição
com o Sintoma 1 (duas perguntas na mesma mensagem), mas o problema aqui é distinto e persistiria
mesmo perguntando uma coisa de cada vez: recitar a lista de valores em si já torna a conversa
artificial, parecendo um formulário lido em voz alta em vez de uma conversa.

Causa raiz: a lista "Valores permitidos" (`format_attribute_definition`, Fase 09,
`SystemPromptsService#funnel_section`) existe para orientar o modelo a **mapear internamente** a
resposta livre do lead para o valor correto ao chamar `manage_opportunity`/`update_contact` — não
deveria ser recitada ao cliente como se fosse uma pergunta de múltipla escolha. Nenhuma diretriz
hoje instrui o modelo a tratar essa lista como informação de mapeamento interno, não como texto a
apresentar literalmente na pergunta.

### Ajuste aplicado (2026-08-29)

Diferente dos Sintomas 1 e 2 (ainda sem instrução testada), o Sintoma 3 teve uma diretriz bounded
aplicada diretamente em `guardrails_section` nesta data, junto com uma diretriz correlata (também
observada na mesma conversation_id 36): o Scout executava `manage_opportunity` com sucesso mas
nunca confirmava ao cliente que o interesse/dado havia sido registrado — o cliente via só perguntas
de qualificação adicionais, sem nenhuma confirmação de que algo foi feito. Essa segunda lacuna não
é sobre momentum conversacional nem sobre stage-matching (é o inverso da diretriz
anti-falsa-promessa: agir sem informar, em vez de prometer sem agir), então não foi registrada como
sintoma desta seção — apenas o ajuste de prompt foi aplicado junto por serem observações da mesma
conversa e do mesmo mecanismo (`guardrails_section`).

### Por que não é a Fase 12

A Fase 12 (`12-response-auditor/spec78.md`) audita se a resposta *afirma algo que não aconteceu*
(ação concluída sem tool call, promessa futura, handoff necessário e não executado). Nenhum dos
dois sintomas acima envolve uma afirmação falsa: a resposta com 3 perguntas é totalmente verdadeira
(só mal formada), e a resposta inerte do sintoma 2 não afirma nada de errado — simplesmente não
avança. Um auditor de veracidade não tem como (nem deveria) julgar isso.

### Diagnóstico preliminar e por que ainda não é uma fase própria

Mesma causa raiz arquitetural das fases de guardrail já existentes: falta diretriz explícita em
`SystemPromptsService` (provavelmente `guardrails_section`, não `funnel_section` — não é
específico de estágio de funil) instruindo o modelo a (a) nunca empilhar mais de uma pergunta por
resposta, (b) sempre fechar com uma pergunta ou próximo passo de avanço quando apresentar
informação relevante para a qualificação, (c) reconhecer quando o lead sinaliza pausa/encerramento
e parar de reintroduzir perguntas de qualificação pendentes (Sintoma 3), (d) nunca expor
identificadores internos, nomes de campos/atributos do CRM ou linguagem de "log de sistema" ao
confirmar uma ação já executada (Sintoma 4), e (e) tratar a lista de "Valores permitidos" de campos
de qualificação como mapeamento interno, nunca recitando as opções ao cliente como um menu de
múltipla escolha (Sintoma 5). A Fase 08 já deixou esse tipo de regra de estilo explicitamente fora
de escopo ("podem ser adicionadas depois se necessário").

Diferente da Fase 12 (que só avançou por ter evidência de que um guardrail de prompt *já existente*
não bastava), ainda não há evidência de que uma instrução de prompt simples seja insuficiente para
os Sintomas 1 e 2 — nenhuma diretriz foi testada ainda contra eles. O Sintoma 1 já tem duas
observações reais independentes (conversation_id 21/display_id 19 e conversation_id 42/display_id
40), confirmando que é um padrão recorrente, não um caso isolado — mas a diretriz correspondente
ainda não foi escrita nem testada. O Sintoma 3 recebeu ajuste bounded em 2026-08-29 (ver nota
acima), antes da decisão de processo abaixo, por ser um caso mais simples de descrever e já ter
evidência de recorrência no mesmo turno seguinte.

### Decisão de processo (2026-08-30)

A partir desta data, qualquer achado cuja causa raiz seja exclusivamente prompt/`guardrails_section`
(sem nenhum componente de código/lógica) passa a ser só **registrado como evidência nesta Fase 18**
no momento em que é observado, em vez de receber um ajuste bounded imediato — mesmo quando o
tratamento preliminar acima recomendaria isso. O objetivo é acumular evidência de múltiplas
conversas de teste e tratar todos os sintomas de prompt/guardrail (1, 2, 3 e quaisquer outros que
surgirem) numa única leva de ajustes em `guardrails_section`/`funnel_section`, revisada e testada de
uma vez, em vez de várias edições incrementais. Achados cuja causa raiz é código (lógica, bug,
race condition) continuam sendo corrigidos imediatamente fora desta fase, no arquivo/serviço
correspondente — como os dois fixes em `response_auditor.rb` (mensagem duplicada pós-handoff) e o
double-confirmation gate do `ActionClassifierService`, tratados em sessão de debugging separada, não
registrados aqui por não serem sobre conteúdo do prompt.

---

> **Nota**: Preview criado a partir do diagnóstico de três conversas reais da mesma conta/Scout:
> conversation_id 21 (Oportunidade #10 — não moveu para "Falhou" apesar de a descrição do estágio
> cobrir exatamente a recusa observada), conversation_id 20 (Oportunidade #9) e conversation_id 22
> (Oportunidade #11) — nas duas últimas o Scout confirmou um agendamento ao cliente sem nunca mover
> a oportunidade para o estágio qualificado nem disparar o handoff automático correspondente.
> Tratamento adiado para o momento oportuno, a critério do operador — ver `spec60.md` §11.
> `feature_response_auditor` foi ativado no Scout "Vitória" (`Scout.find(1)`) em 2026-08-29 como
> mitigação reativa de curto prazo para a direção de qualificação (ver segunda evidência acima).
>
> Atualização (2026-08-29): conversation_id 36 (display_id 34, modelo `gpt-5.2`, Oportunidade #21)
> adicionou o Sintoma 3 ao tema adjacente de momentum conversacional (insistência na mesma pergunta
> após o lead sinalizar pausa/encerramento) e revelou uma lacuna correlata fora do escopo desta fase
> (ausência de confirmação ao cliente quando uma ação de registro é concluída com sucesso). Ambas
> receberam um ajuste bounded em `guardrails_section` nesta data — ver seção "Ajuste aplicado
> (2026-08-29)" acima.
