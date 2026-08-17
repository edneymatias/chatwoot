# Frontend Component Contract: Opportunity Activity Log

---

## 1. Component: `OpportunityActivityLog.vue`

**Path**: `app/javascript/dashboard/components-next/Opportunities/OpportunityActivityLog.vue`

### Props
| Prop Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `opportunityId` | `Number` | Yes | - | ID of the opportunity whose activities are being rendered |

### Internal State & Computed
- `activities`: `Array<Activity>` (fetched on mount or when `opportunityId` changes)
- `isLoading`: `Boolean`
- `hasError`: `Boolean`
- `stageMap`: Computed dictionary of stages (`id -> name`) from `pipelineStages` store module

### Template & Layout
- Header bar: Shows Title ("Histórico da oportunidade" / "Opportunity Activity") and close / return action if desired.
- Body: Scrollable vertical timeline (`overflow-y-auto`, `max-h-full`).
- Timeline item layout:
  - Left icon column: Circular badge with specific icon & color per `event_type`:
    - `opportunity_created`: `i-ph-plus-circle-bold` (brand / blue)
    - `opportunity_stage_changed`: `i-ph-arrows-left-right-bold` (amber / violet)
    - `opportunity_won`: `i-ph-trophy-bold` (emerald / green)
    - `opportunity_lost`: `i-ph-x-circle-bold` (ruby / red)
    - `opportunity_reopened`: `i-ph-arrow-counter-clockwise-bold` (slate)
    - `conversation_opened`: `i-ph-chat-circle-dots-bold` (sky / cyan)
  - Content column:
    - Event text with stage names / conversation details
    - Badge for `(approximate)` / `(aproximado)` if `metadata.approximate === true`
    - Actor attribution ("por {actor.name}" / "by {actor.name}")
    - Relative timestamp (`timeAgo` / formatted date tooltip)

---

## 2. Drawer Integration: `OpportunityConversationDrawer.vue`

**Path**: `app/javascript/dashboard/components-next/Opportunities/OpportunityConversationDrawer.vue`

### Added State & Handlers
- `activeTab`: `ref<'conversation' | 'activity'>('conversation')`
- `isOpportunitiesFeatureEnabled`: `computed(() => isCloudFeatureEnabled(FEATURE_FLAGS.OPPORTUNITIES))`
- `currentOpportunity`: `computed(() => store.getters['opportunities/opportunityByConversationId'](currentChat.value?.id))`
- ButtonGroup addition:
  - Adds toggle button when `isOpportunitiesFeatureEnabled && currentOpportunity` is true.
  - Clicking toggles between `activeTab = 'activity'` and `activeTab = 'conversation'`.
- Content swap:
  - When `activeTab === 'activity'`, renders `<OpportunityActivityLog :opportunity-id="currentOpportunity.id" />`
  - When `activeTab === 'conversation'`, renders `<ConversationBox>` + `<ConversationSidebar>`.
