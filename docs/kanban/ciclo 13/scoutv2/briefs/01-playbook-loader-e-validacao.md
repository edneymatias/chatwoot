# Fase 01 — Loader e Validação de Playbooks (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §4.3 (formato), §4.4 (validação no boot), §6 (Fase 0)
**Depends on**: — (primeiro brief do épico; índice em `docs/kanban/scoutv2/briefs/README.md`)

---

## 1. Problema

Métrica de dor, medida no próprio repositório: **12 commits em
`custom/app/services/custom/scout/system_prompts_service.rb`, 5 nos auditores, 24 no módulo Scout**
(design §1.1 e §9). Toda regra de comportamento nova — inclusive as situacionais — cai no mesmo
heredoc global, porque não existe no código nenhuma unidade menor que "o prompt inteiro".

O efeito medido é um piso estático de ~11 mil caracteres por turno, independente do que a conversa
precisa: 6.076 caracteres no bloco central de diretrizes (`system_prompts_service.rb:68-79`),
~2.151 de diretrizes de funil (`system_prompts/funnel_section_builder.rb:31-51`), 523 de identidade,
567 de data/hora, 910 de instruções da conta — com 6 das 8 seções concatenadas incondicionalmente
(`system_prompts_service.rb:19-28`). Pelo menos 5 dos 11 bullets são situacionais por natureza e
mesmo assim estão sempre presentes (design §1, tabela).

## 2. Contexto técnico

- `system_prompts_service.rb:19-28` — `build` concatena 8 seções; 6 sem condicional alguma.
- `system_prompts_service.rb:68-79` — `guardrails_section`, 11 bullets numa string única. Não há
  como referenciar, testar ou desativar um bullet isolado: a menor unidade endereçável é o método.
- `system_prompts/funnel_section_builder.rb:31-51` — mesmo padrão para o funil.
- `system_prompts_service_spec.rb` — o único teste possível hoje é asserção de substring, ou seja,
  teste de implementação, não de comportamento (design §7).
- Não existe artefato declarativo de comportamento no módulo: nenhum arquivo, nenhuma tabela,
  nenhum registro nomeia "situação X ⇒ procedimento Y".

## 3. Precedente

- **Botpress Playbooks** (`llms-full.txt:9828-9836`): procedimento para situação específica, com
  passos ordenados, *"reusável, testável e melhorável independentemente"*. Regra de corte explícita
  entre Instructions (regras duráveis) e Playbook (`:9826`). Aplica-se integralmente ao formato.
- **`Captain::Scenario`** (upstream 4.18.0, `enterprise/app/models/captain/scenario.rb:146-178`):
  `title` + `description` (trigger) + `instruction` (passos) + `tools`, com
  `validate_instruction_tools` rejeitando no `save` qualquer referência `tool://` inexistente.
  **Reaproveitável:** a ideia de validar referências antes de a playbook existir em runtime.
  **Não se aplica:** lá o scenario é linha de banco por assistant, validada no `save` e com UI; aqui
  é arquivo versionado no fork (design decisão 2), então o equivalente do `save` é o boot/CI.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | Playbook é **arquivo versionado no fork** (`custom/playbooks/<nome>.md`), frontmatter YAML + corpo markdown | Design decisão 2: banco exigiria UI, e UI só se paga com edição por conta — não-objetivo explícito. O ciclo de deploy já é o mecanismo de mudança de comportamento hoje (heredoc em Ruby), então arquivo não adiciona fricção: isola cada regra num `.md` e propaga a correção para todas as contas num deploy |
| 2 | `when_state` **sem DSL**: lista de nomes de predicados registrados em Ruby, com argumento opcional, avaliada como **E lógico** | Sem `or` e sem aninhamento não há linguagem nova para manter nem parser para testar; disjunção vira duas playbooks ou um predicado novo, que é código com spec (design §4.4) |
| 3 | Predicado é **classe Ruby registrada** (`Custom::ScoutV2::Predicates::*`), resolvida por nome | É a unidade pequena e isolada que torna o roteamento testável sem LLM (design §7) |
| 4 | Validação no boot **falha alto**, nunca degrada em silêncio | `AGENTS.md`: estado impossível/misconfigurado indica bug de setup e deve falhar alto. Referência quebrada morre no CI, não numa conversa de cliente (design §4.4) |
| 5 | Corpo da playbook é escrito em **pt-BR** e fica **fora do ciclo de i18n** (`en.json`/`pt_BR.json`) | É instrução ao modelo, não texto ao cliente; a resposta ao lead segue o idioma detectado, como hoje (design §4.3) |
| 6 | `priority` é **obrigatória, inteira e única** em toda playbook — sem default e sem playbook "sem prioridade" | Um default tornaria a validação de `priority` duplicada (design §4.4) autocontraditória: toda playbook que omitisse o campo colidiria, e escapar disso exigiria tratar ausência como caso especial — exatamente a coerção de valor malformado que o `AGENTS.md` proíbe. A regra de decisão do roteador também compara com `>` estrito (design §4.4), o que exige ordem total. Com seis playbooks autoradas em PR (decisão 1), não há argumento de escala para default. Vale inclusive para as que ativam só por `trigger`: `fora_de_prospeccao` é especificada como `priority` máxima (design §6) |
| 7 | `exits` é **opcional**: zero desfechos é playbook válida, e o loader entrega lista vazia (nunca `nil`) | Design §4.6: *"Turno sem exit é o caso normal — responder e aguardar o cliente é o `ListenExit` implícito; exit só existe onde há desfecho"*. Reforçando: o mecanismo de exit só nasce no brief 05, e a `qualificacao` do brief 03 (decisão 5 de lá) é entregue sem exits — exigir ≥1 no boot tornaria a única playbook da Fase 0 incarregável. Declarar ao menos um desfecho onde a situação tem desfecho é **convenção de autoria revisada em PR** (as seis do primeiro corte declaram, design §6), não regra de validação |

