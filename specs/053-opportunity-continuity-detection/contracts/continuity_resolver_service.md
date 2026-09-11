# Contract: `Custom::Opportunities::ContinuityResolverService`

Internal Ruby service contract — the single interface both deal-creation call sites depend on.
Any future third call site (if one is ever added) MUST also go through this contract rather than
reimplementing the funnel, per FR-008's "no rule-specific shortcut" requirement.

## Interface

```ruby
Custom::Opportunities::ContinuityResolverService.new(
  account: Account,                    # required
  contact: Contact,                    # required
  declared_opportunity_id: nil         # optional, Integer or nil
).call
# => ContinuityDecision (see data-model.md)
```

`.new(keyword_args).call` matches house style for services in this namespace family — see
`Custom::Scout::OpportunityStageTransitionService#call` and
`Custom::AutomationRules::OpportunityConditionsFilterService#perform`/`Custom::Scout::HandoffService#perform`
(all keyword-arg `initialize` + a single public `call`/`perform` method, never `resolve`).

To stay under this repo's RuboCop `Metrics/CyclomaticComplexity`/`Metrics/AbcSize` thresholds
(`.rubocop.yml`: `AbcSize` Max 26, `CyclomaticComplexity`/`PerceivedComplexity` Max 11) and match
the extraction style already used by the closest analogs
(`OpportunityStageTransitionService`, `OpportunityConditionsFilterService` — one private method per
branch/outcome rather than one large conditional), the implementation should extract one private
method per funnel outcome (e.g. `decision_for_no_candidates`, `decision_for_declared_match`,
`decision_for_ambiguous`) plus a `fetch_candidates` helper, rather than a single branchy `call`
method.

## Preconditions

- `account` and `contact` MUST be persisted records; `contact.account_id` MUST equal `account.id`
  (defense-in-depth scoping — see research.md's "never busca sem escopo" rationale).
- `declared_opportunity_id`, when present, is treated as untrusted input (may originate from an LLM
  tool call) and MUST be validated against the real candidate set — never trusted at face value
  (spec FR-004).

## Postconditions / behavior (see data-model.md's funnel table for the full decision matrix)

- Never mutates any record. Purely a decision/query service — the caller (not the resolver) is
  responsible for actually creating or updating the `Opportunity`, and for writing the ambiguity
  private note.
- `candidates` on the returned `ContinuityDecision` is always the true, freshly-queried open-deal
  set for the contact at call time (no caching) — this is what makes the concurrency edge case in
  the spec safe: a second near-simultaneous call re-queries rather than trusting a stale read.
- `reason` is always populated (even for `:create_new` and `:reuse`), so every outcome is
  traceable (FR-010), not only the ambiguous ones.

## Callers and how each uses it

### `Custom::Scout::Tools::ManageOpportunity#execute`

- Passes `declared_opportunity_id:` from the tool's new `opportunity_id` parameter (see
  `manage_opportunity_tool.md` in this directory).
- On `:create_new` → proceeds with existing create flow.
- On `:reuse` → uses `decision.opportunity` as the target for the existing update flow (replacing
  today's `Opportunity.find_by(origin_conversation_id: conversation.id)` lookup).
- On `:ambiguous` → does not create or update any `Opportunity`; creates a private note (via
  `Messages::MessageBuilder`, same pattern as `Custom::Scout::Tools::CreatePrivateNote`) using
  `decision.reason`, and returns a tool result message indicating no action was taken — the
  conversation continues normally otherwise (per User Story 2).

### `Custom::AutomationRules::ActionService#create_opportunity`

- Calls `resolve` with `declared_opportunity_id` omitted (always `nil`) — a rule has no mechanism
  to declare a specific match (per the `/speckit-clarify` resolution).
- On `:create_new` → proceeds with the existing create flow (unchanged from today, minus the
  narrower `origin_conversation_id`-only check it replaces).
- On `:ambiguous` (reachable whenever the contact already has ≥1 open deal, i.e. every case except
  zero candidates) → does not create any `Opportunity`; adds a private note on `@conversation`
  using `decision.reason`, mirroring the same private-note mechanism the rest of
  `Custom::AutomationRules::ActionService`/`OpportunityActionService` already uses
  (`add_private_note`).
- `:reuse` is not reachable from this call site (see data-model.md).
