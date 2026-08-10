# Phase 0: Research

## Decisions

- **Decision**: Re-use `OpportunityCreateModal.vue` for manual opportunity creation.
  **Rationale**: The modal already supports all required fields (title, contact search, stage select, assignee, deal value). Opening it without a `defaultStageId` provides the necessary "board-independent" creation flow with zero new components.
  **Alternatives considered**: Building a dedicated "List View Opportunity Create" form, rejected to adhere to the Smallest Production-Ready Change principle.

- **Decision**: Wrap `ComposeConversation.vue` inside `StartOpportunityConversationButton.vue`.
  **Rationale**: `ComposeConversation.vue` already handles the complex logic of selecting an inbox, finding the contact, and creating a conversation. A wrapper can pre-fill the `contactId` and monitor for the newly created conversation via Vuex getters, then immediately link it to the opportunity.
  **Alternatives considered**: Building a custom API call and modal for conversation creation, rejected to avoid duplicating upstream logic.

- **Decision**: Limit `origin_conversation_id` mutation in `OpportunitiesController`.
  **Rationale**: Allowing an opportunity to link a conversation after creation is necessary. However, to prevent accidental un-linking, a model validation will ensure it can only be updated if it is currently `nil`.
  **Alternatives considered**: Allowing free reassignment, rejected as it was explicitly scoped out and would require additional UX for un-linking.
