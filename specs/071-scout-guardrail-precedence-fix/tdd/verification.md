---
feature: 071-scout-guardrail-precedence-fix
verdict: PASS_WITH_GAPS
standard: .specify/extensions/tdd/templates/tdd-test-quality-rubric.md
verified_at: 4c3b4454 # working tree at audit time; feature has zero commits (see Finding 1)
behaviors: 23
proven: 0
likely: 21
test_after: 0
no_test: 0
not_applicable: 2
high_smells: 0
criteria_total: 8 # FR-001..FR-008
criteria_covered: 7 # FR-008 is a structural non-goal, verified by inspection, not by test
sc_total: 4
sc_covered_by_proxy: 4
sc_covered_end_to_end: 0 # see Finding 3
mutation_score: unmeasured # no mutation tool in profile; 4/4 sampled deliberate mutants caught, 0 survivors
suite: 59 passed, 0 failed, 2.55s (feature-scoped: system_prompts_service_spec.rb + action_classifier_service_spec.rb)
---

# TDD Verification: Routine-Request Guardrail False Positive & Persona Precedence Fix

**Verdict: PASS_WITH_GAPS.** Every behavior is `LIKELY` or `NOT_APPLICABLE` (none `PROVEN`, because
the feature has zero git commits to corroborate cycle-order — see Finding 1), no test-quality `HIGH`
smell was found, all four deliberate mutants sampled across both rewritten fragments were caught with
a clean restore, and every FR/SC traces to at least one passing test. The one significant gap is
Finding 3: `tasks.md`'s `T012` (the only layer meant to verify the feature's actual LLM behavior
against SC-001–SC-003, since the automated specs only check prompt *text*) is checked `[X]` with no
recorded evidence anywhere in the feature directory that it was run.

## Test-first evidence

Every behavior's cycle-log entry records a red command and failure output (Cycles 1, 2, 3, 5) or a
deliberate-mutant spot-check in lieu of a first-run red (Cycle 4, for `U7`). None can be corroborated
against git history: `git log` on both changed files stops at `e7beca16ce` (an unrelated prior
feature commit), and `git status`/`git diff` show every change as an uncommitted working-tree
modification — `cycle-log.md` itself records `commit: none (--no-commit, pending explicit user
approval per AGENTS.md)` on all five cycles. This is a legitimate, disclosed consequence of this
repo's `AGENTS.md` workflow constraint ("never commit before explicit user validation"), not a
process violation — but it means test-first ordering rests entirely on the cycle log's self-report,
with no independent corroboration available. Per the rubric, that caps every behavior at `LIKELY`.

| Behavior | Class | Evidence |
| --- | --- | --- |
| A1 | LIKELY | Cycle 1 red recorded (`custom/spec/.../system_prompts_service_spec.rb -e "specifies exhaustive..."` → 1 failure); no git corroboration |
| A2 | LIKELY | Cycle 2 red recorded; no git corroboration |
| A3 | LIKELY | Cycle 3 red recorded (3 failures incl. line 126); no git corroboration |
| A4 | LIKELY | Cycle 3 red recorded (line 135); no git corroboration |
| A5 | LIKELY | Cycle 3 red recorded (line 142); no git corroboration |
| A6 | LIKELY | Cycle 5 red recorded (line 186); no git corroboration |
| A7 | LIKELY | Cycle 5 red recorded (line 194); no git corroboration |
| U1 | LIKELY | Cycle 1 |
| U2 | LIKELY | Cycle 3 |
| U3 | LIKELY | Cycle 3 |
| U4 | LIKELY | Cycle 3 (same `it` block as U3) |
| U5 | LIKELY | Cycle 3 |
| U6 | LIKELY | Cycle 1 |
| U7 | LIKELY | Cycle 4 deliberate-mutant spot-check (first-run pass, per playbook); independently re-verified this audit (mutant 4 below) — caught |
| U8 | NOT_APPLICABLE | Pre-existing test, unmodified by this feature's diff, still green |
| U9 | LIKELY | Ordering assertions inside the same `it` block Cycle 3 modified (line 126) |
| U10 | LIKELY | Cycle 5 |
| U11 | LIKELY | Cycle 5 |
| U12 | LIKELY | Cycle 5 |
| U13 | LIKELY | Cycle 5; independently re-verified this audit (mutant 2 below) — caught |
| U14 | LIKELY | Cycle 5; independently re-verified this audit (mutant 3 below) — caught |
| U15 | LIKELY | Same `it` block as the Cycle 5 precedence-sentence red (line 178) |
| U16 | NOT_APPLICABLE | Pre-existing test, unmodified by this feature's diff, still green |

