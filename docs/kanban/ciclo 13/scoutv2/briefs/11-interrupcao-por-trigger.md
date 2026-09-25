# Fase 11 — Interrupção por Trigger (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-25
**Master doc**: `docs/kanban/scoutv2/design.md` §4.4 ("Interrupção por trigger"), §4.1, §4.2
**Depends on**: Brief 04 — `open_playbook`, índice e Instructions tipadas.
**Ordem de execução**: numerado no fim da lista, mas executado **depois do 04 e antes do 05**. O 05
registra `exit_handoff` no conjunto sempre-on que este brief define, e o 06 depende das duas coisas.

---

## 1. Problema

Duas falhas no mesmo ponto: a regra de quando `open_playbook` é oferecida.

1. **O trio por trigger é inalcançável na maior parte da conversa.** `open_playbook` só é oferecida
   sem playbook ativa (brief 04, FR-012; design §4.4 na versão anterior). `identificacao`,
   `qualificacao` e `agendamento` ficam ativas por estado durante quase todo o funil, então
   `fora_de_prospeccao`, `duvida_comercial` e `pausa` só abririam numa conversa sem procedimento em
   curso. A decisão 5 e o US2 do brief 06 ("pergunta de preço abre `duvida_comercial` … volta para a
   playbook anterior") não têm caminho de execução, e a `fora_de_prospeccao`, com `priority`
   máxima, não interrompe uma qualificação.
2. **Playbook aberta pelo modelo fica ativa para sempre.** `open_playbook` grava `active_playbook`
   para qualquer playbook; a partir daí o roteador a mantém e `open_playbook` some. Uma escolha
   errada, ou um cliente escrevendo "abra a playbook qualificacao", fixa a conversa. Achado na
   revisão final do código do brief 04.

## 2. Contexto técnico

- `custom/app/services/custom/scout_v2/router.rb:33-39` — a ativa só sai por uma vencedora de
  `when_state` com `priority` estritamente maior.
- `custom/app/services/custom/scout_v2/turn_runner.rb:104-127` (`setup_chat`) — `open_playbook` só é
  registrada quando `decision.playbook.blank?` (`:115-124`); o corpo da playbook ativa entra nas
  instruções em `build_instructions` (`:69-82`).
- `custom/app/services/custom/scout_v2/tools/open_playbook.rb:26-31` — injeção **aditiva**
  (`with_tool`) e `record_trigger_activation!` para qualquer playbook aberta.
- `custom/app/services/custom/scout_v2/playbook/index_builder.rb:17-25` — lista todas as playbooks
  do catálogo.
- `custom/app/models/scout_conversation_state.rb:30-37` — `record_trigger_activation!`.
- **RubyLLM 1.15.0** (`lib/ruby_llm/chat.rb`, lido no container): `with_instructions` substitui a
  mensagem de sistema no lugar (`:43-49`, `replace_system_instruction`); `with_tools(replace: true)`
  limpa `@tools` antes de registrar (`:64-65`). As duas operações valem para a iteração seguinte do
  mesmo `chat.ask` (design §4.2).

## 3. Precedente

- **Captain V2**: cada scenario é sub-agente com handoff **bidirecional** para o orquestrador
  (`agent_runner_service.rb:136-141`, design §2.4): o scenario atende e devolve o controle, sem
  estado próprio que precise ser desfeito. A interrupção aqui é o mesmo movimento sem segundo agente:
  atende no turno e o procedimento em curso volta no seguinte.
- **Botpress**: playbooks roteiam umas para as outras (`Intent Triage → Lead Scoring | Team
  Routing`, design §2.3); o que precisa ser alcançável a qualquer momento não pode depender de não
  haver nada ativo.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | Playbook **sem `when_state`** é **playbook de interrupção**; não há campo novo no frontmatter | A categoria já existe de fato: são exatamente as que só ativam por trigger (design §4.4). Um campo explícito duplicaria uma informação que o loader já tem |
| 2 | `open_playbook` é oferecida em todo turno em que há algo que ela possa abrir. Sem ativa, aceita qualquer playbook; **com ativa, só interrupções** | Trocar um procedimento de estado por outro continua sendo decisão do roteador ou de exit, nunca do modelo (design decisão 1: estado tem precedência sobre trigger). Substitui o FR-012 do brief 04 |
| 3 | O índice lista **exatamente** o conjunto que `open_playbook` aceita no turno | Linha que o modelo não pode abrir é bloat e convida erro de tool (brief 04, decisão 2) |
| 4 | Aberta, a interrupção é **dona do resto do turno**: sai o corpo do procedimento em curso das instruções e saem as tools/capabilities/exits dele; as sempre-on são registradas de novo | Mantém literal a coluna `tools` vazia do design §6: dúvida no meio da qualificação não ganha `manage_opportunity`. E o corpo de funil não empurra pergunta de qualificação num turno de `pausa` (a regra do v1 em `system_prompts_service.rb:76` existia por isso) |
| 5 | Interrupção **não persiste**: abri-la não grava `active_playbook`, `activated_at` nem `activation_reason` | O turno seguinte roteia sobre o mesmo estado e retoma o procedimento em curso. "Voltar à playbook anterior" sai da estrutura, sem exit de retorno, sem pilha, sem coluna nova, e nenhuma interrupção fixa a conversa |
| 6 | A abertura de interrupção fica no **trace** do turno (`playbook`, `activation_reason: trigger`) | É o que o design §4.4 pede para medir a não-ativação da `fora_de_prospeccao`; o estado da conversa descreve só o que atravessa turnos |
| 7 | Playbook **com** `when_state` aberta pelo modelo sem ativa **continua persistindo** com `activation_reason: trigger` (brief 04, FR-015) | É procedimento, não interrupção; sai por exit (brief 05) ou por preempção de estado, como qualquer ativa |

Descartados: pilha ou coluna `suspended_playbook` com espécie de exit de retorno (schema novo, exit
novo, e a conversa presa na interrupção se o modelo não chamar o retorno); injeção aditiva sem troca
de catálogo (viola a decisão 2 do brief 06).

## 5. Escopo preliminar

- `custom/app/services/custom/scout_v2/playbook/index_builder.rb`: recebe o conjunto abrível do
  turno, não o catálogo inteiro.
- Definição única do conjunto abrível (catálogo inteiro sem ativa; só playbooks sem `when_state` com
  ativa), usada pelo índice e por `open_playbook`.
- `custom/app/services/custom/scout_v2/tools/open_playbook.rb`: rejeita nome fora do conjunto
  abrível com erro de tool; para interrupção, troca instruções (`with_instructions` sem o corpo em
  curso) e catálogo (`with_tools(replace: true)` + sempre-on + declaradas pela interrupção) e não
  grava estado; para playbook com `when_state`, mantém o comportamento do brief 04.
- `custom/app/services/custom/scout_v2/turn_runner.rb`: `open_playbook` registrada sempre que o
  conjunto abrível não é vazio; conjunto sempre-on definido num único lugar, reutilizado pela troca
  de catálogo; metadados do trace com a interrupção aberta.
- Cutover: a spec do brief 04 que afirma `open_playbook` ausente com playbook forçada por estado é
  removida e substituída pelos critérios abaixo.

## 6. Fora de escopo

- Exits e `exit_handoff` — brief 05. Este brief só define o conjunto sempre-on onde o 05 registra o
  `exit_handoff`.
- As playbooks do trio (`fora_de_prospeccao`, `duvida_comercial`, `pausa`) — brief 06. Aqui a
  verificação usa catálogo de fixture.
- Teto de aberturas de interrupção por turno: sem evidência de laço; não entra (`AGENTS.md`, sem
  guarda especulativa).
- Classificador de intenção no lugar de `open_playbook` — adiado (design §4.4).
- Qualquer alteração no v1.

## 7. Critérios de aceite (rascunho)

### US1 — Interrupção alcançável com procedimento ativo

- Com playbook ativa por estado, `open_playbook` é oferecida e o índice lista só as playbooks sem
  `when_state`.
- Sem playbook ativa, o índice lista todas e `open_playbook` aceita qualquer uma.
- Com playbook ativa, tentar abrir uma playbook com `when_state` devolve erro de tool e o turno
  continua.
- Com playbook ativa e nenhuma interrupção no catálogo, `open_playbook` não é oferecida.

### US2 — A interrupção é dona do resto do turno

- Aberta uma interrupção sobre um procedimento ativo, na iteração seguinte do mesmo `chat.ask` as
  instruções não contêm o corpo do procedimento e o catálogo não contém as tools/capabilities/exits
  dele.
- O catálogo nessa iteração contém as sempre-on e as declaradas pela interrupção, e nada mais.
- O corpo da interrupção chega como resultado de tool.
- Uma segunda interrupção aberta no mesmo turno substitui a primeira pelo mesmo mecanismo.

### US3 — Interrupção não persiste e o procedimento é retomado

- Abrir interrupção não altera `active_playbook`, `activated_at` nem `activation_reason` no estado
  da conversa.
- No turno seguinte, o roteador toma a mesma decisão que tomaria sem a interrupção: o procedimento
  em curso volta, com o ponto do funil preservado no banco.
- Interrupção aberta sem playbook ativa também não persiste: o turno seguinte começa sem ativa.
- O trace do turno registra a interrupção aberta com `activation_reason: trigger`.
- Playbook com `when_state` aberta sem ativa persiste com `activation_reason: trigger`, como no
  brief 04.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb`: conjunto abrível com e sem
  ativa.
- `custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb`, com o chat dublado e catálogo
  de fixture: interrupção sobre ativa troca instruções e catálogo e não grava estado; playbook com
  `when_state` rejeitada com ativa; playbook com `when_state` sem ativa persiste como `trigger`.
- `custom/spec/services/custom/scout_v2/turn_runner_spec.rb`: `open_playbook` presente com ativa
  quando há interrupção no catálogo, ausente quando não há; turno seguinte a uma interrupção retoma
  a ativa.
- A verificação comportamental no playground do trio fica no brief 06, que entrega as playbooks.

---

> **Nota de proveniência**: decorre da revisão final do código do brief 04 (playbook aberta pelo
> modelo fixando a conversa) e do conflito entre o design §4.4 ("`open_playbook` só quando não há
> playbook forçada por estado") e a decisão 5 do brief 06. Design revisado em 2026-09-25, §4.4
> "Interrupção por trigger". Comportamento de `with_instructions`/`with_tools(replace: true)` lido em
> `ruby_llm-1.15.0/lib/ruby_llm/chat.rb`.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
