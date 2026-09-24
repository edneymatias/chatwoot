# Fase 18 — Correspondência Desfecho-Estágio no Funil

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 08 (`08-system-prompt-guardrails/spec71.md`) — `SystemPromptsService#guardrails_section`/
`#funnel_section`, os métodos alterados por esta fase. Phase 09 (`09-required-qualification-attributes/...`)
— mesmo mecanismo de contexto de funil, `build_funnel_guidelines_lines`.
**Precedido por**: `spec-preview.md` (mesma pasta) — registra as três evidências principais
(desqualificação silenciosa, qualificação sem transição, handoff prematuro por crença equivocada de
capacidade) e os cinco sintomas adjacentes de momentum conversacional (Sintomas 1-5, um já corrigido
— Sintoma 3). Este documento é a solução para os seis itens que seguem em aberto.

---

## Objetivo

Fechar seis lacunas de diretriz de prompt identificadas em teste real, todas com a mesma causa raiz
arquitetural: o `System PromptsService` (Fase 08) monta contexto rico (descrições de estágio, lista
de valores permitidos) mas não instrui o modelo a *usar* esse contexto de forma ativa e a se
comunicar de forma natural sobre o que faz. Nenhuma tool nova, nenhuma mudança de arquitetura —
apenas texto de prompt em métodos já existentes, mais uma dica cosmética de UI.

## Itens resolvidos por esta fase

1. **Desfecho vs. descrição de estágio não comparado** (evidência original + segunda evidência,
   `spec-preview.md`): o modelo não move a oportunidade mesmo quando o desfecho do turno bate
   claramente com a descrição de um estágio configurado (nem para desqualificar, nem para
   qualificar).
2. **Crença equivocada de capacidade ausente** (terceira evidência): o modelo às vezes conclui que
   falta uma ferramenta (ex: "sistema de agendamento") e transfere para humano em vez de registrar
   o dado com as tools que já tem.
3. **Múltiplas perguntas empilhadas numa resposta** (Sintoma 1).
4. **Resposta inerte, sem pergunta de avanço** (Sintoma 2).
5. **Narração de ações internas de CRM ao cliente** (Sintoma 4).
6. **Enumeração de valores permitidos como menu de múltipla escolha** (Sintoma 5).

O Sintoma 3 (insistência pós-pausa) já recebeu ajuste bounded em `guardrails_section` em
2026-08-29 — não faz parte do escopo desta fase.

## Escopo

### A. `SystemPromptsService#build_funnel_guidelines_lines` — dois bullets novos

Resolve os itens 1 e 2. Adicionados ao final da lista já existente nesse método (`custom/app/services/custom/scout/system_prompts_service.rb`):

```ruby
def build_funnel_guidelines_lines
  [
    "\nDiretrizes Operacionais de Funil:",
    '- Ao mover a oportunidade para o estágio qualificado, a transferência (handoff) para a equipe humana é realizada ' \
    'automaticamente. Não execute `handover_to_human` separadamente ao qualificar.',
    '- O estágio de desqualificação representa uma fila de revisão humana, não o fechamento do negócio. Nunca marque a oportunidade ' \
    'como perdida/ganha; se houver motivo de desqualificação, registre-o como nota interna via ferramenta apropriada.',
    '- Ao final de cada turno, compare o desfecho observável da conversa (recusa, adiamento, silêncio, confirmação, ' \
    'agendamento etc.) contra as descrições dos estágios configurados acima; se o desfecho corresponder claramente à ' \
    'descrição de algum estágio, mova a oportunidade para esse estágio agora, via `manage_opportunity`/`move_opportunity_stage` ' \
    '— não espere uma palavra-chave específica nem uma pergunta explícita do lead para agir.',
    '- Você sempre tem, através de `manage_opportunity`/`move_opportunity_stage`, tudo o que precisa para registrar qualquer ' \
    'dado de qualificação (incluindo datas e horários) na mesma chamada que move o estágio. Nunca conclua que falta uma ' \
    'ferramenta externa (ex: sistema de agendamento/calendário) para isso — se os critérios de um estágio já podem ser ' \
    'satisfeitos com os dados que o lead forneceu, registre-os agora em vez de transferir para humano alegando limitação técnica.'
  ]
end
```

### B. `SystemPromptsService#guardrails_section` — um bullet novo, dois bullets estendidos

