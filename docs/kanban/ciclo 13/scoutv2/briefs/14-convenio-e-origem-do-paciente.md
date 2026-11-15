# Fase 14 — Processo do Negócio no Cadastro do ERP: Convênio, Carteirinha e Origem (Brief)

**Status**: Rascunho
**Data**: 2026-10-01
**Master doc**: `docs/kanban/ciclo 13/scoutv2/design.md` §4.5 (capabilities: o adapter injeta
configuração, o modelo vê só o que é conversa), §3 decisão 2 (playbook é arquivo compartilhado),
§8 (*"Playbook curada não cobre especificidade de um cliente → Parametrização por dado (estágios,
campos, catálogo, persona) primeiro"*), §6 (Fase 2)
**Depends on**: Brief 07 (spec `089-scout-v2-capabilities-scheduling`): contratos `scheduling` e
`customer_registry`, `Erp::Younus::Client`/`Adapter` e settings do hook `younus`, ainda não
commitados em `ichatr-main`. Endpoints `webhook/convenios` e `webhook/origens` do Younus, entregues
pelo usuário (§2).
**Ordem de execução**: antes da prova herdada do brief 13 (§7, "Prova herdada do brief 07"), para que
a prova contra o ERP real exercite o contrato final de cadastro; o 10 só promove conta real depois
deste brief.

---

## 1. Problema

O brief 07 (decisão 4; US2) classificou como **configuração da conta** todos os identificadores
que as `ScoutTool` do v1 pediam ao modelo, e a spec 089 os transformou em settings de valor único
do hook `younus` (`config/integration/apps.yml:350-411`), lidos por `Erp::Younus::Client`
(`client.rb:35-38`). Três deles não são configuração: dependem do paciente.

| Parâmetro | Descrição na `ScoutTool` do v1 (conta 1, dev) | Natureza real |
|---|---|---|
| `idConvenio` | *"Envie o id 1 para particular e 599 para Dental Uni."* | por paciente, dentre os convênios que o negócio cadastrou no Younus (ids por empresa: Dental Uni é `1370` na empresa 648) |
| `nrConvenio` | *"Obrigatório apenas se o convênio da pessoa for Dental Uni."* | por paciente, quando o convênio não é Particular |
| `idOrigempessoa` | *"Facebook: 1, Instagram: 5, Fachada: 2, Indicação de cliente: 4, Outro: 12"* | por paciente: de onde o lead veio, dentre a tabela de origens do Younus |
| `idEmpresa`, `idUsuario`, `idAgenda`, `idServico` | *"Sempre enviar o id …"* | configuração da conta — o 07 acertou |

Consequências do desenho atual da 089:

1. **Todo paciente cadastrado pelo Scout recebe o mesmo convênio e a mesma origem.**
2. **`nr_convenio` é exigido para particular**: `Erp::Younus::Adapter.capability_settings`
   (`adapter.rb:9-12`) o lista entre as chaves obrigatórias de `customer_registry`.
3. **O agendamento envia o convênio da conta, não o do paciente** (`client.rb:67`), mesmo para
   paciente localizado no ERP com outro convênio (`find_person_found.json:40-41`).

**O v1 não resolvia isso pela descrição da tool.** Langfuse, todas as 5 chamadas de
`cadastrar_pessoa` do v1 (conversas 121, 123 e 136, 2026-09-16 a 2026-09-23): origem perguntada em
0 de 3 conversas, `idOrigempessoa: 12` (Outro) nas 5; convênio perguntado em 2 de 3 (na 121, `1` sem
perguntar); no único paciente Dental Uni (conversa 123), `nrConvenio` vazio. A descrição de parâmetro
é lida na hora de montar a chamada; a pergunta precisava ter acontecido mensagens antes, e o modelo
preenche com o valor mais seguro.

## 2. Diagnóstico / Causa raiz

