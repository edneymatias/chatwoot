# Quickstart: Scout External REST/Webhook Tool

**Branch**: `045-scout-external-webhook-tool` | **Date**: 2026-08-19 | **Spec**: [spec.md](spec.md)

Validates the feature end-to-end against a running dev stack (`docker compose up -d`). Assumes an
account, a Scout, an inbox, and a conversation already exist (see
`specs/043-scout-native-tools-pipeline/quickstart.md` for how to seed those from scratch).

## Prerequisites

- Dev stack running: `docker compose up -d`
- A test HTTP endpoint to call. The simplest option is a local echo/mock endpoint reachable from
  inside the `rails` container (e.g. a `webhook.site` URL, or a tiny Sinatra/Rack script run on the
  host and exposed via the container network) that returns a small JSON body.

## Setup: configure an external tool

```ruby
# docker compose exec rails bundle exec rails runner
account = Account.first
scout = Scout.find_by(account: account) # from prior phases

tool = ScoutTool.create!(
  account: account,
  name: 'check_stock',
  description: 'Checks live stock for a SKU',
  endpoint_url: 'https://webhook.site/<your-test-id>', # replace with a reachable test endpoint
  http_method: 'POST',
  auth_headers: { 'Authorization' => 'Bearer test-token' },
  parameters_schema: {
    'type' => 'object',
    'properties' => { 'sku' => { 'type' => 'string' } },
    'required' => ['sku']
  },
  enabled: true
)
```

## Scenario 1: successful call (User Story 1)

1. Start a conversation whose message content would plausibly lead the Scout to look up stock
   (e.g. "Do you have SKU ABC123 in stock?").
2. Dispatch the message the same way `specs/043-scout-native-tools-pipeline/quickstart.md` does
   (via `Events::Types::MESSAGE_CREATED`), and let the debounce delay elapse.
3. **Expected outcome**: the outbound request arrives at the test endpoint with the payload
   `{"sku":"ABC123"}` and the configured `Authorization` header; the Scout's reply in the
   conversation reflects the endpoint's response body rather than a generic/hallucinated answer.

## Scenario 2: invalid payload (User Story 2, schema branch)

1. Temporarily tighten `parameters_schema` to require a field the Scout is unlikely to supply
   (e.g. `'required' => ['sku', 'warehouse_id']`), or trigger a conversation where the Scout would
   omit `warehouse_id`.
2. **Expected outcome**: server logs show no outbound HTTP request was made to `endpoint_url`; the
   conversation still receives a Scout reply (not a stalled/errored turn).

## Scenario 3: unreachable endpoint (User Story 2, timeout branch)

1. Point `tool.endpoint_url` at a non-routable/black-hole address (e.g. `http://10.255.255.1/`, a
   commonly used unreachable test IP) or a deliberately slow endpoint.
2. Trigger a conversation that would call the tool.
3. **Expected outcome**: the conversation turn completes within roughly 22 seconds (2s connect +
   20s read bound) rather than hanging; `Rails.logger` shows an error log entry for the failed
   call; the customer still receives some reply.

## Scenario 4: disabled tool (User Story 3)

1. `tool.update!(enabled: false)`.
2. Start a new conversation that would previously have triggered the tool.
3. **Expected outcome**: server logs / a debugger breakpoint in `build_tools` confirm
   `call_custom_api` either excludes this tool from its resolvable set or refuses the call with a
   structured failure — the external endpoint is never contacted (verify via the test endpoint's
   request log, e.g. `webhook.site`'s request history, showing no new hit).
4. `tool.update!(enabled: true)` and repeat Scenario 1 to confirm it becomes callable again with
   its original configuration intact.

## Cross-account isolation check

1. Create a second `Account` with its own `Scout` and an external tool of the same `name`.
2. Confirm (via a Rails console call to the tool resolution method directly, or via a conversation
   in the first account) that a Scout in Account A can never resolve or call Account B's
   `ScoutTool`, even when passed Account B's `tool_id` directly.
