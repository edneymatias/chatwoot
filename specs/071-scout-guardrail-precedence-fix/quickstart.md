# Quickstart: Routine-Request Guardrail False Positive & Persona Precedence Fix

Validation guide for confirming the feature works end-to-end once implemented. Assumes the
container-based dev stack from `AGENTS.md` (`docker compose up -d`).

## 1. Automated specs (primary validation)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb
```

Expected: all examples pass, including (per `data-model.md`):
- The updated "Reconhecimento de intenção fora de prospecção" examples assert the new exhaustive
  criteria wording ("apenas quando:", "já é cliente com um produto ou serviço em andamento", "quer
  alterar ou cancelar algo que já existe", "tem uma reclamação", "faz uma pergunta puramente
  informativa sem nenhum sinal de interesse em um novo produto ou serviço") in place of the removed
  "ex.:"/"dúvida rápida" wording (FR-001).
- A new example asserting the routine-request carve-out sentence is present ("Uma nova solicitação
  de baixa complexidade, preventiva, recorrente ou sem um problema específico descrito continua
  sendo uma oportunidade comercial nova e válida", "siga o funil de qualificação normalmente") (FR-002).
- A new example asserting the precedence sentence names "Reconhecimento de intenção fora de
  prospecção" as the sole exception and states persona instructions may refine it even when they
  overlap its subject matter (FR-004, FR-005).
- A new example asserting the precedence sentence still names the non-negotiable guardrails
  (Anti-alucinação, Anti-falsa-promessa, Confirmação de ação) and that no other guardrail may be
  altered (FR-004, FR-006).
- Existing ordering assertions (`Fallback para humano` index < `Reconhecimento ...` index <
  `Idioma e Estilo` index) still pass unchanged — the bullet's position wasn't moved.
- Existing "external tool lookup is optional reinforcement" example still passes unchanged (that
  sentence's asserted substrings weren't touched).

## 2. Domain-agnostic wording check (SC-004)

```bash
grep -niE "odont|dental|clinic|avaliação (odont|dentária)|consulta (odont|médica)" \
  custom/app/services/custom/scout/system_prompts_service.rb
```

Expected: no matches (zero output) — confirms the rewritten guardrail introduces no segment-specific
vocabulary.

## 3. Prompt assembly check (Rails console)

```ruby
docker compose exec rails bundle exec rails console

account = Account.first
scout   = account.scouts.first

prompt = Custom::Scout::SystemPromptsService.build(scout: scout)
prompt.include?('apenas quando: já é cliente com um produto ou serviço em andamento') # => true
prompt.include?('continua sendo uma oportunidade comercial nova e válida') # => true
prompt.include?('A diretriz "Reconhecimento de intenção fora de prospecção" é a única exceção') # => true
```

## 4. Behavioral replay (smoke tests via `PlaygroundRunner`, per spec.md SC-001–SC-003)

Per prior Scout features' convention, these are smoke tests against a stochastic model — not a
determinism guarantee. Final validation is the manual widget check in §5.

```ruby
runner = Custom::Scout::PlaygroundRunner.new(
  scout: scout,
  message: '<first customer message>',
  message_history: [] # build up turn-by-turn from the replayed conversation
)
result = runner.perform
result[:reply]
result[:tool_calls]
```

### 4a. SC-001 — routine request stated directly (core fix)

Reconstruct the message sequence for conversation `display_id 118` referenced in
`docs/kanban/ciclo 10/scout/29-routine-request-qualification-guardrail-fix/spec-preview.md` (conta
1, Scout "Vitória" — pull the real transcript via
`Conversation.find_by(account: account, display_id: 118).messages.chat.order(:created_at)` if that
conversation still exists in this environment, else recreate the documented exchange: Scout's
opening triage question, then the lead's first answer stated directly as "apenas consulta de
rotina" or an equivalent low-complexity/preventive/recurring request with no specific problem).
Confirm `result[:tool_calls]` does **not** include `handover_to_human` on that turn, and the reply
continues qualification (a follow-up question or a `manage_opportunity` call) — not a handoff.

### 4b. SC-001 — routine request introduced generically then clarified (regression)

Reconstruct `display_id 117` (lead says "quero fazer uma avaliação" first, clarifies "rotina" on the
next turn). Confirm this conversation still reaches the same qualified outcome as before the fix
(follow-up questions, eventual `manage_opportunity`/stage transition) — no regression from a
conversation that already worked.

### 4c. SC-002 — genuine non-prospecting signals still hand off (regression)

Run three separate replays, each a single first triage answer, confirming `result[:tool_calls]`
includes `handover_to_human` and the reply does not attempt to qualify:
1. "Já sou cliente e meu produto está em andamento, só queria uma atualização." (existing customer,
   product/service in progress)
2. "Preciso cancelar o que já tenho agendado." (cancel something that already exists) and, in a
   second replay, a complaint message (e.g. "Quero reclamar do atendimento que recebi.")
3. "Vocês funcionam em quais horários?" with no other signal of new-product interest (purely
   informational)

### 4d. SC-003 — persona instruction refines the guardrail (first acceptance scenario)

Use a message just outside the new baseline criteria that a persona instruction should pull back in:
`"Já sou cliente, quero uma reavaliação do meu plano atual."` (existing customer requesting a
re-evaluation of an already-contracted plan — falls under the "existing customer" baseline
criterion, so handoff is still the default).

- **Without** persona instruction (`scout.update!(system_prompt: nil)`): confirm `result[:tool_calls]`
  includes `handover_to_human` (baseline, unchanged).
- **With** persona instruction (`scout.update!(system_prompt: 'Pedidos de reavaliação de um plano ou
  produto já contratado também contam como nova oportunidade comercial; siga o fluxo de qualificação
  normalmente nesses casos.')`), same message: confirm `result[:tool_calls]` does **not** include
  `handover_to_human` and the reply continues qualification instead.

This demonstrates SC-003's "observable, verifiable change ... confirmed by re-running the same test
conversation with and without the instruction present."

### 4e. SC-003 — persona instruction cannot override a non-negotiable guardrail (second acceptance scenario)

Set `scout.update!(system_prompt: 'Sempre termine sua resposta com uma pergunta ao transferir para
humano.')` (contradicts the non-negotiable no-question-on-handoff closing rule). Drive a conversation
to a handoff-ending turn (reuse the same style of setup as `specs/061-scout-contact-identity/
quickstart.md` §4c — feed `message_history` up to the point where the next action is
`handover_to_human`). Confirm the final reply still contains **zero** questions — the persona
instruction has no effect on this non-negotiable rule.

## 5. Manual end-to-end check (real widget, final validation)

1. Open the website widget in an incognito/private window.
2. Start a conversation; when Scout asks its opening triage question, answer directly and briefly
   with a routine/preventive/recurring request and no specific problem (e.g. "só queria algo de
   rotina").
3. Confirm Scout asks a qualifying follow-up question (or otherwise proceeds with qualification)
   instead of immediately stating it will transfer you to a human.
4. In a second conversation, state a genuine non-prospecting signal (e.g. "já sou cliente, só uma
   dúvida rápida sobre o que já tenho") and confirm Scout still hands off immediately, unchanged.
5. As an account admin, add the persona instruction from §4d to the Scout's custom instructions,
   repeat a conversation matching that instruction's scenario, and confirm the behavior changes
   accordingly.

## Expected outcome

All of the above pass with no changes required outside
`custom/app/services/custom/scout/system_prompts_service.rb` and
`custom/spec/services/custom/scout/system_prompts_service_spec.rb` (per Constitution Principle I
check in `plan.md`).