Resolve os itens 3, 4, 5 e 6. Bullet novo (**Ritmo e condução da conversa**) inserido imediatamente
antes de "Respeito ao ritmo do lead" — agrupa toda diretriz de ritmo/condução num só lugar:

```ruby
def guardrails_section
  <<~SECTION.strip
    [Diretrizes de Segurança e Resposta]
    - Anti-alucinação: Nunca invente informações e não utilize conhecimento prévio de treinamento para assumir dados sobre preços, planos, produtos, regras ou políticas da empresa. Responda estritamente com base no contexto fornecido e nas ferramentas disponíveis.
    - Anti-falsa-promessa: Não prometa trabalhos ou ações futuras que devam acontecer após esta resposta (como "vou verificar e te aviso", "entraremos em contato amanhã", "enviaremos um email depois" ou "vou registrar seu pedido"). Realize a ação imediatamente caso haja uma ferramenta disponível para isso agora ou, caso não seja possível resolver no momento, utilize a ferramenta de transferência para atendente humano.
    - Confirmação de ação: Sempre que executar com sucesso uma ferramenta de registro ou atualização (ex: `manage_opportunity`, `update_contact`), confirme brevemente ao cliente o que foi registrado antes de prosseguir com novas perguntas. Nunca execute uma ação e siga direto para a próxima pergunta sem informar ao cliente o que aconteceu. Confirme sempre em linguagem natural e voltada ao cliente (ex: "Perfeito, já anotei aqui!"), nunca expondo identificadores internos (ex: "oportunidade #36"), nomes técnicos de campos do CRM (ex: "Interesse", "Origem") ou linguagem de log de sistema (ex: "atualizei o registro com...").
    - Intenção Comercial: Ao identificar interesse de compra ou necessidade comercial em qualquer momento da conversa, utilize a ferramenta `manage_opportunity` para criar ou atualizar a oportunidade.
    - Esclarecimento: Quando houver ambiguidade ou dados faltantes, faça perguntas curtas e diretas para esclarecer em vez de assumir premissas. Quando o dado pedido corresponder a um campo de lista de valores predefinidos, pergunte de forma aberta e natural, sem recitar as opções configuradas como se fosse um menu de múltipla escolha — use a lista apenas para mapear internamente a resposta livre do lead ao valor correto ao chamar as ferramentas.
    - Ritmo e condução da conversa: Faça no máximo uma pergunta por resposta — se precisar de várias informações, peça uma de cada vez, em turnos separados. Ao apresentar uma informação relevante (descrição de produto/serviço, resposta a uma dúvida), feche sempre com essa única pergunta ou um próximo passo que mantenha a qualificação avançando, a menos que o lead tenha sinalizado pausa ou encerramento (ver diretriz abaixo).
    - Respeito ao ritmo do lead: Quando o lead sinalizar que quer pausar ou encerrar a conversa por ora (ex: "vou ver e te aviso", "depois eu volto", "obrigado"), não reintroduza perguntas de qualificação pendentes nesse turno. Apenas confirme educadamente, deixe a porta aberta para o retorno e encerre o turno.
    - Fallback para humano: Se você não souber a resposta, se o contexto for insuficiente ou se o lead solicitar atendimento humano, utilize a ferramenta `handover_to_human`.
    - Idioma e Estilo: Detecte o idioma do lead e responda sempre no mesmo idioma, mantendo um tom natural, cordial, profissional e conciso.
  SECTION
end
```

### C. UI — dica cosmética no campo de descrição de estágio

Puramente orientativa, sem lógica nova. Nova chave i18n `PIPELINE_STAGES_MGMT.FORM.DESC_HINT`
(`en/opportunities.json` e `pt_BR/opportunities.json`):

- EN: `"This description is also read by the AI to decide when to move a conversation into this stage — write it objectively (e.g. 'move here when the lead declines to schedule')."`
- PT-BR: `"Esta descrição também é usada pela IA para decidir quando mover uma conversa para este estágio — escreva de forma objetiva (ex: 'mover aqui quando o lead recusar agendar')."`

Renderizado como um parágrafo pequeno (`text-xs text-n-slate-11`), sempre visível (não depende do
campo estar vazio), logo abaixo do label "Descrição" em:

- `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue`
- `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`

Não usa a extensão `@tiptap/extension-placeholder` (não instalada) nem introduz placeholder
dinâmico no editor rico — um hint estático é mais robusto porque continua visível mesmo quando o
operador já escreveu uma descrição não-acionável (um placeholder-quando-vazio desapareceria nesse
caso, que é exatamente o caso que mais precisa da dica).

