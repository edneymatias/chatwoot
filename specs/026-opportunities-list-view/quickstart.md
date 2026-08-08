# Quickstart & Validation Guide: Kanban List View

This guide provides steps to validate the new Opportunities List View functionality locally. 

## Prerequisites

Ensure your local development environment is running:

```bash
docker compose up -d
```

Seed the database with sample account and opportunity data if you haven't already:

```bash
docker compose exec rails bundle exec rails db:seed
```

## Validation Scenarios

### Scenario 1: View Toggle and Persistence

1. Navigate to the Opportunities index page in the application.
2. Verify that the new `OpportunitiesViewBar` is visible above the Kanban board.
3. Observe the total lead count and total opportunity value displayed on the bar.
4. Click the "List View" icon on the bar.
5. **Expected Outcome:** The view should immediately switch from the Kanban board to a dense table/list layout. 
6. Refresh the page in your browser.
7. **Expected Outcome:** The list view should remain active, confirming that your preference was successfully loaded from `localStorage`.
8. Click the "Kanban View" icon.
9. **Expected Outcome:** The view switches back to the standard Kanban board.

### Scenario 2: List View Data and Infinite Scroll

1. Ensure you have more than 10 opportunities created in your local database. (If not, create them via the UI or Rails console).
2. Switch to the List View.
3. Verify that the table rows display the correct data matching the Kanban cards (Title, Contact, Assignee, Stage Name, Value, Status Badge, Last Activity).
4. Scroll to the bottom of the list.
5. **Expected Outcome:** A loading indicator appears briefly, and the next page of opportunities is appended to the bottom of the list (Infinite Scroll).

### Scenario 3: Read-Only Actions and Navigation

1. While in the List View, attempt to drag a row or inline-edit a stage.
2. **Expected Outcome:** The rows should be read-only with no drag-and-drop or stage dropdowns available.
3. Click on a row that represents an opportunity with an associated conversation (has an `origin_conversation_id`).
4. **Expected Outcome:** The standard conversation drawer should open on the right side of the screen.
5. Click on a row that does not have an associated conversation.
6. **Expected Outcome:** Nothing should happen.
