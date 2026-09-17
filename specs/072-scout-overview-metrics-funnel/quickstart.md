# Quickstart Validation Guide: Scout Overview — Summary Metrics & Funnel Distribution

## Prerequisites

- Docker stack running: `docker compose up -d`
- At least one Scout configured in the account (create via Scout → Agents if needed)
- At least one inbox linked to the Scout (`ScoutInbox`)
- At least one `PipelineStage` in the account (auto-seeded on first use)

## Seed Test Data

### Minimal seed (Rails console)

```bash
docker compose exec rails bundle exec rails runner - <<'RUBY'
account = Account.first
scout   = account.scouts.first

# Ensure outcome stages are configured
stages = account.pipeline_stages.order(:position)
scout.update!(
  qualified_stage_id:   stages[1]&.id,
  unqualified_stage_id: stages[2]&.id,
  rescue_stage_id:      stages[3]&.id
)

inbox = scout.inboxes.first
contact = account.contacts.first || account.contacts.create!(name: 'Test Lead', phone_number: '+5511900000001')

# Create 5 opportunities in different outcome states
5.times do |i|
  conv = account.conversations.create!(inbox: inbox, contact: contact, status: 'open')
  3.times { conv.messages.create!(message_type: :incoming, content: "msg #{i}", account: account) }
  stage = case i
    when 0 then stages[1]  # qualified
    when 1 then stages[2]  # disqualified
    when 2 then stages[3]  # abandoned
    else stages[0]         # in progress
  end
  account.opportunities.create!(
    contact: contact,
    pipeline_stage: stage,
    origin_conversation: conv,
    created_at: 3.days.ago
  )
end
puts "Done. Scout id=#{scout.id}"
RUBY
```

### Seed for interest-by-stage (requires interest field configured)

```bash
docker compose exec rails bundle exec rails runner - <<'RUBY'
account = Account.first
scout   = account.scouts.first

# Use or create a list-type custom attribute definition
defn = account.custom_attribute_definitions.find_or_create_by!(
  attribute_key: 'produto',
  attribute_display_type: 'list',
  attribute_model: 'opportunity_attribute',
  attribute_name: 'Produto'
)
scout.update!(interest_attribute_definition: defn)

stages  = account.pipeline_stages.order(:position)
inbox   = scout.inboxes.first
contact = account.contacts.first

%w[Seguro Financiamento Seguro].each_with_index do |produto, i|
  conv = account.conversations.create!(inbox: inbox, contact: contact, status: 'open')
  account.opportunities.create!(
    contact: contact,
    pipeline_stage: stages[i % stages.size],
    origin_conversation: conv,
    custom_attributes: { 'produto' => produto },
    created_at: 5.days.ago
  )
end
puts "Done. Interest attribute: #{defn.attribute_key}"
RUBY
```

---

## Validate the API Endpoint

Replace `ACCOUNT_ID`, `SCOUT_ID`, and `TOKEN` with real values.

### 1. Summary cards — period with data

```bash
curl -s "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=7" \
  -H "api_access_token: TOKEN" | jq .
```

**Expected shape**:
```json
{
  "summary": {
    "total_handled": 5,
    "qualification_rate": 20.0,
    "disqualification_rate": 20.0,
    "abandonment_rate": 20.0,
    "avg_messages_per_conversation": 3.0
  },
  "pipeline_stage_distribution": [ ... ],
  "interest_by_stage": { ... }
}
```

Key assertions:
- `total_handled` equals 5: counts all opportunities created within the `range` window by the Scout, including the 2 in-progress opportunities.
- `qualification_rate` is 20.0% (1 ÷ 5), `disqualification_rate` is 20.0% (1 ÷ 5), `abandonment_rate` is 20.0% (1 ÷ 5).
- Sum of outcome rates is 60.0% (the remaining 40% represents the 2 in-progress opportunities; in-progress opportunities are part of the denominator but have no outcome rate card).
- `avg_messages_per_conversation` equals 3.0 (non-activity conversational turns per conversation).
### 2. Period selector switch (no page reload)

Switch `range=7` → `range=30` → `range=this_month` → `range=last_month` in successive requests:

```bash
for R in 7 30 this_month last_month; do
  echo "--- range=$R ---"
  curl -s "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=$R" \
    -H "api_access_token: TOKEN" | jq '.summary.total_handled'
done
```

