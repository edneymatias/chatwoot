# Fase 06 — Playbooks do Primeiro Corte (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §6 (Fase 1, tabela das seis playbooks), §4.3, §4.4
**Depends on**: Brief 05 (exits e Escalation) e Brief 04 (índice + `open_playbook`). A playbook
`qualificacao` já foi entregue no Brief 03 — este brief entrega as outras cinco e acrescenta os
exits à `qualificacao`.

---

## 1. Problema

As regras situacionais do v1 estão todas no prompt global, sempre ligadas. Mapeamento medido
(design §1 e §6):

| Regra hoje global | Linha | Quando de fato importa |
|---|---|---|
| Identidade do contato | `system_prompts_service.rb:74` + `:105-115` + `:118-131` | só quando o nome é placeholder ou falta telefone |
| Respeito ao ritmo do lead | `:76` | só quando o lead sinalizou pausa |
| Intenção fora de prospecção | `:78` | só quando há sinal de cliente existente/reclamação |
| Instrução de uso da base | `:159-162` (+ contra-bullet em `funnel_section_builder.rb:46-49`) | só quando o lead faz pergunta de produto/preço |
| Diretrizes de funil | `funnel_section_builder.rb:31-51`, ~2.151 caracteres | só durante qualificação |

Cada uma dessas regras foi adicionada por uma conversa simulada específica — é o ciclo de churn
(24 commits no módulo) que motivou o épico.

## 2. Contexto técnico

- `system_prompts_service.rb:105-115` (`identity_warning`) e `:118-131`
  (`phone_request_warning`) — avisos just-in-time que já são condicionais, mas vivem no mesmo
  montador monolítico e não trazem tools nem desfecho consigo.
- `system_prompts/funnel_section_builder.rb:31-51` — as diretrizes de funil, e em `:46-49` o
  contra-bullet que pede ao modelo para não inventar perguntas por causa da base de conhecimento.
- `system_prompts_service.rb:76,78` — pausa e intenção fora de prospecção, como bullets globais.
- Predicados de estado disponíveis (brief 01/02): identidade incompleta, oportunidade aberta,
  campos obrigatórios pendentes, estágio da oportunidade, telefone do contato.
- **Limite conhecido**: `when_state` só enxerga o que o banco sabe. "Quero remarcar", "já sou
  cliente reclamando", "quanto custa", "quero falar com gente" não têm assinatura de estado — daí
  três das seis playbooks nascerem só com `trigger` (design §4.4).

## 3. Precedente

`AssistantMigration::InstructionClassifier` do Captain V2 decompõe um prompt monolítico V1 em
`description` + `response_guidelines` + `guardrails` + **scenario candidates**, com regra de corte
explícita (`lib/captain/prompts/instruction_classifier.liquid:1-13,71-80`): *"Create a scenario
candidate only for a distinct multi-step workflow… Do not create scenarios for tone, formatting,
generic escalation, a simple handoff trigger, or a one-step factual answer."* É exatamente o
critério que separa, aqui, o que virou playbook do que virou `Safety`/`Communication`/`Escalation`
no brief 04 — e confirma que a decomposição feita na tabela do design §6 segue a mesma régua.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | Seis playbooks no primeiro corte, com a distribuição de `tools`/`requires`/`exits` fixada na tabela do design §6 | Cada uma tem origem rastreável numa regra global do v1 (coluna "Origem no v1"), exceto `agendamento`, que é capacidade nova |
| 2 | Coluna `tools` vazia é **literal**: naquela playbook o modelo não tem nenhuma tool de mutação | É o ponto do épico — num turno de dúvida ou de pausa, dar a chave do CRM ao modelo é superfície de efeito colateral sem contrapartida (design decisão 12) |
| 3 | `fora_de_prospeccao` tem `priority` máxima e ativação **só por trigger** — inversão assumida conscientemente | `priority` só arbitra entre playbooks que já casaram por estado; não acelera a que depende do modelo. Mitigação: trigger com exclusão explícita e observação de `activation_reason` em produção. Correção, se necessária: predicados parciais, não afrouxar a precedência (design §4.4 e §8) |
| 4 | `agendamento` entra **com `requires` insatisfeito**, exercitando a degradação | O caminho de degradação precisa ser provado antes de existir capability; o passo degrada em texto com pendência visível, não estoura (design §6, Fase 1) |
| 5 | `duvida_comercial` encerra **voltando à playbook anterior**, não em exit terminal | Tirar dúvida é interrupção, não desfecho: o lead volta ao procedimento onde estava |
| 6 | `CreatePrivateNote` **não** é declarada por nenhuma das seis | Os dois usos reais viraram efeito de Ruby (o exit de escalação escreve a nota de transferência; o `ContactNotesService` escreve o resumo de fim de conversa). Volta numa linha de frontmatter se aparecer necessidade concreta (design §4.8) |

