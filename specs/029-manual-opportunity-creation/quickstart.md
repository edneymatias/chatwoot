# Quickstart & Validation Guide

## Prerequisites
- Docker stack running (`docker compose up -d`)
- Test data seeded (`docker compose exec rails bundle exec rails db:seed` or `search:setup_test_data`)

## Validation Scenario 1: Manual Opportunity Creation

1. Log into the application and navigate to the **Opportunities** List view.
2. Verify the "add opportunity" button is enabled.
3. Click "add opportunity".
4. Fill out the title, select a contact, and select a pipeline stage from the dropdown.
5. Submit the form.
6. **Expected Outcome**: The opportunity is created and appears in the list view immediately.

## Validation Scenario 2: Starting a Conversation from an Opportunity

1. Locate or create an opportunity that has no linked conversation.
2. In the **List View**, verify there is a "Start Conversation" action button on the row.
3. Switch to the **Kanban View** and hover over the same opportunity's card. Verify the "Start Conversation" quick action icon appears.
4. Click the action button to open the compose flow.
5. Create a new conversation using the form.
6. **Expected Outcome**: The modal closes, and the opportunity immediately reflects that it is linked to a conversation (the action button disappears, and the row/card becomes fully clickable).
