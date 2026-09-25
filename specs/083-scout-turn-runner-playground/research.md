# Phase 0 Research: Scout V2 Turn Runner and Qualification Playbook (Playground)

Brief 03 (`docs/kanban/ciclo 13/scoutv2/briefs/03-turn-runner-playground.md`) names a precise
scope list (§5) but leaves one load-bearing mechanism entirely implicit: how the **playground**
surface — today fully ephemeral/stateless (`Custom::Scout::PlaygroundRunner`, no DB conversation,
no DB opportunity) — satisfies FR-012/US1-Acceptance-#4 (persist the conversation's active
playbook + activation reason "using the routing decision produced for that same turn") when
`ScoutConversationState` is FK'd to a real `conversations` row, and US3 (multi-turn qualification
with router continuity keyed off `Opportunity#custom_attributes`, which only exists on a real,
persisted `Opportunity`). Every decision below resolves that gap plus the smaller mechanical
choices Phase 1 needs frozen before data-model.md/contracts can be written.

## D1 — Playground turns require a real, persisted sandbox `Conversation`

**Decision**: Under `scout_v2`, the playground surface no longer runs the v1 `PlaygroundRunner`'s
fully-ephemeral simulation. It resolves (lazily creating on first use, reusing thereafter) one
real `Conversation` per Scout, and `Custom::ScoutV2::TurnRunner` operates on it exactly like it
operates on a real inbox conversation — same `RoutingSnapshot::Builder`, same `Router`, same
`ScoutConversationState`, same `Opportunity`.

**Rationale**: Three independent requirements make an in-memory/fake opportunity structurally
impossible to satisfy:
- FR-012 + US1 Acceptance #4 require persisting `active_playbook`/`activation_reason` "using the
  routing decision produced for that turn," unconditionally, for "the new-execution-path turn" —
  no playground carve-out anywhere in spec.md. `ScoutConversationState.conversation_id` is
  `NOT NULL` + FK'd to `conversations` (brief 02, unchanged) — there is no column to write to
  without a real conversation row.
- US3's router activation is entirely state-driven: `opportunity_open` +
  `pending_required_fields` read `ctx.opportunity` (a real AR `Opportunity`, via
  `RoutingSnapshot::Builder#call`'s `conversation.active_opportunity`) and
  `ctx.pending_fields` (derived from `opportunity.custom_attributes`). A playground turn cannot
  exercise "router activates qualificacao by state" or "fields the customer supplies end up
  recorded... conversation not re-routed while collection is in progress" (US3 Acceptance #1/#3)
  without a real `Opportunity` whose `custom_attributes` genuinely accumulate turn over turn — v1's
  `ManageOpportunity#execute` playground branch returns a `"[Simulado]"` string and never writes a
  row, so it cannot support this.
- Spec line 9 itself frames the brief as "proving Briefs 01/02... end to end in a **real**
  playground turn" — "real" is doing exactly this work.

**Alternatives considered**:
- *Keep playground fully ephemeral; skip `ScoutConversationState` persistence for playground
  turns.* Rejected — directly contradicts FR-012's unconditional wording and SC-002's "100% of
  new-execution-path turns," and still leaves US3 unsatisfiable (no real `Opportunity` to
  accumulate `custom_attributes` across turns).
- *Give `RoutingSnapshot`/predicates an in-memory, non-AR "shadow opportunity."* Rejected —
  duplicates brief 01/02's already-delivered contract (`ctx.opportunity` typed as a real AR
  `Opportunity` everywhere) for one caller, contradicting spec.md Assumption #2 ("reuses the...
  routing decision... exactly as they are... neither changes how the routing decision is made").

## D2 — Sandbox conversation resolution: `Custom::ScoutV2::PlaygroundConversation`, zero new schema

**Decision**: New service `Custom::ScoutV2::PlaygroundConversation.for(scout)` lazily
find-or-creates, once per Scout, reused on every subsequent playground call for that Scout:
1. A dedicated `Contact` keyed by a deterministic `identifier` (`"scoutv2-playground-scout-#{scout.id}"`,
   scoped-unique per account — existing upstream column/validation, no new one).