Diff audit of pre-existing assertions (`git diff` on both files): the three renamed `it` blocks at
spec lines 126, 135, 142 had their example substrings updated to match the new exhaustive criteria
text — each new substring is equally or more specific than what it replaced (e.g. `'afirma já ser
cliente, menciona tratamento em andamento'` → `'já é cliente com um produto ou serviço em
andamento'`). No assertion was removed, loosened, weakened to a truthiness check, skipped, or excluded
from a filter. This is a legitimate spec-follows-spec-rewrite update, not weakening.

## Findings

| # | Severity | Finding | Evidence |
| --- | --- | --- | --- |
| 1 | MED | Feature has zero git commits; every cycle log entry records `commit: none`. Test-first ordering for all 21 `LIKELY` behaviors rests solely on the self-reported cycle log — nothing independently corroborates that a test actually failed before its implementing edit landed. | `git log --oneline -- custom/app/.../system_prompts_service.rb custom/spec/.../system_prompts_service_spec.rb` → last commit `e7beca16ce` (unrelated); `git status`/`git diff` show all feature changes as uncommitted working-tree state; `tdd/cycle-log.md:20,29,41,49,61` |
| 2 | MED | `tdd/test-list.md`'s `test` column has 3 stale line-number pointers (test exists and passes under the named `it` string, but at a different line than claimed — later cycles shifted line numbers and the list was never refreshed) | `U8` claims `system_prompts_service_spec.rb:148`, actual `153`; `U15` claims `154-158`, actual `178-184`; `U16` claims `180-185`, actual `221` |
| 3 | HIGH | `tasks.md` `T012` ("Run behavioral replay smoke tests using `Custom::Scout::PlaygroundRunner` per `quickstart.md` §4 (SC-001, SC-002, SC-003)") is checked `[X]`, but no artifact, note, cycle-log entry, or output anywhere in `specs/071-scout-guardrail-precedence-fix/` records that this replay was executed or what it produced. This is the only verification layer the feature's own docs designate for the actual LLM behavioral outcome (`test-list.md`'s "Out of scope" section explicitly defers SC-001–003's real behavior check to this task, since `tdd-profile.md` has `acceptance: null` for Ruby and every RubyLLM-touching spec stubs the chat response). A checked task with the acceptance-level evidence missing is a completion claim with nothing behind it. | `tasks.md:117`; `tdd/cycle-log.md` has no Cycle 6+/T012 entry; no `local://` or other artifact referencing `display_id 117`/`118` replay output found in the feature directory |
| 4 | LOW | `tasks.md` `T013` is checked `[X]` with the stated goal "confirm zero gaps and clean wiring," but `bin/sync-custom-module-hooks --audit` (re-run this session) reports 13 gaps. All 13 are pre-existing and unrelated to this feature's files (spec-kit tooling manifests, `Gemfile`/`Gemfile.lock`, `vite.config.ts`, `docker/Dockerfile`, one dashboard JS file) — `--check` (the actually feature-relevant half) correctly reports 62/62 present. The task's "zero gaps" framing overstates what was confirmed. | `docker compose exec -T rails ruby bin/sync-custom-module-hooks --audit` this session → `13 gaps found` |

No `HIGH` test-quality-catalogue smell (tautological assertion, doubled subject, vacuous assertion,
etc.) was found in either the 8 new/changed `it` blocks or the 3 renamed ones. Every assertion is a
literal-substring check against the real output of `Custom::Scout::SystemPromptsService.build` (no
double stands in for the subject), consistent with this file's pre-existing, unbroken convention for
every other guardrail bullet in the same `describe` block (lines 100–124 do the same thing for
untouched bullets). Multiple `expect` calls per `it` (e.g. line 159, 194) mirror the file's existing
style for one coherent prompt fragment, not new assertion-roulette.

## Mutation results

No mutation tool is wired for Ruby in this repo (`tdd-profile.md`: `mutation: null`). Used deliberate
mutants on the 4 highest-risk behaviors (the ones an acceptance criterion most directly depends on,
across both rewritten fragments). Each mutant: made the change, ran the single named test, confirmed
failure, restored the file from a pre-mutation copy, confirmed byte-identical restore via `md5sum`.

