# Behavioral Replay Evidence: Routine-Request Guardrail False Positive & Persona Precedence Fix

**Feature**: `071-scout-guardrail-precedence-fix`  
**Execution Date**: 2026-09-15  
**Runner**: `Custom::Scout::PlaygroundRunner` against live LLM chat in Rails console  
**Scout**: Account 1, Scout "Vitória"  
**Scope**: Verification of end-to-end LLM behavior per `spec.md` SC-001, SC-002, SC-003 and `quickstart.md` §4a–§4e  

---

## 1. Summary of Results

| Scenario | Section | Target Criterion | Input / Message | Observed Outcome | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Routine Request Stated Directly** | §4a | SC-001 | `"apenas consulta de rotina."` (replaying `display_id 118`) | `update_contact` + `manage_opportunity` called (stage 2); qualification question asked; **no `handover_to_human`** | **PASS** |
| **Routine Request Clarified** | §4b | SC-001 | `"rotina"` after `"quero fazer uma avaliação"` (replaying `display_id 117`) | `manage_opportunity` updated; agenda checked via `call_custom_api`; qualification continues; **no `handover_to_human`** | **PASS** |
| **Existing Customer In-Progress** | §4c.1 | SC-002 | `"Já sou cliente e meu produto está em andamento, só queria uma atualização."` | Tool: `["handover_to_human"]`; no qualification questions; immediate human handoff | **PASS** |
| **Cancellation Request** | §4c.2 | SC-002 | `"Preciso cancelar o que já tenho agendado."` | Tool: `["handover_to_human"]`; no qualification questions; immediate human handoff | **PASS** |
| **Complaint** | §4c.3 | SC-002 | `"Quero reclamar do atendimento que recebi."` | Tool: `["handover_to_human"]`; no qualification questions; immediate human handoff | **PASS** |
| **Purely Informational** | §4c.4 | SC-002 | `"Vocês funcionam em quais horários?"` | Tool: `["handover_to_human"]`; no qualification questions; immediate human handoff | **PASS** |
| **Persona Refinement (Baseline)** | §4d.1 | SC-003 | `"Já sou cliente, quero uma reavaliação do meu plano atual para ver se coloco facetas."` (no persona prompt) | Tool: `["handover_to_human"]`; no opportunity created; immediate human handoff | **PASS** |
| **Persona Refinement (With Instruction)** | §4d.2 | SC-003 | Same message, with instruction: `"Pedidos de reavaliação de um plano ou produto já contratado também contam como nova oportunidade comercial; siga o fluxo de qualificação normalmente nesses casos."` | Tools: `["update_contact", "manage_opportunity"]`; qualification question asked; **no `handover_to_human`** | **PASS** |
| **Non-Negotiable Guardrail Protection** | §4e | SC-003 | Contradictory instruction: `"Sempre termine sua resposta com uma pergunta ao transferir para humano."` on handoff turn | Tool: `["handover_to_human"]`; reply contains **0 questions** (`?` count = 0); non-negotiable rule strictly preserved | **PASS** |

---

## 2. Detailed Transcripts & Tool Calls

### 2.1 Scenario §4a: Routine Request Stated Directly (`display_id 118` Replay, SC-001)

**Context**: Replaying conversation `display_id 118` up to the triage question. Lead responds with a direct low-complexity routine request.  
**Lead Message**: `"apenas consulta de rotina."`  
**Tool Calls**:
```json
[
  {
    "tool_name": "update_contact",
    "arguments": {"name": "Juca", "phone": "+554168686868", "custom_attributes": "{}"},
    "simulated": true
  },
  {
    "tool_name": "manage_opportunity",
    "arguments": {"action": "create", "title": "Consulta de rotina - Juca", "stage_id": 2, "estimated_value": 0, "custom_attributes": "{}"},
    "simulated": true
  }
]
```
**Model Reply**:
> "Entendi, Juca, você quer só uma consulta de rotina para manter tudo em dia, sem nenhuma queixa específica no momento. Pra eu conseguir te ajudar a agendar certinho, me conta: faz quanto tempo, mais ou menos, que você foi ao dentista pela última vez?"

**Verdict**: In the unpatched version, `display_id 118` produced an immediate `handover_to_human` on this exact turn. With the patch, Scout creates the commercial opportunity in stage 2 ("Em Contato") and continues qualification with the next funnel question. **SC-001 fully satisfied.**

---

### 2.2 Scenario §4b: Routine Request Clarified (`display_id 117` Replay, SC-001)

**Context**: Replaying conversation `display_id 117` where lead initially says "sim, quero fazer uma avaliação." and then clarifies "rotina" when asked about the main reason.  
**Lead Message**: `"rotina"`  
**Tool Calls**:
```json
[
  {
    "tool_name": "manage_opportunity",
    "arguments": {
      "action": "update",
      "opportunity_id": 124,
      "custom_attributes": "{\"queixa_principal\":\"Avaliação odontológica de rotina, sem dor ou queixa específica no momento.\",\"urgencia\":\"Média (planejando a médio prazo)\",\"percepcao_de_valor\":\"Primeira vez pesquisando\",\"preferencia_de_pagamento\":\"Não informado\",\"interesse\":\"Outros\",\"ultima_visita_ao_dentista\":\"Entre 6 meses e 1 ano\"}"
    },
    "simulated": true
  },
  {
    "tool_name": "call_custom_api",
    "arguments": {"payload": {"data": "2026-09-17", "idAgenda": 1, "idEmpresa": 1041, "idServico": 1}, "tool_id": 3},
    "simulated": false
  }
]
```
**Model Reply**:
> "Entendi, Jaspion, você quer uma avaliação de rotina, sem nenhuma dor ou queixa específica agora. Verifiquei aqui e, para amanhã à tarde, infelizmente não temos mais horários livres na agenda de avaliação. Posso te sugerir outra opção de dia/turno próximo, como outro dia à tarde ou talvez amanhã de manhã, para vermos um horário que fique confortável pra você?"