2. A dedicated `Inbox` (`Channel::Api`, matching the fork's existing synthetic-inbox convention —
   `bin/seed-opportunities`, `lib/seeders/inbox_seeder.rb`, `search_test_data.rake`) +
   `ScoutInbox.create!(scout:, inbox:)` (needed for D6 below), created together with the contact
   on first use.
3. A `ContactInbox` linking the two, and the `Conversation` on it (found by
   `contact.conversations.where(inbox:).first`, created if absent).

No migration, no new column anywhere — resolution is a plain query chain off `Contact#identifier`,
which is already unique-per-account.

**Rationale**: Constitution II (smallest production-ready change) + Constitution I (additive,
isolated) — the fork already has this exact `Channel::Api` + `Inbox` + `ContactInbox` +
`Conversation` construction pattern in four places (seeders + specs' `quickstart.md`); reusing it
needs no schema change. A dedicated `identifier` avoids fragile name-matching and gives O(1)
account-scoped lookup via an existing unique index.

**Alternatives considered**:
- *New nullable `playground_conversation_id` FK column on `ichatr_scouts`.* Rejected — needs a
  migration for something a plain deterministic query already solves; violates "smallest change"
  for no added correctness.
- *One shared sandbox inbox/contact across all scouts in an account.* Rejected —
  `Inbox has_one :scout_inbox`/`has_one :scout, through: :scout_inbox` (`custom/app/models/
  custom/concerns/inbox.rb:7-8`) is a strict one-inbox-per-scout association; sharing one inbox
  across scouts would make `conversation.inbox.scout` resolve to whichever scout claimed it last,
  silently breaking `RoutingSnapshot::Builder`'s `scout` resolution for every other scout.

**Accepted consequence**: one continuous sandbox conversation per Scout — a tester who wants a
*fresh* qualification scenario reuses a different Scout or resets state via Rails console/Super
Admin; no in-product "reset playground" affordance is introduced (not named in brief 03 §5, and
adding one would be speculative scope per Constitution II). The synthetic contact/conversation is
also visible in the dev account's regular Contacts/Conversations lists like any other — acceptable
for the "conta de desenvolvimento primeiro" phase brief 03 explicitly targets (design.md §4.11);
no hiding mechanism is introduced.

## D3 — Playground turns never create real `Message` rows

**Decision**: `Custom::ScoutV2::TurnRunner` never persists an incoming or outgoing `Message` for
the playground surface. Conversation history for a playground turn comes from the frontend-supplied
`message_history` array (unchanged request contract — `PlaygroundMessagesController#permitted_message_history`)
added transiently to the `chat` object via `chat.add_message`, exactly like
`Custom::Scout::PlaygroundRunner#add_history_to_chat` already does. The reply is returned as JSON,
never dispatched through `Messages::MessageBuilder`.

**Rationale**: `Custom::ScoutListener#message_created` is the sole call site of
`Custom::Scout::ProcessMessageJob.enqueue_debounced` (confirmed: only reference in the codebase)
and fires on **any** incoming, public message on an inbox with an enabled Scout attached —
regardless of channel type (055-scout-cross-channel-activation removed the WhatsApp-only gate).
Since D2's sandbox inbox is deliberately `ScoutInbox`-linked (D6), a real incoming `Message`
created on it would fire this listener and re-enqueue a second, async, uncontrolled turn on the
same conversation a few seconds later — a functional double-dispatch bug, not a hypothetical one.
Never creating `Message` rows for playground sidesteps this entirely, with no need to special-case
the listener or unlink the sandbox inbox. It also costs nothing: router continuity/US3's
"not re-routed" and "fields accumulate" requirements depend only on the real, persisted
`Opportunity`/`ScoutConversationState` (D1), never on `Message` rows — the model's own turn-to-turn
memory is served identically to v1 by the frontend's resent `message_history`.

**Alternatives considered**:
- *Persist real messages, unlink the sandbox inbox from `ScoutInbox` to dodge the listener.*
  Rejected — trades one problem for another: `RoutingSnapshot::Builder#call`'s `scout =
  conversation.inbox&.scout` would resolve `nil`, breaking `ctx.scout`-dependent stage-role/
  pending-fields computation, which would require widening brief 02's `Builder` signature —
  contradicts spec.md Assumption #2 ("reuses... exactly as they are").
- *Persist real messages, keep the listener linked, rely on `conversation_pending?` as a safety
  net.* Rejected — depends on incidental conversation-status timing (`determine_conversation_status`/
  `inbox.active_bot?`) to accidentally no-op the duplicate job; too fragile to be the actual
  safety mechanism for a correctness bug.

## D4 — `TurnRunner` unified interface across both surfaces

**Decision**: `Custom::ScoutV2::TurnRunner.new(scout:, conversation:, message:, message_history: nil).perform`
→ `{ reply: String, tool_calls: Array<Hash> }`. `message_history: nil` (the inbox default) means
"derive from `conversation.messages`" (same query `AgentRunner#conversation_messages` already
uses); an explicit array (always supplied by the playground dispatch point, per D3) is used
verbatim and the DB is never queried for history. Dispatching the returned reply is the caller's
job, not `TurnRunner`'s:
- `ProcessMessageJob`'s v2 branch persists it via `Messages::MessageBuilder` and increments
  `responses_consumed` (mirrors `AgentRunner#dispatch_outgoing_reply`).