- **O Younus é multivertical** (clínicas, advogados, psicólogos, dentistas, cursos de idioma). O que
  perguntar ao lead antes de cadastrar é **processo do negócio**, não regra do ERP.
- **O fork já tem o lugar para processo por negócio**: atributos personalizados de oportunidade,
  exigidos na qualificação por scout (`ichatr_scout_required_fields`) ou por estágio
  (`ichatr_pipeline_stage_required_fields`), ambos lidos por
  `Custom::ScoutV2::RoutingSnapshot::PendingFields` (`pending_fields.rb:13-24`). A `qualificacao` do
  v2 pede e grava os pendentes via `manage_opportunity`. Pôr a pergunta em `agendamento.md` imporia o
  processo de uma clínica a todas as contas (design §3 decisão 2 e §8).
- **Campo opcional é invisível ao modelo no v2**: só entram nas instruções as chaves de
  `PendingFields` (`content_builder.rb:42-49`). Um campo "Carteirinha" opcional nunca é pedido; e
  exigido incondicionalmente seria pedido a quem é Particular.
- **O Younus expõe as listas** (entregues pelo usuário em 2026-10-01):
  - `GET /webhook/convenios?idEmpresa=<id>` → convênios **da empresa**. A empresa sempre vem com
    "Particular" pré-cadastrado; os demais são cadastrados pelo negócio. Os ids variam por empresa.
  - `GET /webhook/origens` (sem parâmetro) → origens do sistema, as mesmas para qualquer empresa:
    `1 Facebook · 2 Fachada · 3 Google · 4 Indicação de Cliente · 5 Instagram · 6 Outdoor ·
    7 Panfleto · 8 Rádio · 9 Site · 10 TV · 11 WhatsApp · 12 Outro · 13 Convênio`.
  - Corpo: `[{ "sucesso": true, "mensagem": "…", "dados": [{ "idConvenio": 925, "nomeConvenio":
    "Academias PHD" }, …] }]`. O endpoint de origens devolve hoje as mesmas chaves
    `idConvenio`/`nomeConvenio`.
- **Os valores do negócio não são os nomes do ERP.** O atributo de origem de produção
  (`origem_da_oprotunidade`) tem `Facebook/Instagram`, `Google`, `Site`, `Fachada`, `Indicação`,
  `Orgânico`, `Interno`. A correspondência com o Younus tem de ser regra fixa em Ruby, não escolha
  do modelo a cada envio — o mesmo valor tem de virar sempre o mesmo id.
- **Origem não é o canal de atendimento.** Um lead no WhatsApp pode ter clicado num anúncio do
  Facebook, e é esse o dado que importa. O fork já o grava sem perguntar, na criação da
  oportunidade: `manage_opportunity.rb:155-163` → `Custom::ReferralAttributionService` →
  `opportunity.campaign_platform` (`facebook`/`instagram`).
- **Atributo de lista aceita qualquer texto.** No dev, as oportunidades 101, 105, 121 e 142 têm
  `interesse: "Implantes"`, fora da lista (`"Implantes unitários"`, …). `manage_opportunity` não
  valida, e o v2 não mostra os valores permitidos que o v1 mostrava
  (`funnel_section_builder.rb:74-76`; `pending_fields_formatter.rb:13-18`).
- **Gap aceito**: o Younus exige origem para cadastrar, mas nada obriga o negócio a ter o atributo nem
  a exigi-lo na qualificação. Sem dado, a origem é "Outro".

## 3. Precedente

- **Ponteiro para atributo personalizado**: `Scout#interest_attribute_definition`
  (`scout.rb:14,115-120`) aponta um atributo de oportunidade e valida tipo e modelo. Mesma regra
  para os atributos apontados pelo hook.
- **Valores permitidos no prompt**: `Custom::Scout::SystemPrompts::FunnelSectionBuilder:74-76` (v1).
- **Pendência injetada por regra em Ruby**: `PHONE_MISSING_NOTICE` (`content_builder.rb:7-8`) e os
  campos pendentes por estágio já entram em `PendingFields` sem o modelo decidir.
