# Phase 0 Research: Unified Card Click & History Links

## Unknown 1 — Does opening a conversation via the existing drawer path already enforce Chatwoot's conversation access policy? (resolves FR-010)

**Decision**: Yes. No new enforcement logic is needed for the "opening" path itself.

**Rationale**: `useConversationDrawer.js`'s `processConversation(id)` falls back to
`ConversationApi.show(id)` → `GET /api/v1/accounts/:accountId/conversations/:id`, which is handled by
`Api::V1::Accounts::ConversationsController#conversation` (`Current.account.conversations
.find_by!(display_id: params[:id])` + `authorize @conversation, :show?`). This already runs the real
`ConversationPolicy` (admin/agent-bot/inbox-membership/team-membership, with the enterprise policy
prepended via `ConversationPolicy.prepend_mod_with`), raising `Pundit::NotAuthorizedError` (401) or
`ActiveRecord::RecordNotFound` (404), both caught by the app's standard exception handling. A user
without access to a given conversation cannot load it through this drawer today, regardless of
entry point (active-conversation card click or a history link) — this feature reuses that path
unchanged for FR-001, FR-002, and FR-006.

**Alternatives considered**: Re-implementing an access check on the frontend before navigating —
rejected as redundant and a duplicate-source-of-truth risk; the backend call is already
authoritative and already runs on every navigation.

**Frontend gap noted**: the drawer currently collapses both 401 and 404 into one generic
"not found" state (`OpportunityConversationDrawer.vue`, `OPPORTUNITIES.DETAIL.NOT_FOUND`). This is
acceptable and requires no change — FR-006a specifies the same "not accessible" treatment for both
an unresolvable and an unauthorized conversation, so no differentiation is needed post-click either.

## Unknown 2 — Can the "disable the link upfront" + "show current status" requirements (FR-006a, FR-011) be satisfied from data already loaded client-side, or is new data exposure required?

**Decision**: New data exposure is required, but it is a small, additive enrichment of an existing
fork-owned endpoint response — not a new endpoint, and not new business logic (it reuses the
existing `ConversationPolicy`).

**Rationale**:
- `Opportunity#associated_conversations_json` (`custom/app/models/custom/concerns/opportunity_conversation_management.rb`)
  already includes live `status` per conversation, and is already loaded client-side as
  `opportunity.associated_conversations` — but it is scoped to `opportunity_conversations` **currently**
  linked to the opportunity. A `conversation_detached` history entry, by definition, describes a
  conversation that may no longer be linked, so it will not reliably appear in this array — using it
  as the sole source would silently break the detached-conversation case the spec explicitly calls
  out (User Story 2, Scenario 3/6).
- Even where a conversation is still linked, `associated_conversations_json` exposes `inbox_id` but
  not `team_id`, so the current user's access could not be fully replicated client-side (team-based
  access, and the admin/agent-bot bypasses in `ConversationPolicy`, would require duplicating policy
  logic in JS — a maintenance and correctness risk against Constitution Principle I, which prefers
  reusing the authoritative check over reimplementing it).
- The activity log's own stored metadata (written in `opportunity_conversation.rb` and
  `opportunity_conversation_management.rb`) only ever persists `conversation_id`/`conversation_display_id`
  (+ transfer-specific fields) at write time — never status, since status is explicitly required to be
  the conversation's *current* state (per spec Assumptions), not a historical snapshot.

**Chosen approach**: Enrich the existing `GET .../opportunities/:opportunity_id/activities` response
(`Api::V1::Accounts::Opportunities::ActivitiesController#index`, already fork-owned under `custom/`)
so that, for the four conversation-related event types only, each entry additionally carries the
referenced conversation's current `status` and a `conversation_viewable` boolean. Both are computed
server-side by batch-loading the referenced `Conversation` records (avoiding N+1) and running the
existing `ConversationPolicy#show?` against `Current.user` for each — the same authorization already
used everywhere else, so it automatically honors admin/agent-bot bypass, inbox access, team access,
and the enterprise policy override, without reimplementing any of it. No new endpoint, no new
migration, no change to write-time metadata.

**Alternatives considered**:
- *Fetch each conversation individually from the frontend to check.* Rejected — N+1 network calls
  per rendered history panel, worse UX (flicker/loading per row), and no material simplification
  over a single batched backend computation.
- *Extend `associated_conversations_json` and have the frontend cross-reference it.* Rejected — does
  not cover detached conversations (see above), which is a named acceptance scenario.
- *Add `team_id` to `associated_conversations_json` and replicate `ConversationPolicy` in JS.*
  Rejected — duplicates authorization logic in two places (a correctness/maintenance hazard) for no
  benefit over a single server-side check that already exists and already accounts for every access
  path including future policy changes.

## Unknown 3 — Dual-tree (OSS/Enterprise) impact

**Decision**: None beyond what's automatic. The enrichment reuses `ConversationPolicy.new(...).show?`
directly rather than reimplementing access rules, so the enterprise-prepended policy
(`enterprise/app/policies/enterprise/conversation_policy.rb`) is honored automatically. No Enterprise
override file is needed for this feature.

## Unknown 4 — Frontend test runner

**Decision**: Vitest (`pnpm test`, `vitest --no-watch ...` per `package.json`), not Jest —
`OPPORTUNITIES.DETAIL...`-style specs in this codebase are Vitest specs. (spec.md's acceptance
criteria mentioning "Jest" refers to the same suite; Vitest is the actual runner.)
