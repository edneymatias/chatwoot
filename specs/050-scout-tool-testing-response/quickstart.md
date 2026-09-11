# Quickstart & Validation Guide: Scout Tool Testing & Response Shaping

## Prerequisites & Setup

1. **Start Development Environment**:
   ```bash
   docker compose up -d
   ```
2. **Apply Database Migrations**:
   ```bash
   docker compose exec rails bundle exec rails db:migrate
   ```

---

## Scenario 1: Validate Path Placeholders & Query Parameters via RSpec

Run the custom tool test suite:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/tools/http_request_executor_spec.rb custom/spec/services/custom/scout/tools/call_custom_api_spec.rb
```

### Expected Behavior
- URL templates with `{{order_id}}` substitute the matching payload parameter.
- Unconsumed parameters for `GET` requests append to the query string (e.g. `?limit=10&filters=%7B%22status%22%3A%22active%22%7D`).
- Unconsumed parameters for `POST` requests form the JSON request body.
- Missing path parameters raise a strict template rendering error before any network request is sent.

---

## Scenario 2: Validate Response Shaping with Liquid Templates

Run response template shaping specs:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/tools/http_request_executor_spec.rb
```

### Expected Behavior
- When `response_template` is `"Order {{ r.id }} status: {{ r.status }}"` and the remote API returns `{"id": 42, "status": "delivered", "extra": "..."}`, the shaped response is `"Order 42 status: delivered"`.
- When `response_template` is nil or empty, the parsed JSON or raw body is returned unchanged.
- Referencing a non-existent field under strict evaluation returns an informative template rendering error.

---

## Scenario 3: Validate Draft Tool Testing API Endpoint

Run test endpoint request specs:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb
```

### Expected Behavior
- `POST /api/v1/accounts/:account_id/scout_tools/test` executes the draft request without persisting a `ScoutTool` record.
- Successful executions return status 200 with `raw_body` (truncated to 500 characters) and `formatted_response`.
- Network errors, timeouts, or remote 4xx/5xx responses return status 200 with detailed error diagnostic strings and the captured HTTP status.

---

## Scenario 4: Validate Frontend Management Modal & Test Playground

1. Navigate to **Scout → Tools** (`/app/accounts/{accountId}/scout_tools`) in the browser.
2. Click **Add Tool**.
3. Enter:
   - **Name**: `order_status`
   - **Method**: `GET`
   - **Endpoint URL**: `https://httpbin.org/anything/orders/{{order_id}}`
   - **Response Template**: `Order {{ r.json.order_id }} is processed with query: {{ r.args.status }}`
   - **Sample Payload**: `{"order_id": "999", "status": "active"}`
4. Click **Test**.
5. Verify:
   - HTTP Status 200 badge is displayed.
   - Raw Response Preview displays the JSON response from httpbin (truncated if > 500 chars).
   - Shaped Response Preview displays `"Order 999 is processed with query: active"`.
6. Save the tool and reopen it to verify that `endpoint_url`, `auth_headers`, and `response_template` persist accurately.