## 5. Escopo preliminar

- `custom/playbooks/fora_de_prospeccao.md` — `priority` máxima, só trigger, sem tools, exit
  `handoff`. Origem: `system_prompts_service.rb:78`.
- `custom/playbooks/identificacao.md` — `when_state: [contact_identity_incomplete]`,
  `tools: [update_contact]`, exit de transição → `qualificacao`. Origem: `:105-115` + `:118-131`.
- `custom/playbooks/duvida_comercial.md` — só trigger, sem tools, exit → playbook anterior. Origem:
  `:159-162`.
- `custom/playbooks/pausa.md` — só trigger, sem tools, exit terminal. Origem: `:76`.
- `custom/playbooks/agendamento.md` — `when_state: [opportunity_in_stage(qualificado),
  contact_has_phone]`, `requires: [scheduling, customer_registry]`, `needs:
  [politica_reagendamento]`, exits `agendado` · `sem_horario` · `handoff`.
- `custom/playbooks/qualificacao.md` — acrescentar `exits: qualificado · desqualificado · handoff`
  (o corpo do brief 03 termina respondendo; agora termina em desfecho).
- Predicados novos: `contact_identity_incomplete`, `opportunity_in_stage`, `contact_has_phone`.
- Degradação por `requires` insatisfeito: renderização da pendência no corpo + `unsatisfied_flags`
  no estado da conversa e no trace.

## 6. Fora de escopo

- `CapabilityRegistry` e adapters reais — brief 07. Aqui `scheduling`/`customer_registry` existem
  apenas como **nomes no catálogo declarado**, insatisfeitos por construção.
- Packs de playbook por vertical (`playbook_pack: odontologia | vendas_generico`): design §6.2,
  gatilho é o segundo vertical com funil estruturalmente diferente.
- Materialização das playbooks em banco e UI de enable/disable: design §6.3.
- Remoção do texto correspondente em `system_prompts_service.rb`/`funnel_section_builder.rb` do v1:
  o v1 segue intocado até a depreciação (brief 10).

## 7. Critérios de aceite (rascunho)

### US1 — `identificacao` e `qualificacao` fecham o caminho state-driven

- Contato com identidade incompleta ativa `identificacao` por estado; o Scout coleta nome/telefone
  usando `update_contact` e transiciona para `qualificacao` por exit, na mesma conversa.
- `qualificacao` termina em `qualificado`, `desqualificado` ou `handoff`, com os campos
  obrigatórios validados antes da escrita.
- Durante `identificacao`, o modelo não tem `manage_opportunity`; durante `qualificacao`, não tem
  `update_contact` — cada playbook só oferece o que declara.

### US2 — O trio por trigger cobre o resíduo de intenção

- Sinal de cliente existente/reclamação abre `fora_de_prospeccao` e termina em `handoff`, sem
  nenhuma tool de mutação disponível no caminho.
- Pergunta de produto/preço abre `duvida_comercial`, que consulta a base de conhecimento e **volta
  para a playbook anterior**, sem perder o ponto do funil.
- Sinal de pausa do lead abre `pausa`, que encerra sem insistir e sem tool de mutação.
- Os três registram `activation_reason: trigger`.
- Nenhum dos três é ativado por `when_state` em nenhum estado do banco.

### US3 — `agendamento` degrada com pendência visível

- Com `scheduling`/`customer_registry` insatisfeitas, `agendamento` ativa normalmente por estado e
  o passo dependente é apresentado ao modelo como pendência, sem quebrar o turno.
- O Scout não inventa horários nem confirma agendamento que não aconteceu; o desfecho possível é
  `handoff`.
- A pendência aparece em `unsatisfied_flags` no estado da conversa e no trace do turno.
- Satisfeitas as capabilities (brief 07), a mesma playbook passa a executar o caminho completo sem
  alteração no arquivo.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/router_spec.rb` (extensão): estado → playbook para
  `identificacao`, `qualificacao` e `agendamento`; e ausência de ativação por estado para o trio de
  trigger, em qualquer estado.
- `custom/spec/services/custom/scout_v2/predicates/*_spec.rb`: os três predicados novos.
- Flow test por playbook (capabilities dubladas): conversa multi-turno verificando exits e
  transições — incluindo `duvida_comercial` retornando à playbook anterior e `agendamento`
  degradando.
- Verificação no playground das seis, com `activation_reason` conferido em cada uma.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §6 (tabela da Fase 1),
> §4.3 e §4.4; a coluna "Origem no v1" de cada playbook aponta a linha exata do prompt monolítico
> que ela substitui.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
