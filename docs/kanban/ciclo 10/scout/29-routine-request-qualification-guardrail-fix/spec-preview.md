# Fase 29 — Falso Positivo do Guardrail de Intenção Fora de Prospecção e Precedência da Persona (Preview)

**Status**: Preview — regressão de comportamento identificada em simulação real (display_id 117 e
118, conta 1, Scout "Vitória"); especificação completa e implementação adiadas para o momento
oportuno, a critério do operador.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on / corrige**: Fase 23 (`23-non-sales-intent-immediate-handoff/spec86.md`) — introduziu
o guardrail cujo texto está causando o falso positivo tratado aqui. Fase 08
(`08-system-prompt-guardrails/spec71.md`) — introduziu `custom_instructions_section` e a cláusula de
precedência que subordina a persona da conta às guardrails fixas.

---

## Contexto: consulta de rotina tratada como "fora de prospecção"

Descoberto ao simular, em duas conversas de teste (conta 1, Scout "Vitória"), um lead que pede
"consulta de rotina" logo na primeira resposta de triagem.

- **Conversa display_id 117** ✅: lead diz "quero fazer uma avaliação" e, na pergunta seguinte,
  qualifica como "rotina". O Scout segue o funil normalmente — pergunta há quanto tempo foi à última
  visita, confirma data, qualifica e transfere corretamente pelo mecanismo de qualificação
  (`move_opportunity_stage` ao estágio qualificado).
- **Conversa display_id 118** ❌: lead diz diretamente "apenas consulta de rotina" em resposta a "Do
  que você está precisando hoje?". O Scout chama `handover_to_human` imediatamente, sem qualificar,
  com o motivo textual (livre, gerado pelo próprio modelo): *"Lead solicitou apenas consulta de
  rotina; precisa de atendimento humano para sequência de agendamento/rotina."*