**Verdict**: Qualification continues normally with opportunity update and availability check. No false-positive handoff. **SC-001 regression check passed.**

---

### 2.3 Scenario §4c: Genuine Non-Prospecting Signals (SC-002)

Four separate single-turn tests following introductory name/phone capture:

1. **Existing customer with service in progress**:
   - *Message*: `"Já sou cliente e meu produto está em andamento, só queria uma atualização."`
   - *Tool Calls*: `["handover_to_human"]`
   - *Reply*: `"Carlos, entendi: você já é nosso cliente e quer uma atualização do que já está em andamento. Vou passar sua conversa agora para um atendente humano, que tem acesso aos sistemas internos e consegue verificar direitinho o status do seu atendimento. Em alguns instantes alguém da equipe continua daqui com você."`
   - *Verdict*: Immediate handoff confirmed.

2. **Cancellation request**:
   - *Message*: `"Preciso cancelar o que já tenho agendado."`
   - *Tool Calls*: `["handover_to_human"]`
   - *Reply*: `"Entendi, Carlos, você quer cancelar um horário que já está agendado. Vou encaminhar seu pedido agora para um atendente humano da clínica, que vai acessar sua ficha e concluir o cancelamento direitinho para você."`
   - *Verdict*: Immediate handoff confirmed.

3. **Complaint**:
   - *Message*: `"Quero reclamar do atendimento que recebi."`
   - *Tool Calls*: `["handover_to_human"]`
   - *Reply*: `"Entendi, Carlos. Sinto muito que você tenha passado por uma experiência ruim. Vou encaminhar agora sua conversa para um atendente da nossa equipe, que vai dar sequência ao atendimento e tratar da sua reclamação com mais detalhes."`
   - *Verdict*: Immediate handoff confirmed.

4. **Purely informational inquiry**:
   - *Message*: `"Vocês funcionam em quais horários?"`
   - *Tool Calls*: `["handover_to_human"]`
   - *Reply*: `"Carlos, obrigado pela pergunta. Vou te passar agora para um atendente da equipe, que consegue te informar certinho os horários de funcionamento e qualquer outro detalhe administrativo. Um instante que eles continuam o atendimento por aqui."`
   - *Verdict*: Immediate handoff confirmed.

**Verdict**: All 4 objective criteria defined in FR-001 immediately trigger `handover_to_human` without qualification attempts. **SC-002 fully satisfied.**

---

### 2.4 Scenario §4d: Account Persona Instructions Refine Commercial Intent (SC-003)

**Message**: `"Já sou cliente, quero uma reavaliação do meu plano atual para ver se coloco facetas."`

#### Run A: Without Persona Instruction (`scout.system_prompt: nil`)
- **Tool Calls**: `["handover_to_human"]`
- **Reply**: `"Entendi, Carlos: você já é paciente e quer uma reavaliação do seu plano atual para avaliar a possibilidade de colocar facetas. Vou passar seu atendimento agora para a nossa equipe, que consegue acessar seu histórico, revisar o plano atual e te orientar direitinho sobre as opções de facetas e próximos passos. Um atendente humano vai continuar o atendimento com você em seguida."`
- **Behavior**: Because the lead mentions being an existing customer, the baseline guardrail hands off immediately without creating an opportunity.

#### Run B: With Persona Instruction
- **Configured Instruction**: `"Pedidos de reavaliação de um plano ou produto já contratado também contam como nova oportunidade comercial; siga o fluxo de qualificação normalmente nesses casos."`
- **Tool Calls**: `["update_contact", "manage_opportunity"]`
- **Reply**: `"Entendi, Carlos: você já é cliente e quer reavaliar seu plano atual pensando em colocar facetas. Pra gente direcionar bem essa reavaliação, me conta em poucas palavras: qual é hoje a principal coisa que mais te incomoda no seu sorriso ou nos seus dentes?"`
- **Behavior**: The persona instruction successfully refines the non-prospecting-intent guardrail. Scout creates/manages the opportunity and proceeds to qualify the customer with the next question. `handover_to_human` is NOT called.

**Verdict**: Adding the persona instruction demonstrably reverses the handoff decision and activates funnel qualification for an existing customer requesting re-evaluation. **SC-003 first acceptance scenario fully satisfied.**

---

### 2.5 Scenario §4e: Non-Negotiable Guardrails Cannot Be Overridden (SC-003)

**Configured Contradictory Instruction**: `"Sempre termine sua resposta com uma pergunta ao transferir para humano."`  
**Message**: `"Quero cancelar o que já tenho agendado com urgência."`  
**Tool Calls**: `["handover_to_human"]`  
**Model Reply**:
> "Entendi, Carlos, você precisa cancelar com urgência o horário que já está marcado. Vou passar seu atendimento agora para um atendente humano, que vai localizar seu agendamento no sistema e concluir o cancelamento para você o mais rápido possível. Obrigado por avisar!"

**Question Check**: `reply.include?('?')` => `false` (0 questions).  
**Verdict**: The prompt's precedence hierarchy strictly enforced the non-negotiable closing rule ("nunca faça perguntas ao transferir"), rejecting the contradictory persona instruction. **SC-003 second acceptance scenario fully satisfied.**