- **Entrada dura na capability** (brief 07 decisão 2): input inválido falha antes da requisição e
  volta ao modelo como erro de tool, corrigível no mesmo turno.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | **Nenhum passo de convênio, carteirinha ou origem em `agendamento.md`.** O que perguntar é configurado por negócio como atributo de oportunidade | Playbook é compartilhada entre verticais (§2) |
| 2 | **Atributo de lista só aceita valor da lista.** `PendingFieldsFormatter` mostra os valores permitidos de atributos `list`; `Custom::ScoutV2::Tools::ManageOpportunity` rejeita valor fora da lista com erro de tool, citando os permitidos | Pré-requisito da correspondência por valor (§2). Vale para todos os atributos de lista; o v1 fica intocado |
| 3 | **Listas vêm dos endpoints do Younus**, lidas pelo `Erp::Younus::Client` (`convenios(id_empresa)`, `origens`). Chaves de leitura: `idConvenio`/`nomeConvenio` nos convênios e `idOrigem`/`nomeOrigem` nas origens (pré-requisito do usuário: renomear no endpoint de origens). `sucesso: false` ou corpo fora da forma → `Erp::ApiError` | Fonte da verdade é o ERP: nada de lista digitada no hook nem tabela no código |
| 4 | **Cache por empresa** em `Rails.cache` (Redis), 24h. Salvar o hook consulta sem cache e renova. No cadastro, valor sem correspondência no cache → uma consulta sem cache antes de desistir | Convênios mudam raramente e origens quase nunca; no caso normal o cadastro não ganha requisição (latência do turno é problema aberto no brief 13). A reconsulta cobre convênio cadastrado no Younus hoje |
| 5 | Hook `younus`: saem `id_convenio`, `nr_convenio` e `id_origem_pessoa` (schema, formulário, `visible_properties`, MANIFEST, adapter, client, `CallRecord`); entram, opcionais, **`atributo_convenio`** (oportunidade, `list`), **`atributo_carteirinha`** (oportunidade, texto) e **`atributo_origem`** (oportunidade, `list`) | O hook diz qual atributo do negócio corresponde a qual dado do ERP; sem eles, padrões (decisões 6 e 8). Corte limpo: a 089 não foi commitada nem chegou a produção |
| 6 | **Convênio**: valor do `atributo_convenio` → convênio da empresa de mesmo nome (sem caixa nem acento). Vazio ou atributo não configurado → "Particular". No save do hook: valor da lista sem convênio correspondente na empresa, ou empresa sem "Particular" → 422 citando o que falta. No cadastro, valor sem correspondência mesmo após reconsulta → erro de tool → `exit_handoff`, sem chamar o ERP | Convênio errado é cadastro errado no ERP; a correspondência é exata e falha cedo |
| 7 | **Carteirinha é pendência condicional**: com `atributo_convenio` e `atributo_carteirinha` configurados, convênio preenchido e diferente de "Particular" e carteirinha vazia → `PendingFields` inclui a carteirinha. A `qualificacao` a pede e grava via `manage_opportunity`; o exit `qualificado` (`Exits::StageMove`, só no v2) recusa enquanto `PendingFields` não estiver vazio. No cadastro, `nrConvenio` = valor do atributo, ou vazio | É regra do processo (o v1 cadastrou Dental Uni com `nrConvenio: ""` e confirmou o agendamento ao lead na conversa 123 — indício de que o ERP não a exige; resposta do ERP não conferida). Campo exigido incondicional pediria carteirinha a particular; opcional nunca seria pedido (§2). Uma regra em Ruby, uma fonte (`PendingFields`) para pedir e para barrar |
| 8 | **Origem**, em Ruby, nesta precedência: (a) referral da oportunidade — `campaign_platform` → origem do Younus de mesmo nome (`facebook` → Facebook, `instagram` → Instagram); (b) valor do `atributo_origem` → origens do Younus cujo nome normalizado é igual, contém ou está contido no valor; **uma** correspondência → ela; **mais de uma** (ex.: `Facebook/Instagram`) → `customer_registry_create` exige o input `origem`, com `enum` restrito às candidatas, e o modelo a preenche com o que o lead disse (perguntando se ele não disse); (c) nenhuma, vazio ou atributo não configurado → "Outro", com `deviation` no `capability_call` quando havia valor | Regra do usuário: viu no Facebook, Facebook; no Instagram, Instagram. O valor do negócio pode agrupar o que o ERP separa; só nesse caso o modelo escolhe, e só entre as candidatas, nunca o id |
| 9 | **Origem pré-preenchida pelo referral**: na criação da oportunidade pelo v2, depois de `ReferralAttributionService`, se `atributo_origem` está configurado, há `campaign_platform` e o atributo está vazio → grava o valor da lista do negócio que contém o nome da plataforma, quando for um só | O lead que veio de anúncio não é perguntado: o atributo deixa de ser pendente. Sem anúncio, continua pendente (se exigido) e a qualificação pergunta. Só no v2 (`Custom::ScoutV2::Tools::ManageOpportunity`) |
| 10 | O agendamento envia o convênio **do paciente**: `remember_customer!` guarda `convenio_id` — do cadastro do ERP quando localizado (`idConvenio`), do resolvido quando criado — e `scheduling_book` o lê de `capability_state` | O convênio do agendamento é o do paciente atendido |
| 11 | Satisfação no `Registry`: `customer_registry` exige `token`, `id_empresa`, `id_usuario`; `scheduling` exige `token`, `id_empresa`, `id_agenda`, `id_servico`, `id_usuario`. Os `atributo_*` ficam fora | Convênio e origem têm padrão; os atributos são opcionais por desenho. Falha dos endpoints no cadastro é `erp_error` → `exit_handoff` |