## 5. Escopo preliminar

- `custom/playbooks/` (novo diretório): arquivos de playbook, um por situação.
- `custom/app/services/custom/scout_v2/playbook/loader.rb`: parse de frontmatter + corpo, objeto
  tipado com `name`, `title`, `priority`, `when_state`, `trigger`, `requires`, `needs`, `tools`,
  `exits`, `body`.
- `custom/app/services/custom/scout_v2/playbook/validator.rb`: as checagens de boot listadas em §7 US2.
- `custom/app/services/custom/scout_v2/predicates/base.rb` + registro por nome + os predicados
  exigidos pela playbook do brief 03 (`opportunity_open`, `pending_required_fields`).
- Ponto de execução da validação no boot/CI (initializer do módulo `custom/` ou tarefa dedicada).

## 6. Fora de escopo

- Regra de decisão do roteador (precedência, continuidade, interrupção) — brief 02.
- Execução de turno, montagem de prompt e qualquer chamada LLM — brief 03.
- `CapabilityRegistry` real: aqui a validação de `requires:` só confere o nome contra o **catálogo
  declarado**, sem resolver adapter — brief 07.
- Qualquer alteração em `system_prompts_service.rb`, `agent_runner.rb` ou `response_auditor.rb`: os
  serviços de comportamento do v1 ficam sem uma linha de diff (design decisão 5).
- UI, banco ou enable/disable de playbook por conta (design §6, itens 6.3).

## 7. Critérios de aceite (rascunho)

### US1 — Carregar playbook de arquivo em objeto tipado

- Um arquivo em `custom/playbooks/` com frontmatter (`name`, `title`, `priority`, `when_state`,
  `trigger`, `requires`, `needs`, `tools`, `exits`) e corpo em markdown é carregado como um objeto
  com esses campos acessíveis, e o corpo preservado verbatim.
- `name`, `title`, `priority` e `trigger` são **obrigatórios** em toda playbook; ausência é erro de
  boot (US2), não default.
- Campos opcionais ausentes (`requires`, `needs`, `tools`, `when_state`, `exits`) resultam em
  **coleção vazia, nunca `nil`** — playbook só por `trigger` é caso normal (3 das 6 do primeiro
  corte, design §4.4), e ela declara `priority` como qualquer outra.
- `exits: []` (ou `exits` ausente) é playbook válida: sem desfecho declarado, o turno responde e
  aguarda o cliente — o `ListenExit` implícito do design §4.6 — e a escalação continua alcançável
  por `exit_handoff`, que é sempre-on (design §4.1).
- Carregar o conjunto de playbooks devolve um catálogo consultável por nome e ordenável por
  `priority`.

### US2 — Falhar no boot diante de referência quebrada

- Sobe com erro claro, identificando arquivo e referência, quando: predicado citado em `when_state`
  não está registrado · capability em `requires` está fora do catálogo · exit citado no corpo não
  está declarado em `exits` · playbook de destino de transição não existe · `priority` está ausente
  ou não é inteira · duas playbooks têm a mesma `priority`.
- **Não** é erro de boot: playbook sem `exits`. A validação só reprova **referência quebrada**
  (nome que não resolve), não ausência de desfecho.
- O mesmo erro reprova o CI — nenhuma dessas condições chega a uma conversa.
- Conjunto íntegro de playbooks sobe sem aviso e sem custo de LLM.

### US3 — Predicado como unidade registrada e testável

- Um predicado é uma classe que recebe o contexto de roteamento (e um argumento opcional) e devolve
  booleano, resolvida pelo nome usado no `when_state`.
- Uma lista `when_state` com múltiplas entradas só é satisfeita quando **todas** são verdadeiras.
- Predicado inexistente é erro de boot (US2), nunca `false` silencioso.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/playbook/loader_spec.rb`: frontmatter completo, frontmatter
  mínimo (só `name`/`title`/`priority`/`trigger`), corpo preservado, e `exits`/`when_state`/`tools`
  ausentes devolvendo coleção vazia (asserção explícita de `== []`, não de `nil`).
- `custom/spec/services/custom/scout_v2/playbook/validator_spec.rb`: um exemplo por classe de
  quebra listada em US2, incluindo `priority` ausente e `priority` duplicada — mais um exemplo
  **positivo** de playbook sem `exits` passando na validação.
- `custom/spec/services/custom/scout_v2/predicates/*_spec.rb`: verdadeiro/falso por predicado, e E
  lógico sobre lista com mais de uma entrada.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` (revisado e fechado em
> 2026-09-24); métricas de churn e contagens de caracteres vêm do §1.1 e §9 do mesmo documento.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
