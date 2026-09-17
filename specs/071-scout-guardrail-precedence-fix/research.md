# Research: Routine-Request Guardrail False Positive & Persona Precedence Fix

No NEEDS CLARIFICATION markers — the spec's Clarifications session (2026-09-15) and Assumptions
section already resolved the one open question (persona-refinability scope). This file records the
concrete prompt-text decisions the plan's Technical Context references.

## 1. Guardrail rewrite: exhaustive criteria list, explicit routine-request carve-out

**Decision**: Replace the "Reconhecimento de intenção fora de prospecção" bullet's example-
introduced list ("... ex.: afirma já ser cliente, ...") with an exhaustive list introduced by
"apenas quando:" (only when:), and add one explicit sentence stating a low-complexity/preventive/
recurring/no-specific-problem new request is still a valid new opportunity that follows the normal
funnel. Exact replacement text is in `data-model.md`.

**Rationale**: `spec-preview.md` (`docs/kanban/ciclo 10/scout/29-routine-request-qualification-
guardrail-fix/spec-preview.md`) traced the false positive to the "ex.:" framing: introducing the
non-prospecting patterns as *examples* invites the model to generalize past them (a routine request
gets pattern-matched onto the "dúvida rápida não relacionada" example). FR-001's "MUST classify ...
only on objective criteria" requires an exhaustive, not illustrative, list — "apenas quando:" makes
that textually explicit. The added carve-out sentence directly implements FR-002.

**Alternatives considered**: Keeping "ex.:" and just adding more/better examples (rejected — doesn't
fix the root cause, a sufficiently novel phrasing of the same false-positive pattern could still slip
through; FR-001's "only on objective criteria" specifically calls for an exhaustive framing).
Removing the routine-request carve-out sentence and relying solely on the narrower exhaustive list to
implicitly exclude it (rejected — FR-002 explicitly requires the guardrail to *state* this, not just
avoid contradicting it; an implicit exclusion is exactly the kind of ambiguity that caused the
original bug).

## 2. Precedence rewrite: name the non-negotiables, name the one exception

**Decision**: Replace `custom_instructions_section`'s precedence sentence's blanket "Siga-as apenas
quando não conflitarem com o formato de resposta JSON ou com ... regras de segurança" (which treats
the entire `[Diretrizes de Segurança e Resposta]` block as one undifferentiated security-rule unit)
with a sentence that (a) names the actually non-negotiable guardrails — Anti-alucinação,
Anti-falsa-promessa, Confirmação de ação, plus the existing JSON-format/context-only requirements —
and (b) names "Reconhecimento de intenção fora de prospecção" as the one guardrail persona
instructions may refine, then states no other guardrail in the section may be changed. Exact
replacement text is in `data-model.md`.

**Rationale**: Directly implements FR-004 (distinguish non-negotiable guardrails from the one
persona-refinable guardrail, by name) and FR-005 (persona instructions overlapping the guardrail's
subject matter still take effect — "mesmo que pareçam ... tocar no mesmo assunto dessa diretriz"
removes the textual-overlap block `spec-preview.md` identified as the actual root cause). FR-006 is
preserved unchanged in spirit: instructions still yield to the named non-negotiables.

**Alternatives considered**: Making all 8 guardrail bullets persona-refinable (rejected — the spec's
2026-09-15 clarification session explicitly answered this: only the non-prospecting-intent bullet
becomes refinable, every other bullet stays fixed; FR-004 encodes that answer). Adding a per-bullet
refinability flag/config instead of a prose exception (rejected — FR-008 forbids any new schema/data
model for this feature; a hardcoded named exception in prompt text is the smallest change that
satisfies FR-004).

## 3. RuboCop heredoc exemption confirmed, no line-length mitigation needed

**Decision**: No backslash-continuation restructuring of either heredoc bullet.

**Rationale**: `.rubocop.yml:19-20` sets `Layout/LineLength: Max: 150` with no `AllowHeredoc`
override, and RuboCop's own default for that cop is `AllowHeredoc: true`. The file's existing
unmodified bullets (e.g. line 71, 1219 chars; line 78, 791 chars pre-edit) already exceed 150 chars
on a single physical heredoc line and are presumed rubocop-clean today (no `.rubocop_todo.yml` entry
for this file, no inline `rubocop:disable` comment in the file) — confirming the exemption applies.
The replacement bullets follow the same one-line-per-bullet heredoc convention.

## 4. FR-007 reactive safety net — explicitly zero changes

**Decision**: `Custom::Scout::ActionClassifierService` (`out_of_scope_commercial_request` action,
`custom/app/services/custom/scout/action_classifier_service.rb`) and its schema
(`action_classifier_schema.rb`) are not touched.

**Rationale**: FR-007 requires this reactive layer to continue operating unchanged; `spec-preview.md`
§"Fora de escopo" and the Assumptions section both explicitly exclude it. It already contains no
segment-specific vocabulary (`'out_of_scope_commercial_request': A solicitação do cliente está fora
do escopo comercial do assistente ...`) so it needs no genericization either.
