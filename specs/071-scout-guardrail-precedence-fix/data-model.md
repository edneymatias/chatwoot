# Data Model: Routine-Request Guardrail False Positive & Persona Precedence Fix

## No persisted entities

This feature introduces no database table, column, model, or migration (FR-008). The only state
involved is existing, unmodified: `Scout#system_prompt` (the account's persona text, already
free-form and already rendered verbatim inside `<account_custom_instructions>` tags).

## Carrier: `Custom::Scout::SystemPromptsService` (prompt text fragments)

Both changes are in-place edits to existing heredoc methods in
`custom/app/services/custom/scout/system_prompts_service.rb`. No method signature, section ordering,
or public API of the service changes — `build`'s section list and order is unchanged.

### Fragment 1 — `guardrails_section`, "Reconhecimento de intenção fora de prospecção" bullet

Replaces the current line (guardrails_section, penultimate bullet, unchanged position — still after
"Fallback para humano", still before "Idioma e Estilo", matching the existing ordering assertions in
`system_prompts_service_spec.rb`):

```
- Reconhecimento de intenção fora de prospecção: Se em qualquer momento ficar claro que o contato não busca uma nova oportunidade comercial — apenas quando: já é cliente com um produto ou serviço em andamento, quer alterar ou cancelar algo que já existe (não uma nova solicitação), tem uma reclamação, ou faz uma pergunta puramente informativa sem nenhum sinal de interesse em um novo produto ou serviço — não tente resolver a questão por conta própria, mesmo que pareça simples. Utilize `handover_to_human` imediatamente. Uma nova solicitação de baixa complexidade, preventiva, recorrente ou sem um problema específico descrito continua sendo uma oportunidade comercial nova e válida — siga o funil de qualificação normalmente nesses casos. Se houver uma ferramenta externa configurada para verificar o status do contato (cliente existente, produto ou serviço em andamento) e o telefone já estiver disponível, consulte-a para reforçar a decisão — mas um sinal claro na própria fala do cliente já é suficiente para transferir, sem exigir confirmação do ERP.
```

Rule mapping: "apenas quando: já é cliente ... produto ou serviço" = FR-001 criterion 1. "quer
alterar ou cancelar algo que já existe (não uma nova solicitação)" = FR-001 criterion 2. "tem uma
reclamação" = FR-001 criterion 3. "faz uma pergunta puramente informativa sem nenhum sinal de
interesse em um novo produto ou serviço" = FR-001 criterion 4. "Uma nova solicitação de baixa
complexidade, preventiva, recorrente ou sem um problema específico descrito continua sendo uma
oportunidade comercial nova e válida — siga o funil de qualificação normalmente" = FR-002. No
medical/dental/segment term anywhere = FR-003/SC-004. External-tool-reinforcement tail sentence is
carried over unchanged except genericizing its parenthetical from "(cliente existente, tratamento em
andamento)" to "(cliente existente, produto ou serviço em andamento)" for FR-003 consistency — its
behavior (optional reinforcement, never blocking) is otherwise unchanged, matching FR-007's "reactive
mechanism unaffected" framing at the proactive-layer level too.

### Fragment 2 — `custom_instructions_section`, precedence sentence

Replaces the current sentence (still the first line inside the heredoc, still immediately followed
by the unchanged `<account_custom_instructions>` wrapper tags and `#{@scout.system_prompt}`
interpolation):

```
As instruções a seguir foram configuradas pelo administrador da conta. Siga-as, exceto quando conflitarem com o formato de resposta JSON, com a exigência de responder exclusivamente a partir do contexto fornecido, ou com as diretrizes inegociáveis de segurança e resposta descritas acima — no mínimo, Anti-alucinação, Anti-falsa-promessa e Confirmação de ação. A diretriz "Reconhecimento de intenção fora de prospecção" é a única exceção: estas instruções podem refinar ou expandir o que conta como uma nova oportunidade comercial válida especificamente nesse critério, mesmo que pareçam, à primeira vista, tocar no mesmo assunto dessa diretriz. Nenhuma outra diretriz da seção acima pode ser alterada por estas instruções.
```

Rule mapping: "Anti-alucinação, Anti-falsa-promessa e Confirmação de ação" (+ the pre-existing
"formato de resposta JSON"/"contexto fornecido" clauses) = FR-004's named non-negotiable list ("never
fabricating information" / "always JSON format" / "never unfulfillable promises" / "always confirming
successful tool actions"). "A diretriz ... é a única exceção" = FR-004's "allow ... to refine or
expand only the non-prospecting-intent guardrail". "mesmo que pareçam, à primeira vista, tocar no
mesmo assunto" = FR-005 (no need to avoid textual overlap). "Nenhuma outra diretriz ... pode ser
alterada" = FR-004's "every other guardrail bullet ... remains fixed" (stated generically — no need
to enumerate all 7 other bullet names in the prompt text itself; FR-006 (non-negotiables still win)
falls out of the same "exceto quando conflitarem ... com as diretrizes inegociáveis" clause.

## State transitions

None — this is a stateless prompt-text builder; there is no entity lifecycle to model.
