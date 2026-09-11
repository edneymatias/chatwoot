# Quickstart & Verification Guide: Scout Custom Tool Authentication & Visual Parameter Builder

This guide describes end-to-end verification scenarios to validate structured HTTP authentication and visual parameter builder functionality for Scout custom tools.

---

## Prerequisites

- Chatwoot development environment running (`docker compose up -d`).
- Database migrated with the new `auth_type` column on `ichatr_scout_tools`.
- Logged in as an admin or agent to the dashboard.

---

## Verification Scenarios

### Scenario 1: Create a Tool with Bearer Token & Visual Parameters

1. Navigate to **Scout → Tools** in the primary navigation.
2. Click **"+ Add Tool"** to open the `ScoutToolModal`.
3. Enter basic details:
   - **Tool Name**: `Order Lookup`
   - **Method**: `GET`
   - **Endpoint URL**: `https://httpbin.org/anything/orders/{{ order_id }}`
   - **Description**: `Looks up order status and details by order ID`
4. Under **Authentication Type**, select **Bearer Token**:
   - Verify the Token input field appears.
   - Enter `demo_secret_token_123`.
5. Under **Parameters**, click **"+ Add Parameter"**:
   - **Name**: `order_id`
   - **Type**: `String`
   - **Description**: `The customer order identifier`
   - **Required**: Check the checkbox.
6. Click **"+ Add Parameter"** again:
   - **Name**: `include_items`
   - **Type**: `Boolean`
   - **Description**: `Whether to include detailed line items in the response`
   - **Required**: Leave unchecked.
7. Click **"▷ Test connection"**:
   - Verify sample payload is pre-populated with `{"order_id": "", "include_items": true}`.
   - Fill in `"order_id": "ORD-12345"`.
   - Click "Test" and verify that httpbin returns `200 OK` with header `Authorization: Bearer demo_secret_token_123`.
8. Click **"Create"** and confirm the tool appears in the tools list.

---

### Scenario 2: Verify Parameter Identifier Validation

1. In the tool creation/editing modal, click **"+ Add Parameter"**.
2. Type an invalid name such as `order id` (with space) or `order-id` (with hyphen).
3. Verify that an inline validation message appears indicating that only alphanumeric characters and underscores are permitted.
4. Try to submit the form; verify submission is blocked until corrected to `order_id`.

---

### Scenario 3: Edit Tool & Verify Secret Masking

1. In the tools list, click the edit button (pencil icon) on the tool created in Scenario 1.
2. Verify that:
   - **Authentication Type** is selected as `Bearer Token`.
   - The token field displays `••••••••`.
   - The parameters `order_id` and `include_items` are listed in the visual builder with their types, descriptions, and required states.
3. Edit only the description: change to `Updated order lookup tool`.
4. Click **"Save changes"** without modifying the masked token field.
5. Re-open the tool or test the connection to verify the original token `demo_secret_token_123` was retained and not corrupted by `••••••••`.

---

## Automated Test Commands

### Backend Specs
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/scout_tool_spec.rb \
  custom/spec/services/custom/scout/tools/http_request_executor_spec.rb \
  custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb
```

### Backend Linting
```bash
docker compose exec rails bundle exec rubocop \
  custom/app/models/scout_tool.rb \
  custom/app/services/custom/scout/tools/http_request_executor.rb \
  custom/app/controllers/api/v1/accounts/scout_tools_controller.rb
```

### Frontend Linting
```bash
docker compose exec vite pnpm eslint app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue
```
