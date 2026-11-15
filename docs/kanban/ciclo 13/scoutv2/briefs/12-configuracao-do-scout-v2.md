# Fase 12 — Configuração do Scout para o v2: Identity e Estilo na Tela (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-25
**Master doc**: `docs/kanban/scoutv2/design.md` §3 (decisão 6), §4.1, §6 (checklist de promoção)
**Depends on**: Brief 04 — colunas `tone`/`response_length`/`greeting` e os builders de Instructions.
**Ordem de execução**: numerado no fim da lista. Independe de 11, 05, 06 e 07; tem de estar entregue
**antes do 10**, cujo preflight cobra `role`/`scope`. Recomendado antes do 06, para que a
verificação de playground das seis playbooks rode com o contexto da conta, como vai rodar em
produção.

---

## 1. Problema

Duas lacunas deixadas pelo brief 04, achadas na revisão final do código:

1. **O v2 não sabe quem é nem o que a empresa faz.** `Identity` é texto fixo
   (`custom/app/services/custom/scout_v2/instructions/identity_builder.rb:14-20`: nome do scout,
   nome da conta e uma frase genérica de qualificação). O v1 injeta a `persona` da conta
   (`system_prompts_service.rb:173-183`), e o v2 não lê esse campo. Promover uma conta hoje
   apagaria do prompt o nome da assistente, o público atendido e o que ela não pode fazer.
2. **Estilo só se configura pelo console.** `tone`, `response_length` e `greeting` existem no
   model (`custom/app/models/scout.rb:23-26`, `db/schema.rb`), mas ficaram fora de `scout_params`
   (`custom/app/controllers/api/v1/accounts/scouts_controller.rb:66-70`) e da tela
   (`ScoutGeneralSettings.vue`) de propósito (`specs/084-scout-instructions-open-playbook/research.md`
   §8). O brief 10 não cobre isso: a UI dele é só a sinalização em `ScoutToolsList.vue`.

**Por que não reaproveitar `persona`.** O problema é o contrato do campo, não o conteúdo que uma
conta pôs nele. A tela apresenta o campo como "Persona e Prompt do Sistema" e pede "personalidade,
tom de voz e diretrizes comerciais" e "critérios de qualificação, tom de objeções e instruções de
pitch" (`scout.json:57-59`). O v1 o injeta como "Instruções Personalizadas da Conta", com poder de
refinar diretrizes globais (`system_prompts_service.rb:173-183`). No v2 cada um desses assuntos tem
lugar próprio: papel e escopo em `Identity`, tom e tamanho nos enums de `Communication`, critério de
qualificação nos campos obrigatórios e na playbook `qualificacao`, regra situacional nas playbooks e
na `Escalation`. Um campo que aceita tudo isso, injetado em todo turno, recoloca por conta o balde de
prosa que o épico remove. As personas existentes foram escritas para o v1 e suas limitações, e não
servem de molde para o v2.

## 2. Contexto técnico

- `custom/app/models/scout.rb:6` — `alias_attribute :system_prompt, :persona`; `persona` só é lida
  pelo v1.
- `custom/app/services/custom/scout_v2/instructions/communication_builder.rb:28-49` — `tone`,
  `response_length` e `greeting` já viram diretiva fixa no prompt.
- `scouts_controller.rb:66-70` — allowlist de `scout_params`.
- `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutGeneralSettings.vue:101-114`
  e `i18n/locale/{en,pt_BR}/scout.json:57-59` — o contrato do campo `persona`: prompt de sistema
  livre, com tom, critérios de qualificação e pitch.
- `db/schema.rb` — `inboxes.greeting_enabled`/`greeting_message`: a caixa de entrada já pode enviar
  saudação própria, então a do Scout pode duplicar.
- Rails 7.2: `enum ..., validate: true` transforma valor fora do conjunto em erro de validação
  (422) em vez de `ArgumentError`.

## 3. Precedente

- **Painel Botpress** (design §2.3): `Instructions > Identity` tem `Role` e `Scope` como campos
  nomeados, separados de `Communication`. Aplica-se diretamente.
- **Captain V2**: `AssistantMigration::InstructionClassifier` decompõe o prompt livre do V1 em
  descrição, diretrizes, guardrails e candidatos a scenario, **com `needs_review`** (design §2.4).
  Nem o upstream confia na separação automática sem revisão humana; aqui a revisão é a própria
  reescrita.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | Colunas novas `role` e `scope` no scout, texto livre com **limite de 500 caracteres** cada, validado no model | Campo nomeado e curto força o conteúdo certo no lugar certo; o limite impede colar a persona inteira (design decisão 6) |