- `PlaygroundMessagesController`'s v2 branch renders `{ reply:, tool_calls: }` directly — the
  exact JSON shape the frontend (`ScoutPlaygroundChat.vue:53-55,150-157`) already reads, so no Vue
  change is needed.

**Rationale**: Matches the brief's own framing — "one code path, two dispatch points" — while
keeping "what happens to the reply" (a real message vs. an HTTP response) as the one genuine
difference between surfaces, mirroring exactly how v1 already splits this between `AgentRunner`
and `PlaygroundRunner`. Keeps `TurnRunner` a single class with a single spec suite (no
InboxTurnRunner/PlaygroundTurnRunner duplication) satisfying US1/US2's "one code path" framing
literally.

## D5 — Prompt assembly: playbook body verbatim, or a minimal static fallback

**Decision**: System instructions = `playbook.body.strip` when the router selects one, otherwise a
short static fallback constant (no dynamic sections). No Identity/Communication/Memory/Safety/
Escalation/playbook-index layer this phase — those are brief 04/05's `Custom::ScoutV2::Instructions`
mechanism, explicitly out of scope here (brief 03 §6, spec Edge Cases #1).

**Rationale**: FR-007 ("contains that playbook's full step-by-step body"), FR-008 ("MUST NOT
include the existing path's fixed always-on guideline block"), Edge Case #1 ("minimal baseline
prompt" when nothing matches). Nothing in brief 03's scope or spec's FRs asks for typed
Identity/Communication sections — inventing them now would be scope creep the later briefs already
own.

## D6 — `pending_fields` surfaced in-prompt (data, not a new behavior branch)

**Decision**: `TurnRunner` appends a short, dynamically-generated "campos pendentes" listing —
derived the same way `RoutingSnapshot#pending_fields` already computes it (`attribute_key` →
`CustomAttributeDefinition#attribute_display_name`/`attribute_description`, same formatting
primitive as `FunnelSectionBuilder#format_attribute_definition`, reimplemented locally rather than
reused — see rationale) — immediately after the static `qualificacao.md` body, only when that
playbook is active and `ctx.pending_fields` is non-empty.

**Rationale**: `custom/playbooks/qualificacao.md` is one file shared by every account (design
decision 2); it cannot hardcode a specific account's configured qualification fields. Without
*some* per-account field list in the prompt, the model has no way to know what to ask about,
making US3 Acceptance #2 ("the information the customer supplies ends up recorded through
`manage_opportunity`") and Acceptance #4 ("observed qualification behavior equivalent to v1's")
unachievable — v1's `FunnelSectionBuilder` supplies exactly this today. This is *not* the
"unsatisfied_flags... does not use it to change turn behavior" mechanism spec.md's Assumptions
section defers (that's about a routing/exit decision branching on the flag, e.g. skipping
selection or forcing an exit) — appending read-only field-name context the playbook's own
procedure needs to execute doesn't change *which* playbook/tools/exit path runs, only what the
model is told to ask about. `FunnelSectionBuilder` itself is not reused directly — it is a v1 class
mixing in stage-funnel guidelines (auto-stage-transition rules, qualified/unqualified handling)
that brief 03 explicitly excludes from v2 (those become Ruby-decided exits in brief 05); importing
it would drag v1 behavioral text into the v2 prompt FR-008 forbids.

## D7 — Tool catalog: static per-name map, `search_knowledge_base` always present

**Decision**: `Custom::Scout::Tools::SearchKnowledgeBase` is always chained (FR-009's "one
read-only knowledge-lookup tool"). Additional tools come from `playbook.tools.map { |name|
TOOL_CLASSES.fetch(name) }`, a small frozen `Hash` constant inside `TurnRunner`
(`{ 'manage_opportunity' => Custom::Scout::Tools::ManageOpportunity }` — the only entry this
phase's one playbook needs; brief 06 extends the map, not the mechanism). `move_opportunity_stage`,
`handover_to_human`, `call_custom_api` are never referenced, satisfying FR-010 structurally (they
are simply never constructed, not filtered out at runtime).

**Rationale**: Matches brief 01's `Validator`'s own `requires`/tool-reference validation pattern
(name → registered class) already established for predicates/capabilities; smallest mechanism that
supports exactly one playbook today and trivially extends for brief 06 without redesign.

## D8 — Tools constructed with `playground: false` in both v2 surfaces

**Decision**: `Custom::Scout::Tools::ManageOpportunity.new(@scout, @conversation, playground: false)`
regardless of surface — D1/D2 make the "playground" conversation a real, persisted one from the
tool's own perspective, so its existing `playground?` no-op branch (`"[Simulado]..."`, no DB write)
is simply never reached by v2. Zero diff to `custom/app/services/custom/scout/tools/**` — brief 03
§5 calls this "tool available to v2 in a scoped version," not a new tool variant.

**Rationale**: Keeps the "services undiffed" boundary (brief 03 §6) as tight as possible — only
`AgentRunner`/`ResponseAuditor`/`SystemPromptsService` are explicitly named untouched, but nothing
in brief 03 asks for a *new* v1 tool no-op branch either; reusing the existing "real write" branch
via `playground: false` needs no tool-file change at all.

## D9 — No `.with_schema`; plain-text reply

**Decision**: `TurnRunner` calls `chat.ask(message)` with no `.with_schema(...)`, taking
`response.content` as the reply text directly (same as `PlaygroundRunner`, unlike `AgentRunner`'s
`.with_schema(Custom::Scout::ResponseSchema)` + `{response:, reasoning:}` JSON parsing).

**Rationale**: `ResponseSchema`'s only consumer of the split was the auditor-adjacent `reasoning`
field for logging (design.md §4.6: "`ResponseSchema` perde `reasoning`, que hoje só alimenta log")
— v2 has no auditor and no reasoning-logging requirement. `ResponseSchema` is a v1 file
(`custom/app/services/custom/scout/response_schema.rb`), not named in brief 03's scope; reusing it
would import a v1-shaped contract for no behavior v2 needs.

## D10 — Infra fail-safes (quota/API key) reused, behaviorally, from `AgentRunner`'s pattern

**Decision**: `TurnRunner` replicates `AgentRunner#pre_call_checks_pass?`'s exact check
(`scout.quota_available? && ScoutAccountConfig.find_by(account_id:)&.api_key.present?`) before
calling the model; on failure it calls `Custom::Scout::HandoffService.new(scout:,
conversation:).perform(message: ...)` directly (a shared infra service, not one of the three
undiffed v1 files) — for the inbox surface only. Playground turns render the failure reason as an
error response instead of triggering a real handoff (mirrors `PlaygroundRunner`'s
`rescue StandardError` → `{ reply: "Erro ao executar simulação: ...", error: }` shape — a
sandbox-conversation handoff would be a confusing, inbox-workflow-only side effect for a tester,
and design.md §508-509 only requires the fail-safe to remain for genuine production/system
failure, not for a synthetic testing conversation).

**Rationale**: design.md explicitly keeps infra fail-safes in v2 ("Permanecem os fail-safes de
infraestrutura... são falha de sistema, não compensação de comportamento") — this is not part of
the removed auditor/classifier stack.

## D11 — State-write rule: only on fresh activation/interruption, matching brief 02's own framing

**Decision**: After `decision = Router.call(ctx, catalog)`, `TurnRunner` calls
`ScoutConversationState.for_conversation(conversation).record_state_activation!(decision.playbook.name)`
only when `decision.playbook.present? && decision.playbook != ctx.active_playbook` (fresh
activation or priority interruption — a new/changed name). When `decision.playbook` already equals
`ctx.active_playbook`, or is `nil`, no write happens this turn (state already reflects the current
decision, or there is nothing to activate by state this phase — no `open_playbook` trigger
mechanism exists yet, brief 04).

**Rationale**: brief 02's own delivered contract (`data-model.md` for 082: "`Router` never...
distinguishes 'continuing unchanged' from 'freshly activated'... a caller that already has
`ctx.active_playbook` can tell the two apart itself") names this exact comparison as the caller's
job — brief 03 is "the first place that wires 'the router decided X' together with 'X gets
persisted'" (spec.md Assumption #2), i.e. this wiring **is** brief 03's contribution, not a
deviation from it. Still satisfies FR-012/US1-#4 ("persisted exactly as the turn's routing
decision determined") — an unchanged decision is correctly represented by an unchanged row.

## D12 — Feature flag: `scout_v2`, mirrors `erp_integration`'s MANIFEST entry exactly

**Decision**: Append to `config/features.yml` (end of file, per its own header comment):
```yaml
- name: scout_v2
  display_name: Scout V2
  enabled: false
  column: feature_flags_ext_1
```
plus one `bin/sync-custom-module-hooks` MANIFEST entry (same file/anchor/insert shape as the
existing `erp_integration` entry, `bin/sync-custom-module-hooks:207-209`) so the bit position
survives future upstream syncs (Constitution I). Checked via `account.feature_enabled?('scout_v2')`
— identical call pattern to `captain_integration_v2` throughout `enterprise/`. No
`app/javascript/dashboard/featureFlags.js` entry — nothing in the frontend reads this flag (no new
route/page/component is gated by it; Super Admin already renders every `features.yml` entry as a
checkbox generically, design.md §4.11).

**Rationale**: Named explicitly in brief 03 §5; directly mirrors the two sibling flags
(`scout`, `erp_integration`) already on `feature_flags_ext_1`.

## D13 — Two dispatch points, minimal branch, no gate duplication

**Decision**: `ProcessMessageJob#process_debounce` and `PlaygroundMessagesController#create`
each gain a single `if @scout.account.feature_enabled?('scout_v2')` branch selecting
`Custom::ScoutV2::TurnRunner` vs. the existing v1 runner — no other line in either file changes.
`PlaygroundMessagesController`'s v2 branch additionally calls
`Custom::ScoutV2::PlaygroundConversation.for(@scout)` (D2) to obtain the conversation `TurnRunner`
needs; `ProcessMessageJob` already has one.

**Rationale**: Literally brief 03 §5 ("Branch de despacho nos dois únicos pontos... Sem a flag, os
dois seguem exatamente como hoje") and spec.md Assumption #7. No new gate is added at either
point — debounce/audience/quota/API-key gates upstream of the branch are unchanged (design.md
§4.11 "os porteiros... são os mesmos nas duas engines").

## D14 — `unsatisfied_flags` trace metadata, computed not persisted, this phase

**Decision**: `TurnRunner`'s `instrumentation_params[:metadata]` includes `playbook:`,
`activation_reason:`, and `unsatisfied_flags:` (derived read-only from `ctx.pending_fields` +
`playbook.requires` vs. `ctx.satisfied_capabilities` — both already computed by
`RoutingSnapshot::Builder`, brief 02, unchanged). The `ichatr_scout_conversation_states.
unsatisfied_flags` jsonb column (already created, brief 02) is **not** written by this phase — it
stays reserved, exactly as 082's data-model.md already documented ("created but never
populated/read by this phase's code" — that statement now transfers one phase later, to brief 03,
and remains true here too: it is Langfuse metadata only, never a DB write).

**Rationale**: spec.md Assumptions: "this feature does not introduce a new source of that data and
does not use it to change turn behavior; it is trace data only." US2 Acceptance #2 requires the
trace to carry playbook + activation reason (not `unsatisfied_flags` specifically, but design.md
§4.9 names it as part of the same metadata payload) — SC-002 ("100% of turns... answerable from
trace alone").