**Expected**: each response returns a valid `summary` object with counts that vary by window (seeded data was created 3–5 days ago, so `range=7` and `range=30` should include it; `last_month` should not if seeded today).

### 3. Unconfigured outcome stage → null rate

```bash
docker compose exec rails bundle exec rails runner \
  "Scout.first.update!(rescue_stage_id: nil); puts 'done'"

curl -s "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=7" \
  -H "api_access_token: TOKEN" | jq '.summary.abandonment_rate'
# Expected: null
```

Restore after test:
```bash
docker compose exec rails bundle exec rails runner \
  "Scout.first.update!(rescue_stage_id: PipelineStage.order(:position).third.id)"
```

### 4. No opportunities in period → empty state

```bash
curl -s "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=last_month" \
  -H "api_access_token: TOKEN" | jq '.summary'
# Expected: total_handled=0, all rates=null
```

`pipeline_stage_distribution` must still list all stages with `count: 0`.

### 5. Interest-by-stage — configured

After running the interest seed above:

```bash
curl -s "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=7" \
  -H "api_access_token: TOKEN" | jq '.interest_by_stage'
# Expected: { configured: true, attribute_name: "Produto", data: [...] }
```

### 6. Interest-by-stage — not configured

```bash
docker compose exec rails bundle exec rails runner \
  "Scout.first.update!(interest_attribute_definition_id: nil)"

curl -s "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=7" \
  -H "api_access_token: TOKEN" | jq '.interest_by_stage'
# Expected: { "configured": false }
```

### 7. Pipeline-stage distribution — not period-filtered

Create one opportunity outside the selected period:

```bash
docker compose exec rails bundle exec rails runner - <<'RUBY'
account = Account.first; scout = account.scouts.first
contact = account.contacts.first
conv = account.conversations.create!(inbox: scout.inboxes.first, contact: contact, status: 'open')
account.opportunities.create!(
  contact: contact,
  pipeline_stage: account.pipeline_stages.last,
  origin_conversation: conv,
  created_at: 60.days.ago
)
puts "Opportunity in last stage, created 60 days ago"
RUBY
```

```bash
# With range=7 (opportunity 60d ago is outside period)
curl -s "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=7" \
  -H "api_access_token: TOKEN" | jq '{total: .summary.total_handled, last_stage: .pipeline_stage_distribution[-1].count}'
```

**Expected**: `total` does NOT count the 60-day-old opportunity; but `last_stage` count in `pipeline_stage_distribution` DOES include it (snapshot is period-independent).


### 8. Authorization — Agent Role Access (Clarification 2026-09-16 / FR-015)

Verify that standard agents (non-administrators) have full access to Scout Overview, matching Captain Overview:

```bash
# Obtain or use an agent user's token (not administrator)
AGENT_TOKEN=$(docker compose exec rails bundle exec rails runner \
  "puts AccountUser.where(account_id: Account.first.id, role: :agent).first&.user&.access_token&.token")

curl -s -o /dev/null -w "%{http_code}\n" \
  "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=7" \
  -H "api_access_token: $AGENT_TOKEN"
# Expected: 200 (not 403 Forbidden)
```

### 9. Latency Benchmark (Clarification SC-002)

Verify on-demand execution on localhost/LAN meets the SC-002 performance goal (< 2.0s):

```bash
curl -s -w "Total time: %{time_total}s\n" -o /dev/null \
  "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/scout_overview_reports?scout_id=SCOUT_ID&range=30" \
  -H "api_access_token: TOKEN"
# Expected: Total time < 2.0s (typically < 0.1s on localhost)
```
---

## Validate the Frontend

1. Start the dev stack and open `http://localhost:3036`.
2. Navigate to **Scout → Overview** (first item in the Scout sidebar section).
3. Verify:
   - Five summary cards render with correct values matching the API
   - Period selector (7d / 30d / this month / last month) updates cards without full page reload
   - If account has > 1 Scout, a Scout selector appears at the top; switching it changes all cards
   - If account has exactly 1 Scout, no selector is shown
   - Pipeline-stage distribution chart renders all stages (including human-managed stages after qualification)
   - Interest-by-stage card: when configured, shows stacked breakdown; when not configured, shows CTA linking to `scout_funnel` route
   - With no opportunities in the period, `EmptyStateLayout` appears instead of charts

---

## References

- API contract: [`contracts/api.md`](contracts/api.md)
- Data model: [`data-model.md`](data-model.md)
- Research decisions: [`research.md`](research.md)
