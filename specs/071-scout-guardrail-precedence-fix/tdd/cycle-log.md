# Cycle Log: Routine-Request Guardrail False Positive & Persona Precedence Fix

Append only. Newest last. Every entry's `red` block is the evidence that the test existed and
failed before the implementation.

## Baseline

- feature-scoped suite: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb custom/spec/services/custom/scout/action_classifier_service_spec.rb` -> 54 passed, 0 failed
- full ruby suite (from `.specify/memory/tdd-profile.md`, detected at `b80a0f31ce`, 2 unrelated commits behind this baseline): `bundle exec rspec` -> 8924 examples, 1 failure (`AgentBuilder#perform when user does not exist reserves email capacity and enqueues the invitation`, `spec/builders/agent_builder_spec.rb:47` — order-dependent test pollution from an earlier spec in the run, unrelated to Scout/prompt code; re-running that file alone passes all 12 examples). Not re-run in full for this baseline (977s, no relevant commits since detection); this feature's own scope is the 54/0 result above.
- commit: `4c3b4454`
- recorded: cycle 0, before any change

## Cycle 1: A1, U1, U6 exhaustive non-prospecting marker and routine-request carve-out

- test: `custom/spec/services/custom/scout/system_prompts_service_spec.rb:154` "specifies exhaustive non-prospecting criteria introduced by apenas quando and explicitly carves out routine requests" (new)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb -e "specifies exhaustive non-prospecting criteria introduced by apenas quando"`
  -> `expected "[Identidade e Escopo]..." to include "- Reconhecimento de intenção fora de prospecção: Se em qualquer momento ficar claro que o contato não busca uma nova oportunidade comercial — apenas quando:"` (1 failed)
- green: `custom/app/services/custom/scout/system_prompts_service.rb:78` replaced the guardrail bullet with Fragment 1 text introducing "apenas quando:" and the explicit carve-out. Feature suite -> 54 passed, 0 failed
- refactor: none needed; prompt heredoc string replacement per data-model.md
- commit: none (`--no-commit`, pending explicit user approval per AGENTS.md)

## Cycle 2: A2 unconditional routine-request qualification without turn or phrasing dependency

- test: `custom/spec/services/custom/scout/system_prompts_service_spec.rb:166` "phrases the routine-request qualification unconditionally without turn or phrasing dependency" (new)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb -e "phrases the routine-request qualification unconditionally"`
  -> `expected "[Identidade e Escopo]..." not to include "responde a uma pergunta de triagem"` (1 failed)
- green: `custom/app/services/custom/scout/system_prompts_service.rb:78` contains no conversational-turn conditioning. Feature suite -> 54 passed, 0 failed
- refactor: none
- commit: none (`--no-commit`)

## Cycle 3: A3, A4, A5, U2, U3, U4, U5 objective non-prospecting criteria

- test: `custom/spec/services/custom/scout/system_prompts_service_spec.rb:126,135,142` (updated to assert new objective clauses)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb:126 custom/spec/services/custom/scout/system_prompts_service_spec.rb:135 custom/spec/services/custom/scout/system_prompts_service_spec.rb:142`
  -> 3 failures:
     - `expected "... to include \"já é cliente com um produto ou serviço em andamento\""`
     - `expected "... to include \"quer alterar ou cancelar algo que já existe (não uma nova solicitação), tem uma reclamação\""`
     - `expected "... to include \"faz uma pergunta puramente informativa sem nenhum sinal de interesse em um novo produto ou serviço\""`
- green: `custom/app/services/custom/scout/system_prompts_service.rb:78` satisfies all 4 objective non-prospecting criteria. Feature suite -> 54 passed, 0 failed
- refactor: none
- commit: none (`--no-commit`)

## Cycle 4: U7 domain-agnostic wording in non-prospecting guardrail

- test: `custom/spec/services/custom/scout/system_prompts_service_spec.rb:148` "uses domain-agnostic wording in non-prospecting guardrail without niche or segment vocabulary" (new)
- red: verified via deliberate-mutant spot check (inserted "consulta odontológica" into line 78, confirmed test failed: `expected "- Reconhecimento de intenção fora de prospecção: consulta odontológica..." not to match /odont|dental|clinic|avaliação (odont|dentária)|consulta (odont|médica)/i`, then reverted)
- green: `custom/app/services/custom/scout/system_prompts_service.rb:78` verified free of niche or segment vocabulary. Feature suite -> 54 passed, 0 failed
- refactor: none
- commit: none (`--no-commit`)

## Cycle 5: A6, A7, U10, U11, U12, U13, U14 persona instructions precedence sentence

- test: `custom/spec/services/custom/scout/system_prompts_service_spec.rb:178,186,194`
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb:178 custom/spec/services/custom/scout/system_prompts_service_spec.rb:186 custom/spec/services/custom/scout/system_prompts_service_spec.rb:194`
  -> 3 failures:
     - `expected "... to include \"Siga-as, exceto quando conflitarem com o formato de resposta JSON\""`
     - `expected "... to include \"A diretriz \\\"Reconhecimento de intenção fora de prospecção\\\" é a única exceção: estas instruções podem refinar ou expandir o que conta como uma nova oportunidade comercial válida especificamente nesse critério, mesmo que pareçam, à primeira vista, tocar no mesmo assunto dessa diretriz.\""`
     - `expected "... to include \"Siga-as, exceto quando conflitarem com o formato de resposta JSON, com a exigência de responder exclusivamente a partir do contexto fornecido, ou com as diretrizes inegociáveis de segurança e resposta descritas acima — no mínimo, Anti-alucinação, Anti-falsa-promessa e Confirmação de ação.\""`
- green: `custom/app/services/custom/scout/system_prompts_service.rb:168` replaced precedence sentence with Fragment 2 text. Full target suite (`system_prompts_service_spec.rb` + `action_classifier_service_spec.rb`) -> 59 passed, 0 failed
- refactor: verified RuboCop clean across both files (0 offenses); verified custom module hooks audit (all 62 wiring points present)
- commit: none (`--no-commit`)