| Mutant | File:line | Change | Behavior | Test | Survived? |
| --- | --- | --- | --- | --- | --- |
| 1 | `system_prompts_service.rb:78` | Deleted the routine-request carve-out sentence (FR-002's core fix) | A1/U6 | `specifies exhaustive non-prospecting criteria...` | No — caught |
| 2 | `system_prompts_service.rb:168` | Deleted the `", mesmo que pareçam, à primeira vista, tocar no mesmo assunto dessa diretriz"` overlap clause (FR-005) | A6/U13 | `allows persona instructions to refine only the non-prospecting-intent guardrail...` | No — caught |
| 3 | `system_prompts_service.rb:168` | Deleted `"Nenhuma outra diretriz da seção acima pode ser alterada por estas instruções."` (FR-004/FR-006 protection) | A7/U14 | `preserves non-negotiable guardrails and forbids altering any other guardrail...` | No — caught |
| 4 | `system_prompts_service.rb:78` | Replaced `"produto ou serviço em andamento"` with `"consulta odontológica em andamento"` (segment-specific term, FR-003/SC-004) | U7 | `uses domain-agnostic wording...` | No — caught (independently re-verifies Cycle 4's self-reported spot-check) |

0/4 survivors. Full feature-scoped suite re-confirmed green (59 passed, 0 failed) after all four
restores. Sample size: 4 of 23 behaviors (~17%), concentrated on the clauses that carry the feature's
actual rule changes (the two clauses each fragment adds beyond copy-editing); the more mechanical
criteria substitutions (U2–U5, the four objective non-prospecting clauses) were not independently
mutated this session — their risk profile is materially lower (literal find-and-replace of a noun
phrase already exercised by the same test pattern as the ones sampled) and the cycle log already
carries a recorded red for each.

## Traceability

| Requirement | Tests | End to end (proxy notes) |
| --- | --- | --- |
| FR-001 (objective criteria only) | A3, A4, A5, U2–U5 | Prompt-text proxy only; see "What was not audited" |
| FR-002 (routine-request carve-out) | A1, U6 | Prompt-text proxy only |
| FR-003 (domain-agnostic wording) | U7 | Prompt-text proxy + independently re-verified via `grep` (0 matches) and deliberate mutant 4 |
| FR-004 (precedence names non-negotiables + sole exception) | A6, A7, U10–U14 | Prompt-text proxy only |
| FR-005 (overlap doesn't block refinement) | A6, U13 | Prompt-text proxy only; independently re-verified via deliberate mutant 2 |
| FR-006 (non-negotiables still win) | A7, U10, U11 | Prompt-text proxy only; independently re-verified via deliberate mutant 3 |
| FR-007 (reactive safety net unaffected) | `action_classifier_service_spec.rb` (unchanged, 5/5 green in feature suite) + U8 | Confirmed via `git diff --stat` — zero diff on `action_classifier_service.rb`/`action_classifier_schema.rb` |
| FR-008 (no new tool/model/schema) | — (structural non-goal) | Not testable by assertion; verified by inspection: diff touches exactly 2 files, no migration/model/tool added |
| SC-001 | A1, A2 (proxy) | **No end-to-end test.** Designated verification is `quickstart.md` §4a/§4b — no evidence T012 ran (Finding 3) |
| SC-002 | A3, A4, A5 (proxy) | **No end-to-end test.** Designated verification is `quickstart.md` §4c — no evidence T012 ran (Finding 3) |
| SC-003 | A6, A7 (proxy) | **No end-to-end test.** Designated verification is `quickstart.md` §4d/§4e — no evidence T012 ran (Finding 3) |
| SC-004 | U7 | Independently re-verified via `grep` this audit session (0 matches) |

Untested criteria: none — every FR and SC traces to at least one passing RSpec example. Tests tracing
to nothing: none. The gap is depth, not coverage: FR-001–FR-006 and SC-001–SC-003 are verified only
at the "prompt contains the required instruction" layer, not at the "Scout's LLM actually decides
X" layer, because this stack has no deterministic way to assert an LLM decision (`tdd-profile.md`:
`acceptance: null`) — a structural, disclosed constraint the feature's own `plan.md`/`test-list.md`
name explicitly, not a gap this audit discovered. What *is* a genuine gap is that the one designated
mechanism for closing that depth gap (`T012`'s replay) shows no evidence of having run (Finding 3).

## What was not audited

- **Full Ruby suite** (`bundle exec rspec`, 977s) was not re-run this session; relied on
  `tdd-profile.md`'s recorded baseline (8924 examples, 1 pre-existing unrelated failure in
  `agent_builder_spec.rb`, order-dependent test pollution, confirmed unrelated to this feature by the
  profile itself). Feature-scoped suite (`system_prompts_service_spec.rb` +
  `action_classifier_service_spec.rb`, 59 examples) was run twice this session (once before mutation
  testing, once after all four restores) — 0 failures both times.
- **Coverage**: no coverage tool wired for Ruby in this repo (`tdd-profile.md`); not assessed.
- **Mutation was sampled, not exhaustive**: 4 of 23 behaviors, both rewritten fragments represented,
  chosen for highest rule-change risk; the remaining 19 were not independently mutated this session
  (all have a recorded cycle-log red).
- **`quickstart.md` §4's behavioral replay and §5's manual widget check**: not executed by this audit
  — both require live `RubyLLM` calls against a real or reconstructed conversation and are explicitly
  framed by the feature's own docs as non-deterministic smoke checks, not automated pass/fail tests.
  Their absence of recorded evidence is reported as Finding 3, not filled in by this audit.
- **JavaScript/frontend suite**: out of scope — this feature touches no frontend file.
- **RuboCop and `bin/sync-custom-module-hooks --check`**: re-run independently this session (0
  offenses; 62/62 wiring points present) — both confirmed, not merely trusted from `tasks.md`.
