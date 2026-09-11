# Research: Scout Contact Identity Detection

No `NEEDS CLARIFICATION` markers remain in the Technical Context — the source design document
(`docs/kanban/ciclo 10/scout/19-contact-identity-and-conversation-labeling/spec81.md`) already
resolved every open question through prior brainstorming with the operator. This document records
the decisions and the verification performed against the current codebase state.

## Decision: Placeholder-name detection is shape-based (regex), not a word list

**Rationale**: The generator (`Haikunator.haikunate(1000)` in `app/builders/contact_inbox_with_contact_builder.rb:63`)
produces names of the form `adjective-noun-number` where the number is `0`–`999`. A regex over the
*shape* (`\A[a-z]+-[a-z]+-\d{1,3}\z`) survives Haikunator's dictionary being updated by a future gem
bump, and both real evidence samples (`empty-meadow-50`, `polished-forest-561` — note: the second
example has 3 digits, still within `0-999`... actually `561` fits `\d{1,3}` regardless of the
`1000` cap wording) match it. Real two-word names (`Maria Silva`, space-separated, capitalized) and
other channels' handles (`primeirazinha11234`, no hyphen) do not match.

**Alternatives considered**:
- A closed word list mirroring Haikunator's adjective/noun dictionaries — rejected: brittle against
  gem updates, and the dictionaries are large/internal to the gem, not meant to be duplicated.
- Flagging by "no explicit name given" state instead of pattern-matching the stored value — rejected:
  there is no separate "identified" boolean on `Contact` today; introducing one would touch core
  schema/model, violating Constitution Principle I (upstream compatibility, smallest change).

## Decision: Deterministic detection only for the website-widget channel; judgment-based guardrail elsewhere

**Rationale**: The placeholder-generation mechanism (`Haikunator`) is only invoked in
`ContactInboxWithContactBuilder`, which is the path used for **new** website-widget contacts
without a supplied name. Other channels (WhatsApp, Instagram, etc.) populate `contact.name` from
the channel's own profile data — there is no equivalent, reliable system-level signal there, so a
regex would either miss real handles (false negatives) or, worse, misclassify legitimate real names
that happen to resemble the shape (false positives). This mirrors the precedent already set in
Phase 18 (guardrails work) of leaving channel-profile judgment calls to the model rather than
hardcoding channel-specific pattern rules in code.

**Alternatives considered**:
- Extending the regex to also flag common handle shapes (e.g. `name+digits`) across all channels —
  rejected: increases false-positive risk on real names with numbers (e.g. usernames people
  legitimately go by), and the spec explicitly scopes deterministic detection to the site channel
  only.

## Decision: No new tool — reuse existing `update_contact` tool for persistence

**Rationale**: `Custom::Scout::Tools::UpdateContact` (`custom/app/services/custom/scout/tools/update_contact.rb`)
already accepts a `name` param and persists it to the contact via `target_contact.save!`. The
feature only needs to make Scout *aware* that it should ask and then call this existing tool with
the answer — no new tool surface, no new param.

**Alternatives considered**: A dedicated `set_real_name` tool — rejected as unnecessary duplication
of `update_contact`'s existing capability (violates Constitution Principle II, smallest change).

## Decision: Prompt changes land in `Custom::Scout::SystemPromptsService` only

**Rationale**: This is the single existing place that assembles per-contact context
(`context_section`) and channel-agnostic guardrails (`guardrails_section`) into the system prompt
given to the LLM (`custom/app/services/custom/scout/system_prompts_service.rb`). Both target
insertion points already exist as private methods in this class today; no new prompt-assembly
mechanism is needed.

**Verification against current code** (as of this plan): `context_section` currently builds the
contact line inline as `"Contexto do Contato:\n#{@contact.to_llm_text}"` without any placeholder
check (`system_prompts_service.rb:85`) — confirms the gap described in the spec is still present
and unaddressed. `guardrails_section` currently has no "Identidade do contato" bullet
(`system_prompts_service.rb:66-79`) — confirms the second insertion point is clean/available.

