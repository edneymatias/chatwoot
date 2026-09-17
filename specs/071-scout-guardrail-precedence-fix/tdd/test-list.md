---
feature: 071-scout-guardrail-precedence-fix
loop: outside-in
profile: .specify/memory/tdd-profile.md
spec_criteria: 7
planned_at: 4c3b4454
updated_at: 4c3b4454
suite_baseline: red
---

# Test List: Routine-Request Guardrail False Positive & Persona Precedence Fix

## Entry point and testing ceiling (read before the tables below)

This feature has no separate acceptance runner (`.specify/memory/tdd-profile.md` records
`acceptance: null` for Ruby) and FR-008 scopes the whole feature to "the prompt text and its
precedence structure" — there is no new tool, model, or deterministic trigger to exercise. The
highest level this repo's stack can deterministically test is `Custom::Scout::SystemPromptsService
.build`'s returned string: every existing spec in `custom/spec/services/custom/scout/*_spec.rb`
that touches the LLM (`playground_runner_spec.rb:33-34`, `agent_runner_spec.rb`) stubs
`RubyLLM::Chat`/`RubyLLM::Message` with a scripted response rather than driving a real model
completion, so "Scout hands off" / "Scout continues qualifying" as an actual model decision is not
something an RSpec run in this stack can assert.

Consequently every outer-loop (`A`) behavior below asserts the **prompt-text mechanism** that must
exist for its acceptance scenario's outcome to be possible (the strongest deterministic proxy), not
the LLM's eventual choice. The full behavioral claim — the model actually hands off or actually
qualifies, and actually changes its choice when a persona instruction is added — is verified by the
non-deterministic replay scenarios already specified in `quickstart.md` §4, which that document
itself frames as "smoke tests against a stochastic model — not a determinism guarantee." That
replay is not part of this automated list; see "Out of scope."

All behaviors below are exercised through `Custom::Scout::SystemPromptsService.build(scout:,
contact:, inbox:, ...)` — the feature's only public entry point — matching the existing spec file's
`subject(:prompt) { described_class.build(...) }` convention.

## Outer loop: acceptance behaviors

One per acceptance scenario in `spec.md` (7 total, across User Stories 1–3). Each stays red until
`system_prompts_service.rb`'s two rewritten fragments are live.

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| A1 | Built prompt's non-prospecting guardrail states, verbatim, that a low-complexity/preventive/recurring/no-specific-problem new request is a valid new commercial opportunity that follows the normal funnel, introduced by the exhaustive "apenas quando:" (not the old illustrative "ex.:") framing for its non-prospecting criteria | US1 AS1; FR-001, FR-002, SC-001 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:159` "specifies exhaustive non-prospecting criteria introduced by apenas quando and explicitly carves out routine requests" |
| A2 | Built prompt's routine-request carve-out and exhaustive non-prospecting criteria are phrased as unconditional facts about the request's nature, with no clause conditioning classification on which turn or wording surfaced it — the same single guardrail text governs a directly-stated and a later-clarified routine request alike (proxy only — see note below) | US1 AS2; SC-001 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:171` "phrases the routine-request qualification unconditionally without turn or phrasing dependency" |
| A3 | Built prompt's non-prospecting guardrail's exhaustive criteria names "existing customer with a product or service already in progress" | US2 AS1; FR-001, SC-002 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:126` "instructs immediate handover_to_human upon recognizing existing customer with product or service in progress" |
| A4 | Built prompt's non-prospecting guardrail's exhaustive criteria names both "wants to change or cancel something that already exists" and "has a complaint" | US2 AS2; FR-001, SC-002 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:135` "instructs immediate handover_to_human for change, cancel, or complaint requests without self-resolution" |
| A5 | Built prompt's non-prospecting guardrail's exhaustive criteria names "a purely informational question with no signal of interest in a new product or service" | US2 AS3; FR-001, SC-002 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:142` "instructs immediate handover_to_human for purely informational question with no signal of new interest" |
| A6 | Built prompt's precedence sentence names "Reconhecimento de intenção fora de prospecção" as the sole guardrail persona instructions may refine or expand, and states this applies even when the persona instruction textually overlaps the guardrail's subject | US3 AS1; FR-004, FR-005, SC-003 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:186` "allows persona instructions to refine only the non-prospecting-intent guardrail even on subject-matter overlap" |
| A7 | Built prompt's precedence sentence still names the non-negotiable guardrails (at minimum Anti-alucinação, Anti-falsa-promessa, Confirmação de ação) and states no other guardrail bullet may be altered by persona instructions | US3 AS2; FR-004, FR-006, SC-003 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:194` "preserves non-negotiable guardrails and forbids altering any other guardrail from persona instructions" |

**Note on A2**: no RSpec-level test can distinguish "stated directly" from "introduced then
clarified" because the prompt has exactly one guardrail text with no phrasing-conditional branch —
its test asserts the absence of any such conditioning language (a regression guard against a future
edit that accidentally reintroduces a turn-dependent qualifier). The scenario's actual outcome
equivalence is confirmed only by `quickstart.md` §4a/§4b's replay of conversations `display_id
117`/`118`.

## Inner loop: unit behaviors

### `custom/app/services/custom/scout/system_prompts_service.rb`

Single file, two private heredoc-returning methods (`guardrails_section`,
`custom_instructions_section`), both reachable only through `.build`. Grouped by method below.

#### `guardrails_section` — "Reconhecimento de intenção fora de prospecção" bullet (Fragment 1)

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U1 | Introduces the non-prospecting criteria with the exhaustive marker "apenas quando:" and no longer with the illustrative "ex.:" | FR-001 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:159` "specifies exhaustive non-prospecting criteria introduced by apenas quando and explicitly carves out routine requests" |
| U2 | Classifies an existing customer with a product or service already in progress as non-prospecting | FR-001 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:126` "instructs immediate handover_to_human upon recognizing existing customer with product or service in progress" |
| U3 | Classifies wanting to change or cancel something that already exists (explicitly "not a new request") as non-prospecting | FR-001 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:135` "instructs immediate handover_to_human for change, cancel, or complaint requests without self-resolution" |
| U4 | Classifies a complaint as non-prospecting | FR-001 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:135` "instructs immediate handover_to_human for change, cancel, or complaint requests without self-resolution" |
| U5 | Classifies a purely informational question with no signal of interest in a new product or service as non-prospecting | FR-001 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:142` "instructs immediate handover_to_human for purely informational question with no signal of new interest" |
| U6 | States explicitly that a new request that is low-complexity, preventive, recurring, or has no specific problem described is still a valid new commercial opportunity and follows the normal qualification funnel — the boundary case on the other side of U2–U5 | FR-002 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:159` "specifies exhaustive non-prospecting criteria introduced by apenas quando and explicitly carves out routine requests" |
| U7 | Guardrail text contains zero business-segment-specific vocabulary (no medical/dental/niche terms) | FR-003, SC-004 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:148` "uses domain-agnostic wording in non-prospecting guardrail without niche or segment vocabulary" |
| U8 | External customer-status tool lookup remains optional reinforcement, never blocking, and a clear verbal signal alone still suffices without ERP confirmation (unaffected by the rewrite) | FR-007 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:153` "instructs that external customer status lookup is optional reinforcement and never blocks handoff" |
| U9 | The bullet's position is preserved: after "Fallback para humano", before "Idioma e Estilo" (unaffected by the rewrite; ordering assertions live in the same `it` block as U1 and carry forward unchanged when that block is rewritten) | — (structural invariant recorded here; no FR references ordering, but `data-model.md` and existing spec assertions require it preserved) | example | DONE | `system_prompts_service_spec.rb:131-132` ordering assertions inside "instructs immediate handover_to_human upon recognizing existing customer..." |

**Note on U7**: the pre-rewrite bullet already contains no medical/dental-specific vocabulary
(only the generic word "tratamento"), so this test may pass on its first run against the
*current* text too — not a valid red by itself. Per `tdd-loop-playbook.md` Step 3, treat a
first-run pass as "behavior already exists": apply the deliberate-mutant check (temporarily
insert a segment-specific term into the bullet, confirm the test fails, then revert) rather than
expecting a normal pre-implementation red.

#### `custom_instructions_section` — precedence sentence (Fragment 2)

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U10 | Names the non-negotiable guardrails persona instructions may never override, at minimum "Anti-alucinação, Anti-falsa-promessa e Confirmação de ação" | FR-004, FR-006 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:194` "preserves non-negotiable guardrails and forbids altering any other guardrail from persona instructions" |
| U11 | Retains the pre-existing JSON-response-format and context-only requirements in the same precedence clause (must not be dropped while the sentence is rewritten to add the named list) | FR-004, FR-006 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:194` "preserves non-negotiable guardrails and forbids altering any other guardrail from persona instructions" |
| U12 | Names "Reconhecimento de intenção fora de prospecção" as the sole guardrail account persona instructions may refine or expand what counts as valid commercial intent | FR-004 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:186` "allows persona instructions to refine only the non-prospecting-intent guardrail even on subject-matter overlap" |
| U13 | States the refinement applies even when the persona instruction appears, at first glance, to touch the same subject as the guardrail — no textual-overlap avoidance required | FR-005 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:186` "allows persona instructions to refine only the non-prospecting-intent guardrail even on subject-matter overlap" |
| U14 | States no other guardrail bullet in the section may be altered by persona instructions | FR-004 | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:194` "preserves non-negotiable guardrails and forbids altering any other guardrail from persona instructions" |
| U15 | Wraps the account's persona text verbatim inside `<account_custom_instructions>` tags, preceded by the `[Instruções Personalizadas da Conta]` header (unaffected by the precedence-sentence rewrite; the stale precedence substring in the same `it` block is what U10–U14 replace) | — (structural mechanism, `data-model.md` "Carrier" section) | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:178-184` "wraps operator custom instructions in subordinate tags with override prohibition" |
| U16 | Omits the entire custom-instructions section (and therefore the precedence sentence) when `scout.system_prompt` is blank (unaffected by the rewrite) | — (structural mechanism, unaffected) | example | DONE | `custom/spec/services/custom/scout/system_prompts_service_spec.rb:221` "omits the custom instructions section without raising errors" |

## Invariants and edge cases still to place

None — every behavior above already has a home in the one file/two-method scope this feature
touches (`plan.md` Scale/Scope).

## Out of scope

- **Real LLM behavioral outcome for any acceptance scenario** (Scout actually calling
  `handover_to_human` or actually continuing qualification, and a persona instruction actually
  changing that choice): no acceptance runner exists for this stack (`tdd-profile.md`:
  `acceptance: null`), and every existing spec that touches `RubyLLM` stubs the chat response
  (`playground_runner_spec.rb:33-34`). Verified instead by `quickstart.md` §4's scripted
  `PlaygroundRunner` replays and §5's manual widget check, both explicitly non-deterministic smoke
  checks, not automated pass/fail tests.
- **`Custom::Scout::ActionClassifierService` / `out_of_scope_commercial_request` reactive safety
  net (FR-007)**: explicitly unchanged by this feature (`research.md` §4); its existing spec
  (`custom/spec/services/custom/scout/action_classifier_service_spec.rb`) is already green
  (confirmed at planning time, part of the 54-example/0-failure baseline below) and needs no new
  characterization test since the file is never touched.
- **Genuinely ambiguous requests, persona-instruction-vs-persona-instruction conflicts, and
  segments beyond the one observed in testing**: `spec.md` Edge Cases explicitly leaves these to
  the model's own judgment — no objective criterion to assert.
- **RuboCop line-length / heredoc-exemption compliance**: not a behavior; a lint gate already
  covered by `tasks.md` T010, decided in `research.md` §3.
- **All other guardrail bullets in `guardrails_section`** (Intenção Comercial, Esclarecimento,
  Identidade do contato, Ritmo e condução da conversa, Respeito ao ritmo do lead, Fallback para
  humano, Idioma e Estilo) and the rest of `system_prompts_service.rb` (identity, funnel, context,
  handoff-closing-reminder, response-format sections): untouched by this feature (`plan.md`
  Constitution Check, Principle II); their existing tests are unaffected and out of this list's
  scope.

## Verification commands

Copied verbatim from `.specify/memory/tdd-profile.md` at planning time:

- Single test: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file} -e "{name}"`
- File: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file}`
- Full suite: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec`
- No coverage, mutation, or property tool wired for Ruby in this repo — test strength is verified
  by the deliberate-mutant spot check (`tdd-loop-playbook.md` Step 3) instead.

Feature-scoped baseline confirmed at planning time (narrower than the full suite, per
`AGENTS.md`'s "scope local backend runs to `custom/spec/` plus the specific modified core files"
guidance and `tdd-profile.md`'s note that the full 977s run is reserved for a pre-commit/pre-PR
gate):

```
docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb \
  custom/spec/services/custom/scout/action_classifier_service_spec.rb
# 54 examples, 0 failures
```