**Desvio consciente do brief 07 (decisão 4 e US2)**: o modelo continua sem fornecer nenhum id. Os
valores por paciente vêm do que a qualificação do negócio coletou; o modelo só escolhe a origem entre
candidatas quando o valor do negócio é ambíguo (decisão 8).

## 5. Escopo preliminar

- `custom/app/services/custom/scout_v2/playbook/pending_fields_formatter.rb`: valores permitidos de
  atributos `list` (decisão 2).
- `custom/app/services/custom/scout_v2/tools/manage_opportunity.rb`: rejeição de valor fora da lista
  (decisão 2); pré-preenchimento da origem pelo referral (decisão 9).
- `custom/app/services/custom/scout_v2/routing_snapshot/pending_fields.rb`: pendência condicional da
  carteirinha (decisão 7); `custom/app/services/custom/scout_v2/exits/stage_move.rb`: `qualified`
  recusa com pendência.
- `config/integration/apps.yml` (bloco `younus`) + `insert:` da entrada MANIFEST em
  `bin/sync-custom-module-hooks`: chaves da decisão 5.
- `custom/app/models/custom/integrations/hook.rb`: validações das decisões 5 e 6, só para `younus`,
  consultando os endpoints sem cache.
- `custom/app/services/erp/younus/client.rb`: `convenios`, `origens`; `create_person` e
  `create_appointment` recebem convênio, carteirinha e origem por parâmetro, não de `@settings`.
- `custom/app/services/erp/younus/adapter.rb`: `capability_settings` e `OPERATION_IDENTIFIER_KEYS`
  sem as chaves removidas; cache (decisão 4); resolução de convênio (6) e origem (8);
  `find_person` devolve `convenio_id` do cadastro.
- `custom/app/services/custom/scout_v2/capabilities/customer_registry.rb`: leitura da oportunidade
  da conversa; input `origem` só no caso ambíguo, com `enum` por chamada; erros da decisão 6.
