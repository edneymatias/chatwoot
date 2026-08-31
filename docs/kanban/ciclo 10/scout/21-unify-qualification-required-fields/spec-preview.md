# Fase 21 — Unificar Campos Obrigatórios de Qualificação (Preview)

**Status**: Preview — problema real identificado durante configuração manual do funil de teste;
especificação completa e implementação adiadas para o momento oportuno, a critério do operador.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 09 (`09-required-qualification-attributes/...`) — introduziu `ScoutRequiredField`
e `check_global_qualification_requirements`. Depende também do recurso core, pré-existente,
`PipelineStageRequiredField` (gestão de estágios do Kanban, anterior ao Scout).

---

## Contexto: dois mecanismos de "campo obrigatório", duas telas diferentes

Descoberto ao configurar campos obrigatórios reais para os estágios "Agendado" e "Em negociação"
do funil de teste (conta 1, Scout "Vitória"). Existem hoje **dois sistemas de requisito de campo
que se sobrepõem conceitualmente**, mas vivem em lugares diferentes:

1. **`ScoutRequiredField`** (Fase 09) — campos "globais" de qualificação do Scout, configurados na
   própria aba **"Funil e Qualificação" do cadastro do Scout** (`ScoutFunnelTab.vue`). Checados só
   no momento de mover para `qualified_stage_id`, via
   `OpportunityStageTransitionService#check_global_qualification_requirements`.
2. **`PipelineStageRequiredField`** (recurso core, anterior ao Scout) — campos obrigatórios **por
   estágio**, configurados na tela de **gestão de estágios do Kanban** (`Settings → Funil → editar
   estágio`), usada também por humanos movendo cards manualmente. Checado para qualquer avanço de
   estágio (não só o qualificado), via validação de model
   (`Opportunity#validate_forward_stage_move_requirements`) — roda incondicionalmente para o Scout,
   sem nenhum toggle (confirmado: nada no caminho do Scout seta `Current.executed_by`, a única
   exceção que pula essa validação).

Hoje, no estágio "Agendado" (qualificado) desta conta, os dois mecanismos coexistem: `Interesse` e
`Origem da oportunidade` vêm do `ScoutRequiredField` (aba do Scout), enquanto `Data do Agendamento`
foi configurado via `PipelineStageRequiredField` (tela de estágios) — porque é onde esse tipo de
requisito sempre viveu, e não há como configurá-lo pela aba do Scout.

## Evidência do problema: redundância já visível no próprio prompt

`SystemPromptsService#funnel_section` (Fase 08) já mostra os dois separadamente pro modelo, para o
mesmo estágio:

```
- ID: 4 | Nome: Agendado (Estágio Qualificado)
  Campos obrigatórios para avançar para este estágio:
    - Data do agendamento (...)          ← vem de PipelineStageRequiredField

Requisitos Globais de Qualificação (obrigatórios para mover para o estágio de qualificação):
    - Origem da oportunidade (...)       ← vem de ScoutRequiredField
    - Interesse (...)                    ← vem de ScoutRequiredField
```

Duas seções diferentes no prompt, dois models diferentes, duas telas de configuração diferentes,
para descrever exatamente a mesma coisa do ponto de vista de quem configura: "o que precisa estar
preenchido pra este card chegar aqui". Quem olha só a aba do Scout ("Funil e Qualificação") não vê
os requisitos configurados na tela de estágios, e vice-versa.

## Ideia para a fase (a confirmar na especificação completa)

Em vez de manter `ScoutRequiredField` como uma configuração paralela, os "campos obrigatórios de
qualificação" do Scout passam a ser **inferidos diretamente do que já está configurado no estágio
qualificado** (`@scout.qualified_stage.required_custom_attribute_definitions` +
`requires_deal_value`, via `PipelineStageRequiredField`/core) — não uma config extra e separada.
Elimina a duplicação de tela, de model e a seção redundante no prompt.

## Escopo preliminar (não detalhado — fica para a especificação completa)

- Substituir a leitura de `@scout.required_custom_attribute_definitions` (em
  `check_global_qualification_requirements` e em `SystemPromptsService#build_global_reqs_lines`)
  por `@scout.qualified_stage&.required_custom_attribute_definitions` (+ `requires_deal_value?`).
- Remover (ou aposentar) `ScoutRequiredField`, seu controller e a seção correspondente em
  `ScoutFunnelTab.vue` — a aba do Scout passaria a só **exibir/linkar** o que está configurado na
  tela de estágios, não duplicar a configuração.
- Migração de dados para contas que já têm `ScoutRequiredField` configurado mas nenhum
  `PipelineStageRequiredField` equivalente no estágio qualificado — decidir se migra automaticamente
  ou exige reconfiguração manual.
- Revisitar se faz sentido a aba do Scout mostrar, de forma somente-leitura, os requisitos de
  **todos** os estágios do funil (não só o qualificado) — hoje isso já vai pro prompt via
  `format_stage`, mas não é visível em nenhuma tela dedicada ao Scout.

## Fora de escopo (a confirmar)

- Qualquer mudança no comportamento de `PipelineStageRequiredField` para uso fora do Scout (Kanban
  manual) — esse recurso é core e antecede o Scout, esta fase só muda quem/onde ele é configurado
  para fins de qualificação do Scout.

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Configurar um campo obrigatório para o estágio qualificado passa a acontecer em um único lugar
  (tela de estágios do Kanban) — não mais duas telas.
- O prompt do Scout (`funnel_section`) deixa de ter duas seções separadas ("Campos obrigatórios
  para avançar para este estágio" e "Requisitos Globais de Qualificação") repetindo a mesma
  informação para o estágio qualificado.
- Nenhuma regressão no gate de qualificação — os campos hoje exigidos (Interesse, Origem, e os que
  foram adicionados nesta sessão: Data do Agendamento) continuam sendo exigidos depois da unificação.

---

> **Nota**: Preview criado durante a configuração manual dos campos obrigatórios reais dos estágios
> "Agendado" e "Em negociação" (mesma sessão da Fase 18/20) — a duplicação de mecanismo foi notada
> na hora, não é uma reformulação especulativa. Tratamento adiado para o momento oportuno, a
> critério do operador — ver `spec60.md` §11.