## Decision: FR-011 (never ask in a handoff-ending turn) is already covered by prompt content, but the new instruction needs a short explicit subordination reference

**Finding**: The 2026-09-02 clarification session added FR-011 ("Scout MUST NOT ask the identity
question in any turn whose response ends in a handoff"). Re-reading the current
`custom/app/services/custom/scout/system_prompts_service.rb`, this rule already exists generically,
twice over:
- `guardrails_section`'s "Fallback para humano" bullet (line 76): "Sempre que um turno terminar em
  transferência ... nunca faça perguntas ao transferir."
- `handoff_closing_reminder_section` (lines 141-146): "sua resposta final não pode conter nenhuma
  pergunta ao cliente, mesmo que pareça natural continuar perguntando algo" — deliberately repeated
  close to the response-format instructions per its own comment, precisely because a single
  system-prompt bullet read many messages earlier isn't salient enough on its own.

A **third**, independent layer confirmed by the 2026-09-02 alignment audit: `ResponseAuditor#evaluate_action`
(`custom/app/services/custom/scout/response_auditor.rb:45-56`) can trigger handoff via
`ActionClassifierService` outside the model's own tool-calling. On that path, `execute_handoff` calls
`HandoffService#perform` **without** `message:`, so `send_public_handoff_message`
(`custom/app/services/custom/scout/handoff_service.rb:35-40`) always sends the fixed
`I18n.t('conversations.scout.handoff')` sentence — any model-generated text (including an identity
question) is discarded by code, not by prompt discipline. This path is safe by construction,
independent of what the prompt says.

Both prompt-based rules are unconditional and channel-agnostic already, and neither is scoped to any
particular question topic — so a newly added "ask for the name" instruction automatically falls
under "nenhuma pergunta ao cliente" without needing its own handoff carve-out, *in principle*.

**Revised decision (post-audit)**: Do not duplicate the full no-question-on-handoff rule inside the
new identity-question instruction — the audit confirms this stays correct and unnecessary
duplication is still to be avoided. However, the alignment audit surfaced a documented production
incident of exactly the failure mode this interacts with — `docs/kanban/ciclo 10/scout/20-automatic-handoff-reevaluation/spec80.md:44-46`
records a real "asked a question and transferred in the same turn" bug fixed on 2026-08-30, in a
codebase that (before this feature) had no comparably salient competing instruction pulling the
model toward asking a question near a handoff decision. Because FR-012 deliberately *increases* the
salience of "ask this, with priority" right at the point where a handoff decision is often made
(post-qualification), the two new insertion points (`contact_context_section` warning and the
guardrails bullet) MUST each include one short clause explicitly subordinating the ask/priority
instruction to the handoff rule (e.g. "...exceto quando este turno for terminar em transferência,
caso em que a regra de handoff abaixo prevalece") — a cross-reference, not a restatement of the
full rule. This is deliberate redundancy accepted as a targeted mitigation for a known regression
class, not the general case Constitution Principle II counsels against duplicating.

**Alternatives considered**:
- No cross-reference at all (original pre-audit decision) — rejected after the audit: the documented
  2026-08-30 incident plus FR-012's deliberate salience increase raises this from a
  theoretical/redundant concern to a specific, evidenced regression risk worth one extra clause.
- Duplicating the full no-question-on-handoff rule text in both new insertion points — rejected:
  still unnecessary given the rule is already stated twice elsewhere; a short cross-reference gets
  the salience benefit without tripling the maintenance surface.

## Decision: FR-012 (priority over qualification) and the first-response immediacy rule need explicit new wording in both insertion points

**Finding**: Unlike FR-011, neither "ask the identity question as early as possible — ideally in the
first response" (FR-003, FR-006) nor "prioritize it over a pending qualification question" (FR-012)
exists anywhere in the current prompt. The closest existing rule,
`guardrails_section`'s "Ritmo e condução da conversa: Faça no máximo uma pergunta por resposta",
caps Scout at one question per turn but has no ordering/priority logic between competing candidate
questions — today that ordering is left entirely to model judgment.

**Decision**: Both insertion points must carry explicit language establishing:
1. Ask as early as possible, ideally in the very first response to the contact (not deferred to
   "an appropriate point").
2. When the identity question and a pending qualification question would both be candidates for a
   turn's single question slot, ask the identity question first.

This applies to the site-specific conditional warning in `contact_context_section` (FR-003) and the
new guardrails bullet for other channels (FR-006/FR-012) — both need the same immediacy + priority
language, since FR-012 governs the "already asked once" case as much as the first-turn case.

**Alternatives considered**: Adding a separate, third guardrails bullet solely for the
priority-ordering rule — rejected: the ordering rule only makes sense attached to the "ask for the
name" instruction itself (it has no meaning standalone), so folding it into the existing two
insertion points is simpler and keeps the instruction self-contained where the model reads it.

## Decision: FR-013 (identity question exempt from the "no questions outside configured fields" guidance) needs explicit wording

**Finding**: The 2026-09-02 alignment audit found a second concrete conflict:
`Custom::Scout::SystemPrompts::FunnelSectionBuilder#build_funnel_guidelines_lines`
(`custom/app/services/custom/scout/system_prompts/funnel_section_builder.rb:46-49`) instructs "Não
invente perguntas adicionais fora dos campos configurados". `funnel_section` is assembled
immediately after `context_section` in `SystemPromptsService#build`
(`system_prompts_service.rb:19-28`, `funnel_section` right after `context_section`) — so the model
reads "ask for the name, with priority" and then, in the very next section, "don't invent questions
outside the configured fields." The identity question is not itself a configured funnel field, so
without an explicit exemption the model could reasonably read these as conflicting and suppress the
identity question.

**Decision**: Both new insertion points (`contact_context_section` warning and the guardrails
bullet) must state plainly that the identity question is not one of the account's configured
qualification fields and is not subject to that limit. Captured as spec.md FR-013 (added
2026-09-02 post-audit).

**Alternatives considered**: Editing `FunnelSectionBuilder`'s guidance text itself to carve out an
exception — rejected: that method has no knowledge of contact identity at all today, and teaching it
about a concern that belongs to `SystemPromptsService`/`ContactIdentityService` would spread this
feature's logic across two unrelated builders for no benefit; stating the exemption at the point
where the identity question itself is introduced is simpler and keeps the instruction
self-contained (same reasoning already applied to the priority-ordering decision above).

## Decision: Add one automated spec asserting the identity instructions and the handoff reminder coexist correctly

**Finding**: The alignment audit noted that `ClaimConsistencyService`/`ActionClassifierService` do
not verify question pacing/ordering, and no automated spec today renders `context_section` (with a
placeholder contact) and `handoff_closing_reminder_section` together in the same prompt to assert
the new identity text doesn't visually or semantically crowd out the handoff instruction. The
`quickstart.md` "4c" scenario covers this only as a manual/semi-automated `PlaygroundRunner` smoke
test (LLM-dependent, non-deterministic).

**Decision**: Add a deterministic example to `custom/spec/services/custom/scout/system_prompts_service_spec.rb`
asserting that a prompt built for a placeholder-named contact contains both the identity warning
text and the unmodified, still-present handoff-closing-reminder text — a plain string-presence check
on the rendered prompt, not a behavioral/LLM test. This is cheap, deterministic, and catches any
future edit that accidentally drops or reorders one section when touching the other, independent of
the `quickstart.md` manual scenario. Reflected as a task item at `/speckit-tasks` time.

**Alternatives considered**: Relying solely on the existing `quickstart.md` manual/PlaygroundRunner
scenario — rejected: it depends on a live LLM call and is explicitly documented as non-deterministic
("smoke test, not a determinism guarantee"), so it cannot be part of the fast, deterministic
regression suite the way a plain prompt-content assertion can.

## Decision: New service isolated under `Custom::Scout` namespace, not touching `Contact`

**Rationale**: Constitution Principle I requires fork-specific logic to live in an isolated
location and avoid editing/coupling to core files beyond read-only attribute access. A stateless
class-method service (`Custom::Scout::ContactIdentityService`, mirroring the existing style of
`Custom::Scout::EmbeddingConfig`) satisfies this: it reads `contact.name` but adds no method to
`Contact` itself, and is referenced only from within `Custom::Scout::SystemPromptsService`.

**Alternatives considered**: Adding a `placeholder_name?` instance method directly on `Contact` —
rejected: would require editing the core `app/models/contact.rb` file, which Principle I prohibits
outside of an extension point (`prepend_mod_with`), and there is no existing extension point for
this narrow, Scout-only concern.

## Decision: `PlaygroundRunner` needs a small, optional `contact:` param to support the spec's own replay verification

**Finding**: The spec's "Verificação comportamental" test plan calls for replaying a real
conversation via `Custom::Scout::PlaygroundRunner` to confirm Scout now asks for the name. However,
as of this plan, `PlaygroundRunner#build_system_instructions`
(`custom/app/services/custom/scout/playground_runner.rb:71-76`) calls
`Custom::Scout::SystemPromptsService.build` **without** a `contact:` argument at all — confirmed by
tracing its only caller, `Api::V1::Accounts::Scouts::PlaygroundMessagesController#create`
(`custom/app/controllers/api/v1/accounts/scouts/playground_messages_controller.rb:14-18`), which
never supplies one either. `SystemPromptsService#context_section` skips the entire contact-context
block when `@contact` is `nil` (`if @contact.present?`), so today's playground can never exercise
this feature's contact-context warning at all, regardless of this change.

**Decision**: Add an optional `contact:` keyword param to `Custom::Scout::PlaygroundRunner.new` and
forward it to `SystemPromptsService.build`. Defaults to `nil`, so all existing playground behavior
(text-only simulation, no contact) is unchanged when omitted — purely additive, matching
Constitution Principle II (smallest change) while making the spec's own verification step actually
executable. The controller does not need to change for this feature (no UI to pick a contact) —
this wiring is for the Ruby-level replay/smoke test described in the spec, invokable directly (e.g.
via `rails runner`/console or a spec), not through the HTTP playground endpoint.

**Alternatives considered**: Skip wiring `contact:` into `PlaygroundRunner` and treat the spec's
replay verification as aspirational/manual-only — rejected: the spec explicitly lists this as part
of "Testes", and the fix is a two-line, backward-compatible addition; leaving it out would silently
make a stated verification step impossible to run.

## Decision: No enterprise-overlay changes needed

**Rationale**: Confirmed via `grep -rln "Custom::Scout" enterprise/` — zero matches. Scout is a
fork-only (`custom/`) feature with no Enterprise counterpart or override point referencing it.
Constitution Principle V (Dual-Tree Awareness) is satisfied with no action required.

## Addendum: 2026-09-02 `/speckit-analyze` remediation

A cross-artifact analysis pass (spec.md/plan.md/tasks.md) after `/speckit-tasks` found one HIGH and
one MEDIUM finding, both remediated in `data-model.md` and `tasks.md` directly (no new decision
entry needed, since both are refinements of decisions already recorded above):

- **COV1 (HIGH)**: FR-005 ("ask at most once, regardless of channel") was explicit in the
  non-website guardrails bullet's design from the start, but missing from the site-specific
  `contact_context_section` warning's described content — an asymmetry, since the warning
  re-injects every turn the placeholder shape still matches, so an unanswered ask had no textual
  guard against repeating. Fixed by adding clause (f) to the warning's Rule in `data-model.md` and
  to `tasks.md` T004/T005, plus a new behavioral scenario (`quickstart.md` §4d, `tasks.md` T010).
- **UND1 (MEDIUM)**: FR-008 ("must not modify the contact's name") was true by construction (the
  classifier never assigns anything) but had no explicit spec assertion pinning it against a future
  regression. Fixed by adding an explicit `not_to change(contact, :name)`-style assertion to
  `tasks.md` T002.

Two LOW findings (FR-003 wording ambiguity re: FR-013's non-suppressing role; a reminder to wrap
long heredoc lines for the 150-char RuboCop limit) were also applied — see `spec.md` FR-003 and
`tasks.md` T004/T013.
