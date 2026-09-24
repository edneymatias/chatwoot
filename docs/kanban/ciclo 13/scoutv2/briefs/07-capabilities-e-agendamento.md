# Fase 07 — Capabilities e Agendamento Ponta a Ponta (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §4.5 (capabilities), §6 (Fase 2)
**Depends on**: Brief 06 — `agendamento` já existe e degrada com `requires` insatisfeito; este brief
satisfaz as capabilities e fecha o fluxo.

---

## 1. Problema

Medido no ambiente de dev: as **4 `ScoutTool` ativas** apontam todas para
`wfh.ichatr.com.br/webhook/*` — o mesmo backend do `Erp::Younus::Client`
(`custom/app/services/erp/younus/client.rb:6,9-19,29-30`) — e obrigam o **modelo** a produzir
parâmetros que são configuração, não conversa:

| Tool | Endpoint | Parâmetros exigidos do modelo |
|---|---|---|
| `pesquisar_cliente` | `GET /webhook/pesquisar-pessoa` | `idEmpresa`, `nrTelcelpessoa` |
| `cadastrar_pessoa` | `POST /webhook/incluir-cliente` | `nmPessoa`, **`idEmpresa`, `idUsuario`, `idConvenio`, `nrConvenio`, `idOrigempessoa`**, `nrTelcelpessoa` |
| `obter_horarios_livres` | `GET /webhook/horarios-livres` | `data`, **`idAgenda`, `idEmpresa`, `idServico`** |
| `agendar` | `POST /webhook/incluir-agendamento` | **`idAgenda`, `idEmpresa`, `idServico`, `idUsuario`, `idConvenio`**, `idPessoa`, `nmTitulo`, `dtIniAgenda`, `observacoes` |

Em negrito: configuração. `idEmpresa` **já está nas settings do hook**
(`config/integration/apps.yml:348` para `category: erp`, `:350` para
`visible_properties: ['id_empresa','token']`) e mesmo assim o modelo é obrigado a produzi-lo — é
superfície de alucinação projetada, num caminho que escreve no ERP do cliente.

## 2. Contexto técnico

- `custom/app/services/erp/base_adapter.rb:9-25` e `erp/adapter_factory.rb:5-10` — a camada de
  contrato **já existe no fork**; só não estava exposta ao Scout.
- `config/integration/apps.yml:341-350` — catálogo por categoria, com `category: erp` em `:348`.
- `erp_controller.rb:19-22` — já resolve por categoria (`h.app&.params&.dig(:category) == 'erp'`),
  mantido um fallback por vendor para compatibilidade.
- `custom/app/services/erp/younus/client.rb:24-73` — os métodos existentes do cliente; os 4 do
  fluxo de agendamento ainda não estão lá.
- `custom/app/services/custom/scout/tools/call_custom_api.rb:6-21` e
  `custom/app/models/scout_tool.rb:14,82-89` — a tool genérica de HTTP configurada por conta: sem
  capability, o contrato para a playbook é instável e a superfície de prompt cresce com
  configuração de cliente.

## 3. Precedente

- **Botpress** (design §2.3): o `New HTTP tool` separa `Params/Body/Auth/Headers` (configuração
  fixa) de `Inputs` (*"Variables the LLM must provide"*). É exatamente a distinção que o
  `ScoutTool` hoje não faz, e é o desenho que a capability implementa no lado Ruby.
- **Escopo de tools** (`llms-full.txt:9844-9845`): tools da playbook entram no conjunto quando ela
  está ativa. Aplica-se às capabilities do mesmo modo que às tools nativas.
- `Erp::BaseAdapter`/`AdapterFactory` **do próprio fork**: o precedente interno de "contrato na
  frente, vendor atrás" — reaproveitado inteiro. Não se aplica o `AdapterFactory` como ponto de
  entrada do Scout: a resolução passa a ser por **registro de capability**, não por factory de
  vendor, para manter a porta aberta a provedores futuros sem tocar playbook nem adapter.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | **Capability é contrato do fork**, satisfeita por integração | Arquivo de playbook é compartilhado entre contas e não pode nomear linha de banco de uma conta (decorrência direta de "playbook é arquivo", design decisão 3) |
| 2 | Contrato **duro na entrada**, **mole na saída** | Na entrada a playbook escreve a chamada e o erro é do nosso lado; na saída o retorno vai como texto/JSON ao modelo e validação bloqueante só transformaria variação do fornecedor em turno quebrado. Exit é onde o rigor compra determinismo, porque decide fluxo (design decisão 3) |
| 3 | Resolução por **registro**, não por factory de vendor: `CapabilityRegistry.resolve(:scheduling, account:)` | Quem satisfaz é detalhe de implementação; playbook e adapter não se conhecem (design §4.5) |
| 4 | O adapter injeta credenciais e IDs de configuração; o modelo vê **só** `date`, `service`, `slot_id` e afins | Remove a superfície de alucinação medida na tabela do §1 |
| 5 | **`ScoutTool` não participa do v2** neste corte; `call_custom_api` morre | Sem capability, a tool é contrato instável para a playbook. Provider HTTP de capability é o item 6.1 do design, com gatilho declarado: primeiro cliente sem adapter para a capability de que precisa (design decisão 4) |