O único diferencial observável entre as duas conversas é a forma como o lead verbalizou a mesma
intenção (uma pedindo "avaliação" e detalhando depois, a outra indo direto ao ponto com "consulta de
rotina"). Isso indica que o modelo está classificando "consulta/demanda de rotina, sem problema
específico" como o padrão "dúvida rápida não relacionada a prospecção" — um falso positivo do
guardrail da Fase 23, não uma falha genérica de qualificação (a Fase 18, que trata desfecho→estágio,
e a Fase 09, que trata campos obrigatórios, continuam funcionando normalmente, como prova a conv 117).

## Evidência do problema

### 1. O guardrail da Fase 23 (`custom/app/services/custom/scout/system_prompts_service.rb:78`)

```
- Reconhecimento de intenção fora de prospecção: Se em qualquer momento ficar claro que o contato
  não busca uma nova avaliação/tratamento — ex.: afirma já ser cliente, menciona tratamento em
  andamento, quer reagendar/cancelar, tem uma reclamação, ou responde a uma pergunta de triagem
  indicando ser "só uma dúvida rápida" não relacionada a agendar avaliação — não tente resolver a
  questão por conta própria [...]. Utilize `handover_to_human` imediatamente.
```

O exemplo "só uma dúvida rápida não relacionada a agendar avaliação" é impreciso o suficiente para o
modelo confundir "demanda de baixa complexidade / preventiva / recorrente, sem queixa específica" com
"não é uma nova prospecção". Uma consulta de rotina **é** uma nova prospecção (a pessoa não tem
compromisso agendado, não é atendimento de suporte a algo já vendido) — só não tem uma dor/motivo
detalhado por trás, o que é normal em serviços preventivos/recorrentes de qualquer segmento (não
exclusivo de clínicas).

### 2. Tentativa de correção via persona já foi feita e não bastou

Timeline confirmada em produção (`Scout#updated_at` vs. `Message#created_at`):

| Evento | Timestamp |
|---|---|
| Operador edita a persona do Scout, adicionando: *"Consultas de rotina também é uma oportunidade para novos negócios, siga o fluxo de qualificação normalmente."* | 22:59:11 |
| Resposta problemática da conv 118 (handoff imediato, ignorando a instrução acima) | 22:59:29 |

A instrução personalizada já estava ativa 18 segundos antes da resposta que a contradiz. A causa não
é ausência de instrução — é a hierarquia do prompt.

### 3. Por que a persona não pode vencer essa guardrail hoje

`custom_instructions_section` (`system_prompts_service.rb:163-173`), que injeta `Scout#persona`
(alias `system_prompt`), contém esta cláusula:

> *"As instruções a seguir foram configuradas pelo administrador da conta. Siga-as **apenas quando
> não conflitarem** com o formato de resposta JSON ou com a exigência de responder exclusivamente a
> partir do contexto fornecido e regras de segurança."*

O guardrail da Fase 23 vive dentro do bloco `[Diretrizes de Segurança e Resposta]` — ou seja, é
tratado textualmente como regra de segurança inegociável, não como heurística de roteamento
comercial refinável. Isso significa que **nenhuma instrução de persona pode sobrepor esse guardrail
específico**, por design do prompt, independente do que o operador escrever — o problema não é de
conteúdo da persona, é estrutural.

### 4. O core do prompt não está preso a odontologia/clínicas

Verificado: `identity_section`, `guardrails_section`, `funnel_section`, `response_format_section` —
nenhum menciona odontologia/clínica/avaliação dentária hardcoded no código-fonte. Os termos
"avaliação/tratamento" no guardrail da Fase 23 são genéricos o bastante para outros domínios
(imobiliária, serviços profissionais, etc.), mas a heurística por trás ("dúvida rápida" ≈ "fora de
prospecção") é o que gera o falso positivo — não um termo de domínio específico. Confirma-se que a
correção correta é ajustar a heurística genérica em si, não inserir vocabulário de nicho (ex.: não
adicionar "consulta"/"avaliação odontológica" ao guardrail, o que amarraria o Scout a um segmento).

## Decisões de desenho (a confirmar na especificação completa)

1. **Reformular o guardrail da Fase 23**, mantendo-o agnóstico de domínio: substituir o exemplo
   ambíguo ("dúvida rápida... não relacionada a agendar avaliação") por critérios objetivamente fora
   de funil — contato já é cliente com produto/serviço em andamento, quer alterar/cancelar algo
   **já existente** (não uma nova solicitação), tem reclamação, ou pergunta puramente informativa sem
   qualquer sinal de interesse em novo produto/serviço. Adicionar frase explícita: uma nova
   solicitação de baixa complexidade, preventiva, recorrente ou "sem problema específico" continua
   sendo uma nova oportunidade comercial válida e segue o funil de qualificação normalmente.
2. **Corrigir a hierarquia de precedência entre persona e guardrails**: distinguir, dentro do prompt,
   quais guardrails são realmente inegociáveis (anti-alucinação, formato JSON de saída,
   anti-falsa-promessa, confirmação de ação) das heurísticas de classificação de intenção comercial
   (como a da Fase 23), que devem ser refináveis pelas instruções personalizadas da conta.
   `custom_instructions_section` deixa de tratar toda a seção de guardrails como bloco monolítico de
   "regra de segurança" para efeito de precedência.
3. **Mecanismo reativo da Fase 12 (Response Auditor / `ActionClassifierService`,
   `out_of_scope_commercial_request`) permanece intocado** — mesmo princípio de camada dupla já usado
   nas Fases 12/23: guardrail proativo reduz a frequência de acionamento do auditor reativo, não o
   substitui.

## Escopo preliminar (não detalhado — fica para a especificação completa)

- Reescrita do bullet "Reconhecimento de intenção fora de prospecção" em
  `Custom::Scout::SystemPromptsService#guardrails_section`
  (`custom/app/services/custom/scout/system_prompts_service.rb`).
- Ajuste de `custom_instructions_section` (mesmo arquivo) para explicitar que instruções
  personalizadas da conta podem refinar/expandir critérios de intenção comercial válida, mesmo que
  pareçam à primeira vista tocar em terreno coberto por um guardrail de roteamento (deixando claro
  quais guardrails continuam realmente inegociáveis).
- Revisitar se algum outro guardrail da seção (ex.: "Esclarecimento", "Ritmo e condução da conversa")
  tem a mesma ambiguidade estrutural ou se o problema é isolado ao bullet da Fase 23.

## Fora de escopo

- Qualquer menção a termos de domínio específico (odontologia, "avaliação", "consulta") em código do
  guardrail genérico — a correção é de heurística, não de vocabulário de nicho. Personas por conta
  continuam livres para usar a terminologia do próprio negócio.
- Alterações no `ActionClassifierService`/Response Auditor (Fase 12) — mecanismo reativo permanece
  como rede de segurança complementar, sem mudança.
- Qualquer gatilho mecânico/determinístico de handoff por status de ERP — decisão já tomada e mantida
  na Fase 23 (a leitura de intenção continua vindo do julgamento do modelo sobre a fala do cliente).
- Novas ferramentas nativas, models ou migrations — escopo previsto como alteração de texto de prompt
  e de sua estrutura de precedência, análogo ao artefato único da Fase 23.

## Testes (rascunho)

- `custom/spec/services/custom/scout/system_prompts_service_spec.rb`: atualizar o `it` da Fase 23
  para o novo texto do guardrail; novo `it` cobrindo a precedência ajustada de
  `custom_instructions_section`.
- Verificação comportamental via `Custom::Scout::PlaygroundRunner` (mesmo padrão das fases
  anteriores): replay da conv 118 (lead responde "apenas consulta de rotina" na primeira pergunta de
  triagem) — resposta esperada passa a qualificar, não a transferir. Replay da conv 117 como
  regressão (deve continuar funcionando). Replay de um caso genuinamente fora de funil (cliente
  existente com tratamento em andamento, pedido de reagendamento/cancelamento, reclamação) — deve
  continuar transferindo imediatamente, sem regressão da Fase 23.

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Um lead que solicita uma nova consulta/avaliação/demanda de rotina — recorrente, preventiva ou sem
  problema específico declarado — é qualificado normalmente pelo funil, sem handoff prematuro, em
  qualquer segmento de negócio (não só odontologia).
- Um contato que indica claramente não estar buscando prospecção (cliente existente com
  tratamento/produto em andamento, reagendamento/cancelamento de algo já existente, reclamação)
  continua recebendo handoff imediato — nenhuma regressão da Fase 23.
- Instruções personalizadas da conta (persona) que reforcem ou refinem o que conta como intenção
  comercial válida passam a poder efetivamente mudar o comportamento do Scout nesse eixo, sem
  precisar contradizer um guardrail rotulado como regra de segurança inegociável.
- O guardrail permanece livre de vocabulário de nicho/domínio específico.

---

> **Nota**: Preview criado a partir de simulação real de teste (conversas display_id 117 e 118,
> conta 1, Scout "Vitória") durante validação do fluxo de qualificação — o problema foi reproduzido
> e diagnosticado na causa raiz (falso positivo do guardrail da Fase 23 + hierarquia de precedência
> da Fase 08), não é uma reformulação especulativa. Tratamento adiado para o momento oportuno, a
> critério do operador — ver `spec60.md` §11. Próxima entrega via speckit, mesmo fluxo das fases 26 e
> 23.