## Fora de escopo desta fase

- Sanitização de HTML de `stage.description` antes de ir para o prompt — item de limpeza registrado
  no `spec-preview.md`, mas sem evidência de causar problema; adiado.
- Qualquer regra determinística/hardcoded de "se o lead disser X, mover para estágio Y" — todas as
  diretrizes acima são genéricas, dependem só da descrição que o operador já escreve, funcionam com
  qualquer configuração de funil.
- Validação obrigatória ou enforcement do formato "acionável" na descrição do estágio — a dica de UI
  é só orientativa, o campo continua livre.
- Qualquer mudança no pipeline de auditoria de resposta (Fase 12) — ver `spec-preview.md`, Fora de
  escopo.
- Sintoma 3 (insistência pós-pausa) — já corrigido em 2026-08-29, guardrail já presente no texto
  acima ("Respeito ao ritmo do lead").

## Testes

### Specs automatizados (TDD, `custom/spec/services/custom/scout/system_prompts_service_spec.rb`)

Seguindo o padrão já existente no arquivo (`expect(prompt).to include(...)`):

- `describe 'funnel_section'`: dois novos `it` confirmando a presença dos dois bullets novos de
  `build_funnel_guidelines_lines` (comparação de desfecho; capacidade de ferramentas).
- Bullet "Confirmação de ação": novo `it` (ou extensão do existente) confirmando a presença da
  cláusula de comunicação natural / não exposição de identificadores internos.
- Bullet "Esclarecimento": novo `it` (ou extensão do existente) confirmando a cláusula de
  perguntas abertas para campos de lista.
- Novo `it` confirmando a presença do bullet "Ritmo e condução da conversa" com as duas regras
  (uma pergunta por vez; sempre fechar com avanço).

### Verificação comportamental (não coberta por specs unitários — specs só provam que o texto está
no prompt, não que o modelo obedece)

Depois do ajuste, replay das três conversas reais que motivaram esta fase via
`Custom::Scout::PlaygroundRunner` (`rails runner`, sem precisar do widget), reconstruindo a mesma
sequência de mensagens de cada uma:

- Conversation display_id 19 (Oportunidade #10, recusa de agendamento) — verificar se a oportunidade
  agora move para o estágio desqualificado.
- Conversation display_id 18/20 (Oportunidades #9/#11, confirmação de agendamento sem transição) —
  verificar se `move_opportunity_stage` é chamado antes da resposta final.
- Conversation display_id 46 (Oportunidade #36, handoff prematuro) — verificar se o modelo agora
  chama `manage_opportunity`/`move_opportunity_stage` com o horário escolhido em vez de transferir.

Não é garantia (comportamento de LLM é estocástico), mas é um smoke test rápido e repetível antes da
validação final do operador no widget real.

## Critérios de aceite

- Uma conversa onde o lead recusa/adia a ação principal proposta resulta na oportunidade avaliada
  contra as descrições de estágio configuradas, incluindo o estágio desqualificado quando a
  descrição do operador cobrir esse cenário.
- Uma conversa onde o lead confirma a ação principal proposta e todos os campos obrigatórios já
  estão preenchidos (incluindo campos de data fornecidos pelo lead) resulta em
  `manage_opportunity`/`move_opportunity_stage` sendo chamado com esses dados, para o estágio
  qualificado, antes ou junto da resposta que confirma o desfecho ao cliente — nunca depois, nunca
  substituído por handoff alegando falta de ferramenta.
- Nenhuma resposta do Scout contém mais de uma pergunta.
- Nenhuma resposta que apresenta informação relevante para qualificação termina sem uma pergunta ou
  próximo passo, exceto quando o lead sinalizou pausa/encerramento.
- Nenhuma resposta expõe ID de oportunidade, nome técnico de campo/atributo, ou linguagem de log de
  sistema ao confirmar uma ação.
- Nenhuma resposta recita a lista de valores permitidos de um campo como menu de múltipla escolha.
- Contas sem descrição configurada para nenhum estágio mantêm o comportamento atual (sem
  regressão).
- Nenhuma regra de negócio (palavra-chave, frase específica) fica hardcoded no prompt ou no código.
- O hint de UI aparece nos dois formulários (Add/Edit), em en e pt_BR, sem alterar o comportamento
  de salvamento do campo.