| 2 | `Identity` = moldura fixa + `role` + `scope`. Vazios, cai na moldura fixa de hoje | Scout novo ou ainda não reescrito continua funcionando; o preflight do brief 10 impede promover com os campos vazios sem que o operador veja |
| 3 | O v2 **não lê `persona`**; ela fica intocada e segue alimentando o v1 | Rollback pela flag tem de devolver o v1 como era. A remoção de `persona` é da depreciação (brief 10) |
| 4 | **Sem migração automática** de `persona` para `role`/`scope` | Não há separação determinística de prosa; separar por LLM é estocástico e o próprio Captain exige revisão. E o conteúdo foi escrito para o v1: no v2 boa parte vira enum, campo obrigatório ou playbook. Quem conhece o negócio escreve `role`/`scope` do zero |
| 5 | `scout_params` aceita `role`, `scope`, `tone`, `response_length` e `greeting`; valor fora do enum ou acima do limite devolve **422** | `AGENTS.md`: validar na borda e responder 422, sem coerção de valor malformado |
| 6 | A tela de configuração do scout mostra os cinco campos **sempre**, sem condicionar à flag `scout_v2`, com textos de ajuda indicando que valem para a nova versão do Scout. **Revista pelo brief 10 (decisões 9 e 10, 2026-10-01): os cinco campos passam a aparecer só com `scout_v2`** | O administrador precisa preencher **antes** da promoção, enquanto a conta ainda roda v1. Condicionar à flag criaria o ovo e a galinha: os campos só apareceriam depois de o v2 já estar respondendo clientes. Mostrar configuração não é escolher engine (brief 10, decisão 2) |
| 7 | O texto de ajuda de `greeting` orienta a deixar em branco quando a caixa de entrada já envia saudação | Evita saudação duplicada com `inboxes.greeting_enabled` sem código novo |

## 5. Escopo preliminar

- Migração: `role` e `scope` em `ichatr_scouts`; validação de tamanho em `Scout`; `validate: true`
  nos enums `tone` e `response_length`.
- `identity_builder.rb`: moldura fixa + `role` + `scope`, com a moldura atual quando vazios.
- `scouts_controller.rb`: os cinco campos em `scout_params`; serialização de volta ao frontend.
- `ScoutGeneralSettings.vue`: seção com `role`, `scope` (textarea com limite), `tone` e
  `response_length` (select com rótulos traduzidos), `greeting`; `persona` permanece.
- i18n: `en.json` e `pt_BR.json` (`scout.json`) para rótulos, opções dos enums e ajudas;
  `en.yml`/`pt_BR.yml` para as mensagens de validação.

## 6. Fora de escopo

- Remover `persona` (coluna, alias, API, tela): fora do brief 10 também (depreciação reversível,
  esconder sem apagar).
- Condicionar campos à flag `scout_v2`: feito no brief 10 (decisão 9).
- Assistente de migração que sugira `role`/`scope` a partir da `persona`: sem evidência de que a
  reescrita manual seja gargalo.
- Tom `Custom` ou texto livre de estilo (design decisão 6).
- Qualquer alteração no v1.

## 7. Critérios de aceite (rascunho)

### US1 — `Identity` vem de `role` e `scope`

- Com `role` e `scope` preenchidos, a seção `Identity` do prompt v2 contém os dois textos.
- Com ambos vazios, `Identity` é a moldura fixa de hoje.
- O conteúdo de `persona` não aparece em nenhuma parte do prompt v2.
- O prompt do v1 continua idêntico, com a `persona` onde está hoje.

### US2 — Identity e estilo configuráveis na tela e na API

- Na tela de configuração do scout, o administrador edita `role`, `scope`, `tone`,
  `response_length` e `greeting`, em inglês e português; salvar muda o próximo prompt v2 sem
  console.
- `tone` e `response_length` são escolhidos numa lista fechada com os rótulos traduzidos dos
  valores do enum.
- Pela API, valor de enum inválido ou texto acima de 500 caracteres devolve 422 com mensagem
  traduzida, sem gravar nada.
- A ajuda de `greeting` orienta sobre a saudação da caixa de entrada.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/instructions/identity_builder_spec.rb`: com e sem
  `role`/`scope`; `persona` ausente do resultado.
- Spec de request de `scouts_controller`: os cinco campos gravados; 422 para enum inválido e para
  texto acima do limite.
- Spec de componente de `ScoutGeneralSettings.vue`: campos presentes e payload enviado.
- Verificação no playground: preencher `role`/`scope` do scout de dev e conferir a `Identity` no
  trace.

---

> **Nota de proveniência**: decorre da revisão final do código do brief 04 (Identity fixa, `persona`
> ignorada, estilo só por console, `specs/084-scout-instructions-open-playbook/research.md` §8).
> Contrato do campo `persona`: `scout.json:57-59` e `system_prompts_service.rb:173-183`.
> Design revisado em 2026-09-25 (decisão 6 e checklist de promoção).
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