- `capabilities/scheduling.rb` + `custom/app/models/scout_conversation_state.rb`: `convenio_id` em
  `capability_state['customer']`, lido no `book`.
- `capabilities/registry.rb` e `capabilities/call_record.rb`: chaves da decisão 11; o registro da
  chamada traz `id_convenio`/`id_origem_pessoa` enviados e a fonte de cada um (`referral`,
  `atributo`, `lead`, `padrao`) — ids, nunca token.
- Specs da 089 que fixam as chaves antigas: cutover (`app_spec`, `hook_spec`, `client_spec`,
  `adapter_spec`, `registry_spec`, `operation_tool_spec`, `builder_spec`).
- Pré-requisito do usuário: `webhook/origens` devolvendo `idOrigem`/`nomeOrigem`.
- Operacional (conta 1): atributos `origem_da_oprotunidade`, `convenio` e `carteirinha` já criados
  e os dois primeiros já exigidos no scout 1 (2026-10-01); recriar o hook `younus` com os
  `atributo_*` (o formulário não edita hook existente — `NewHook.vue` só cria), apontando para uma
  empresa cujos convênios coincidam com a lista do atributo (`Academias PHD`, `Dental Uni`,
  `Particular` coincidem com a empresa 648).

## 6. Fora de escopo

- **Atributos personalizados criados pela integração** (ao ativar o Younus, criar e sincronizar as
  listas de convênio e origem). Hoje convênio novo no Younus precisa ser acrescentado à lista do
  atributo à mão; o save do hook acusa a divergência.
- **Campos obrigatórios condicionais ou por fase como recurso genérico do funil** (ex.: motivo da
  perda exigido ao ir para o estágio de perda). A carteirinha da decisão 7 é regra específica da
  integração; o recurso genérico é brief futuro do usuário.
- Tornar origem obrigatória na qualificação porque o Younus a exige (gap aceito, §2).
- Usar o canal da inbox como origem (§2).
- Seletor de atributo no formulário do hook (os `atributo_*` são texto, validados no save).
- Atualizar convênio de paciente já existente no ERP.
- Rótulos traduzidos do formulário do hook (mesmo desvio aceito no plano da 089).
- Qualquer alteração no v1, inclusive validar lista no `manage_opportunity` do v1.
- Instruir convênio e origem por texto em "Escopo e Limites" (`scope`): texto sempre presente, longe
  do momento do cadastro — o modo de falha medido no v1 (§1) — e duplica o campo exigido na
  qualificação.

**Em aberto para o `/speckit-clarify`**:
- Paciente localizado no ERP **sem** `idConvenio` no cadastro: usar o convênio resolvido pela
  decisão 6, ou transferir. Decidir com uma resposta real do `pesquisar-pessoa` para esse caso.
- Confirmar com uma chamada real que o `incluir-cliente` aceita `nrConvenio` vazio para convênio
  diferente de Particular (decisão 7 se apoia no indício da conversa 123).

## 7. Critérios de aceite (rascunho)

### US1 — Valores válidos na qualificação e atributos ligados ao ERP

- Com um atributo `list` pendente, as instruções da qualificação listam os valores permitidos;
  `manage_opportunity` com valor fora da lista falha com erro de tool citando os permitidos, e nada
  é gravado.
- O formulário do hook `younus` tem os três `atributo_*` e não tem mais `Agreement ID`,
  `Agreement number` nem `Person origin ID`.
- `atributo_*` inexistente, de contato ou do tipo errado → 422; valor do atributo de convênio sem
  convênio correspondente na empresa, ou empresa sem "Particular" → 422 citando o que falta.
- Hook só com `token` e `id_empresa` continua válido e o card de dados do ERP funciona como antes.
- Depois do save, um cadastro não faz requisição aos endpoints enquanto o cache vale.

### US2 — Convênio e carteirinha vêm do processo do negócio