## 5. Escopo preliminar

- `custom/app/services/custom/scout_v2/capabilities/registry.rb`: catálogo + `resolve(name,
  account:)`, devolvendo insatisfeita quando não há adapter.
- `custom/app/services/custom/scout_v2/capabilities/base.rb`: DSL `capability :nome do ... input
  ... output ... end`.
- `capabilities/scheduling.rb`: `list_slots(date, service?)` → lista com `slot_id`/`starts_at`;
  `book(slot_id, notes?)` → `appointment_id`.
- `capabilities/customer_registry.rb`: `find_by_phone(phone)`; `create(...)`.
- `custom/app/services/erp/younus/client.rb` + `adapter.rb`: 4 métodos novos cobrindo os endpoints
  da tabela do §1, com `idEmpresa`/`idUsuario`/`idConvenio`/`idAgenda`/`idServico` vindos das
  settings do hook, não do modelo.
- `custom/playbooks/agendamento.md`: passos completos (cadastro → horários → reserva → confirmação
  → exit), sem pendência.
- Exposição das capabilities resolvidas ao modelo como tools, só com a playbook ativa (mecanismo do
  brief 04).

## 6. Fora de escopo

- `ScoutTool` como provider de capability e a separação `Params`/`Inputs`: design §6.1.
- Qualquer outro vendor de ERP além do Younus: o registro existe para permitir, não para antecipar.
- Alterar o `Erp::AdapterFactory` ou `erp_controller.rb` para além do necessário à resolução por
  categoria já existente.
- Validação bloqueante do retorno do fornecedor (decisão 2).

## 7. Critérios de aceite (rascunho)

### US1 — Contrato de capability com entrada dura e saída declarada

- Uma capability declara operações com inputs tipados e obrigatoriedade explícita, e uma forma de
  saída (`required:` + `shape:`).
- Chamada com input faltando ou de tipo errado falha **antes** de qualquer requisição externa, e o
  erro volta ao modelo como erro de tool, corrigível no mesmo turno.
- Retorno do fornecedor fora da forma declarada é registrado e segue ao modelo — não derruba o
  turno.
- `CapabilityRegistry.resolve` devolve "insatisfeita" quando a conta não tem integração, sem
  levantar exceção — é o que alimenta a degradação do brief 06.

### US2 — O adapter esconde configuração do modelo

- Nenhuma operação de capability exige do modelo `idEmpresa`, `idUsuario`, `idConvenio`,
  `nrConvenio`, `idOrigempessoa`, `idAgenda` ou `idServico`.
- Esses valores vêm das settings do hook da conta (`visible_properties` de `category: erp`); conta
  sem eles resulta em capability insatisfeita, não em chamada malformada ao ERP.
- Os quatro endpoints do §1 estão acessíveis via `scheduling`/`customer_registry`.

### US3 — Agendamento ponta a ponta no playground

- Lead qualificado com telefone: `agendamento` ativa por estado, localiza ou cria o cadastro,
  oferece **no máximo três** horários em linguagem natural, reserva o escolhido e encerra em
  `exit_agendado` com `opportunity_id` e `starts_at` preenchidos.
- Sem horário na janela pedida, oferece a próxima data disponível; recusadas todas, encerra em
  `exit_sem_horario` com motivo.
- Pedido de atendente, urgência clínica ou duas falhas de cadastro encerram em `exit_handoff`.
- O IDs enviados ao ERP vêm do hook, verificável no registro da chamada.
- `exit_agendado` é impossível sem que `scheduling.book` tenha rodado — a asserção que substitui o
  `ClaimConsistencyService` nesse caminho (design §4.6).

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/capabilities/registry_spec.rb`: resolução satisfeita e
  insatisfeita.
- `custom/spec/services/custom/scout_v2/capabilities/scheduling_spec.rb`: input obrigatório
  ausente → erro antes da requisição; retorno fora da forma → segue com registro.
- `custom/spec/services/erp/younus/client_spec.rb` (extensão): os 4 métodos novos, com IDs de
  configuração injetados e não recebidos por parâmetro.
- Flow test de `agendamento` com capabilities dubladas: caminho feliz, sem horário, e handoff.
- Verificação no playground contra o hook real, conferindo os IDs enviados.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §4.5 e §6 (Fase 2); a
> tabela de parâmetros do §1 foi levantada das 4 `ScoutTool` ativas no ambiente de dev durante o
> design (§9, "Dados do ambiente de dev").
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
