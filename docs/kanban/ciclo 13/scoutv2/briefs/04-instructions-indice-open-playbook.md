# Fase 04 — Instructions Tipadas, Índice e `open_playbook` (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §4.1 (camadas), §4.2 (ciclo do turno), §6 (Fase 1)
**Depends on**: Brief 03 — o `TurnRunner` que monta o prompt do turno. Este brief entrega a metade
por-trigger do roteamento híbrido cuja costura foi definida no Brief 02.

---

## 1. Problema

Duas dores medidas, ambas no mesmo arquivo:

1. **Estilo compete com regra no mesmo balde de prosa.** O bloco de diretrizes
   (`custom/app/services/custom/scout/system_prompts_service.rb:68-79`) tem 11 bullets e 6.076
   caracteres enviados em todo turno, misturando o inegociável (anti-alucinação, anti-falsa-promessa)
   com estilo e com situacional. Pelo menos 5 dos 11 são situacionais por natureza (design §1).
2. **Metade das situações não tem assinatura de estado.** "Quero remarcar", "já sou cliente
   reclamando", "quanto custa", "quero falar com gente" não são expressáveis em `when_state` — por
   isso 3 das 6 playbooks do primeiro corte (`fora_de_prospeccao`, `duvida_comercial`, `pausa`)
   nascem sem `when_state` (design §4.4). Sem um mecanismo de ativação por trigger, o roteador do
   Brief 02 cobre no máximo metade do problema.

## 2. Contexto técnico

- `system_prompts_service.rb:19-28` — 8 seções concatenadas, 6 incondicionais.
- `system_prompts_service.rb:68-79` — `guardrails_section`: os 11 bullets, com destinos distintos
  (design §4.1: inegociável → `Safety`; estilo → enum em `Communication`; situacional → playbook ou
  Escalation).
- `system_prompts_service.rb:159-162` — bullet global manda "consulte a base sempre que
  necessário"; `system_prompts/funnel_section_builder.rb:46-49` é o **contra-bullet** que pede ao
  modelo para *não* inventar perguntas por causa da base. Um existe por causa do outro.
- **RubyLLM 1.15.0** (design §4.2): `with_tool` escreve em `@tools`, `with_instructions` sobrescreve
  a mensagem de sistema in-place, e `handle_tool_calls` reentra em `complete` relendo o estado do
  chat. Uma tool que segura a referência do chat troca instruções e catálogo **no meio** do
  `chat.ask`, e a iteração seguinte já sai com o estado novo.
- Canal de "resultado de tool é mais saliente que o prompt" já validado no v1:
  `opportunity_stage_transition_service.rb:9-11,47` (`NO_QUESTION_CLOSING_INSTRUCTION`) e
  `tools/base_tool.rb:62-73` (`scoped_confirmation_reminder`); o comentário em
  `system_prompts_service.rb:185-189` diz o porquê — *"a static system-prompt bullet read many
  messages earlier is not salient enough on its own"*.

## 3. Precedente

- **Painel Botpress** (design §2.3): `Instructions > Identity` são campos nomeados (`Role`,
  `Scope`); `Communication` usa **enums** (`Tone`: Friendly/Neutral/Matter-of-fact/Professional/
  Humorous/Custom; `Response length`: Concise/Standard/Thorough) e `Greeting` próprio. Estilo é
  config tipada, não prosa. Aplica-se diretamente.
- **Escopo de tools** (`llms-full.txt:9844-9845`): tool de Instructions está sempre disponível;
  **tools da playbook entram no conjunto quando ela está ativa**. E `:9847`: conectar integração não
  basta — *"Add the action to the relevant Instructions or Playbook and explain the condition for
  using it"*. É a regra que move o "quando consultar a base" do global para o passo.
- **Captain V2** injeta o índice no prompt do orquestrador como `- {title}: {description}, use
  handoff_to_{key}` (`lib/captain/prompts/assistant.liquid:82-84`). Formato reaproveitável. **Não se
  aplica:** lá cada scenario é um sub-agente com handoff bidirecional; aqui a playbook é conteúdo
  injetado no mesmo chat, sem segundo agente.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | **Instructions tipadas**: `Role`, `Scope`, `Tone` (enum), `Response length` (enum), `Greeting`, política de `Memory`, `Safety` | Tira estilo do balde de prosa que compete por atenção (design decisão 6) |
