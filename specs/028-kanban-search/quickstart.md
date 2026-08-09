# Quickstart Validation Guide

This guide details how to validate the Kanban Search and Filter feature end-to-end locally.

## Prerequisites

- The standard Docker Compose stack must be running (`docker compose up -d`).
- Test data should be seeded using the backend rails tasks.

## 1. Setup Test Data

If your local environment doesn't have opportunities and contacts, seed them:
```bash
docker compose exec rails bundle exec rails db:seed
docker compose exec rails bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.first)"
```

## 2. API Validation

You can validate the API filters using a tool like curl or by inspecting network requests in your browser.

1. Find an existing opportunity's title and its contact's name.
2. Send a request with a partial title:
   ```bash
   curl -H "api_access_token: <YOUR_TOKEN>" "http://localhost:3000/api/v1/accounts/1/opportunities?q=partial_title"
   ```
   **Expected**: The response contains only opportunities matching the partial title.
3. Send a request with a partial contact name:
   ```bash
   curl -H "api_access_token: <YOUR_TOKEN>" "http://localhost:3000/api/v1/accounts/1/opportunities?q=contact_name"
   ```
   **Expected**: The response contains opportunities associated with that contact.
4. Test sort by value:
   ```bash
   curl -H "api_access_token: <YOUR_TOKEN>" "http://localhost:3000/api/v1/accounts/1/opportunities?sort_by=value_desc"
   ```
   **Expected**: Opportunities are ordered by value, highest first.

## 3. UI Validation

1. Log into the application and navigate to the **Opportunities** page.
2. Ensure you are in the **Kanban** view.
3. **Test Search**: Type a name into the search bar. The board should immediately reload and show only cards matching the query.
4. **Test Assignee/Status Filters**: Select a specific Assignee and Status from the dropdowns. The board should update.
5. **Test Reset on Navigation**: Navigate to the Inbox or Contacts view, then return to Opportunities. All filters should be cleared, and the full list should be visible.
6. Switch to the **List** view.
7. **Test Sorting**: Select "Value (high to low)" from the sort dropdown. The table rows should reorder. Note that this dropdown should be hidden when switching back to Kanban view.