- Conta sem `atributo_convenio`: o cadastro usa "Particular"; nenhuma pergunta de convênio.
- Oportunidade com `convenio: "Dental Uni"` e carteirinha vazia: a carteirinha aparece entre os
  campos pendentes, a qualificação a pede, e `exit_qualificado` é recusado até ela ser gravada; com
  ela, o ERP recebe o `idConvenio` da Dental Uni **da empresa** e o `nrConvenio`.
- `convenio: "Particular"`: a carteirinha nunca é pedida e vai vazia.
- Valor de convênio sem correspondência mesmo após a reconsulta → nenhuma requisição de cadastro ao
  ERP; `exit_handoff`.
- Agendamento envia o convênio do paciente: o do cadastro do ERP para paciente localizado; o
  resolvido para paciente criado. Verificável no `capability_call` do span.
- `agendamento.md` não menciona convênio, carteirinha nem origem.

### US3 — Origem vem do anúncio ou do processo do negócio

- Lead de anúncio do Instagram, conversa pelo WhatsApp: na criação da oportunidade o atributo de
  origem recebe `Facebook/Instagram`, a qualificação não pergunta a origem e o ERP recebe
  `idOrigempessoa` de Instagram.
- Sem referral, `Google` → origem Google; `Indicação` → Indicação de Cliente.
- Sem referral, `Facebook/Instagram` e o lead disse "vi no Instagram" → Instagram; se o lead não
  disse qual, o Scout pergunta antes de cadastrar; o input `origem` só aceita Facebook ou Instagram.
- `Orgânico`, `Interno`, atributo vazio ou não configurado → Outro, com `deviation` quando havia
  valor; o cadastro não falha.

## 8. Testes (rascunho)

- `pending_fields_formatter_spec.rb` e `scout_v2/tools/manage_opportunity_spec.rb`: valores
  permitidos; valor fora da lista rejeitado sem gravar; pré-preenchimento da origem pelo referral.
- `routing_snapshot/pending_fields_spec.rb` e `exits/stage_move_spec.rb`: carteirinha pendente só
  com convênio diferente de Particular; `qualified` recusado com pendência.
- `custom/spec/models/custom/integrations/hook_spec.rb`: validações das decisões 5 e 6 com WebMock
  dos endpoints; rejeição das chaves removidas.
- `erp/younus/client_spec.rb` / `adapter_spec.rb`: leitura dos endpoints (`sucesso: false` → erro),
  cache e reconsulta no miss, resolução de convênio e de origem (uma, várias, nenhuma
  correspondência), parâmetros novos no corpo enviado.
- `capabilities/customer_registry_spec.rb`: input `origem` exigido só no caso ambíguo e restrito às
  candidatas; precedência referral > atributo > Outro, com WebMock conferindo o corpo.
- `capabilities/scheduling_spec.rb`: `book` envia o `convenio_id` guardado do paciente.
- `capabilities/registry_spec.rb`: satisfação pela decisão 11, com hooks reais.
- Verificação no playground contra o ERP de teste, com a configuração da clínica (§5): um paciente
  particular e um Dental Uni qualificados, cadastrados e agendados, com convênio, carteirinha e
  origem conferidos no ERP.

---

> **Nota de proveniência**: levantado em 2026-10-01 ao configurar o hook `younus` da conta 1 para a
> prova do brief 13. Descrições dos parâmetros: 4 `ScoutTool` da conta 1 (dev). Comportamento do v1:
> observações `tool.call_custom_api` no Langfuse e mensagens das conversas 121, 123 e 136. Valores
> fora da lista: oportunidades 101, 105, 121 e 142 (dev). Endpoints e corpos de resposta, valores do
> atributo de origem de produção e regras de negócio (multivertical; Particular sempre
> pré-cadastrado; carteirinha só para conveniado; Facebook e Instagram registrados separadamente
> conforme o lead disse): do usuário.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