| 2 | Índice de playbooks sempre-on, **1 linha por playbook** (nome + trigger) | É o único sinal que o modelo tem para escolher; mais que uma linha reintroduz o bloat que o épico combate (design §4.1) |
| 3 | `open_playbook` injeta, **no mesmo turno**, corpo + tools + capabilities + exits da playbook aberta | As alternativas são piores: pré-registrar as tools de todas as playbooks é o tool bloat do v1 com outro nome; adiar para o turno seguinte é um turno morto no meio da conversa (design §4.2) |
| 4 | O corpo entra como **resultado de tool**, não como novo bloco de sistema | Canal já validado no v1 e atestado como mais saliente que o prompt (`system_prompts_service.rb:185-189`) |
| 5 | Exclusão entre playbooks vizinhas é **convenção de redação do `trigger`**, revisada em PR, não validação de boot | Ex.: `duvida_comercial` × `fora_de_prospeccao` — *"…; não usar se o contato já é cliente reclamando de atendimento"*. Não é validável estaticamente (design §4.3) |
| 6 | O global passa a **apenas declarar que a base de conhecimento existe**; o *quando* consultar vai para o passo da playbook | Regra explícita de `llms-full.txt:9847`. Efeito colateral: o contra-bullet de `funnel_section_builder.rb:46-49` perde a razão de existir e some |

## 5. Escopo preliminar

- `custom/app/services/custom/scout_v2/instructions/` — Identity, Communication (enums), Memory,
  Safety, montados a partir de configuração do scout, não de prosa livre.
- Campos tipados no scout para `tone` e `response_length` (enums) e `greeting`.
- `custom/app/services/custom/scout_v2/playbook/index_builder.rb` — a linha por playbook.
- `custom/app/services/custom/scout_v2/tools/open_playbook.rb` — tool sempre-on que resolve a
  playbook pelo nome, devolve o corpo como resultado e injeta tools/capabilities/exits no chat vivo.
- `TurnRunner`: registrar `open_playbook` apenas quando **não** há playbook forçada por estado
  (design §4.4, "Limites").

## 6. Fora de escopo

- Escalation, `exit_handoff` e o mecanismo de exits — brief 05 (`open_playbook` já injeta os exits
  declarados; o *handler* deles é do brief seguinte).
- As playbooks em si, além da `qualificacao` do brief 03 — brief 06.
- Classificador de intenção tipado no lugar do `open_playbook`: adiado por decisão (design §4.4) —
  a interface do roteador já permite a troca sem reescrita.
- Qualquer alteração em `system_prompts_service.rb` do v1.
- Tradução do corpo das playbooks para o ciclo de i18n (design §4.3).

## 7. Critérios de aceite (rascunho)

### US1 — Instructions tipadas substituem o bloco de prosa

- O prompt v2 sempre-on é composto de `Identity` (role, scope), `Communication` (tone,
  response_length, greeting), `Memory` (política de retenção) e `Safety` (anti-alucinação,
  anti-falsa-promessa, idioma, escopo comercial) — e de nada mais.
- Mudar `tone` ou `response_length` do scout muda o prompt sem editar texto livre.
- Nenhum dos 5 bullets situacionais do v1 aparece no prompt sempre-on.
- `Safety` declara que existe base de conhecimento, sem instruir *quando* consultá-la.

### US2 — Índice de playbooks sempre presente

- O prompt sempre-on lista todas as playbooks habilitadas, uma linha cada, com nome e trigger.
- O índice reflete o catálogo carregado: adicionar um arquivo de playbook muda o índice sem código
  novo.

### US3 — `open_playbook` ativa procedimento no meio do turno

- Sem playbook forçada por estado, o modelo pode abrir uma playbook do índice; o corpo chega como
  resultado de tool e o turno continua **na mesma chamada de topo**.
- Na iteração imediatamente seguinte, as tools, capabilities e exits declarados por aquela playbook
  estão disponíveis ao modelo — sem turno morto e sem nova mensagem ao cliente.
- Abrir playbook grava `activation_reason: trigger` no estado da conversa.
- Quando há playbook forçada por estado, `open_playbook` **não** é oferecida.
- Abrir playbook inexistente devolve erro de tool e o turno continua, sem quebrar.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/instructions/*_spec.rb`: composição por configuração e
  ausência dos bullets situacionais.
- `custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb`: com o chat dublado, verificar
  que após a chamada o catálogo de tools do chat contém as da playbook aberta e que o corpo voltou
  como resultado — e que `activation_reason` foi persistido como `trigger`.
- Verificação comportamental no playground: mensagem sem assinatura de estado ("quanto custa?")
  abrindo a playbook correta no mesmo turno.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §4.1, §4.2 e §6; os enums
> de `Communication` vêm do painel de referência documentado no §2.3; o mecanismo mid-turn foi
> verificado em `ruby_llm-1.15.0/lib/ruby_llm/chat.rb` durante o design (§9).
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
