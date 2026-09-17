# Quickstart Validation Guide: Scout Overview — Recent Conversations List

**Feature**: `073-scout-overview-conversations`  
**Date**: 2026-09-16  
**Status**: Ready for Verification  

---

## 1. Prerequisites

Ensure the container stack is active:
```bash
docker compose up -d
```
Verify that `rails` and `vite` containers are healthy.

---

## 2. Seed Test Fixtures (All 5 Funnel Outcomes)

Run the following Rails runner command inside the `rails` container to seed conversations covering all five outcome states and edge cases:

```bash
docker compose exec rails bundle exec rails runner "
account = Account.first || FactoryBot.create(:account)
user = account.administrators.first || FactoryBot.create(:user, account: account, role: :administrator)

# 1. Pipeline Stages
pipeline = account.pipeline_stages.any? ? account.pipeline_stages.first.pipeline : FactoryBot.create(:pipeline, account: account)
init_stage = account.pipeline_stages.find_or_create_by!(name: 'Initial Screening', pipeline: pipeline, position: 0)
qual_stage = account.pipeline_stages.find_or_create_by!(name: 'Qualified Leads', pipeline: pipeline, position: 1)
disq_stage = account.pipeline_stages.find_or_create_by!(name: 'Unqualified Leads', pipeline: pipeline, position: 2)
resc_stage = account.pipeline_stages.find_or_create_by!(name: 'Rescue Follow-up', pipeline: pipeline, position: 3)

# 2. Scout & Inbox
scout = account.scouts.first_or_create!(
  name: 'Lead Qualification SDR',
  persona: 'Commercial Qualification AI',
  debounce_delay_seconds: 10,
  responses_quota: -1,
  qualified_stage: qual_stage,
  unqualified_stage: disq_stage,
  rescue_stage: resc_stage,
  default_pipeline_stage: init_stage,
  follow_up_delays_hours: [1, 3, 6]
)

inbox = account.inboxes.first || FactoryBot.create(:inbox, account: account)
ScoutInbox.find_or_create_by!(scout: scout, inbox: inbox)

# 3. Helper to create conversation with messages
def create_conv(account, inbox, contact_name, status: :pending, created_at: 1.day.ago)
  contact = account.contacts.create!(name: contact_name, email: \"#{contact_name.parameterize}@example.com\")
  conv = account.conversations.create!(
    inbox: inbox,
    contact: contact,
    status: status,
    created_at: created_at
  )
  conv
end

# A. Qualified conversation
c1 = create_conv(account, inbox, 'Maria Qualified', status: :open, created_at: 2.days.ago)
opp1 = account.opportunities.create!(title: 'Deal Maria', contact: c1.contact, pipeline_stage: qual_stage, origin_conversation: c1)
c1.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: 'Hi, I want enterprise pricing', created_at: 2.days.ago)
c1.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Great, here are the details!', created_at: 2.days.ago + 5.minutes)

# B. Disqualified conversation
c2 = create_conv(account, inbox, 'Bob Disqualified', status: :open, created_at: 3.days.ago)
opp2 = account.opportunities.create!(title: 'Deal Bob', contact: c2.contact, pipeline_stage: disq_stage, origin_conversation: c2)
c2.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: 'I am a student looking for free tools', created_at: 3.days.ago)
c2.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Understood, our platform is paid B2B.', created_at: 3.days.ago + 2.minutes)

# C. Abandoned conversation (Rescue)
c3 = create_conv(account, inbox, 'Alice Abandoned', status: :open, created_at: 4.days.ago)
opp3 = account.opportunities.create!(title: 'Deal Alice', contact: c3.contact, pipeline_stage: resc_stage, origin_conversation: c3)
c3.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: 'Need a demo', created_at: 4.days.ago)
c3.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'When are you free?', created_at: 4.days.ago + 1.minute)

# D. In Progress conversation
c4 = create_conv(account, inbox, 'Carlos InProgress', status: :pending, created_at: 1.hour.ago)
opp4 = account.opportunities.create!(title: 'Deal Carlos', contact: c4.contact, pipeline_stage: init_stage, origin_conversation: c4)
c4.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: 'Hi there', created_at: 1.hour.ago)
c4.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Hello! How can I assist you?', created_at: 1.hour.ago + 30.seconds)

# E. Transferred without opportunity
c5 = create_conv(account, inbox, 'David Handoff', status: :open, created_at: 2.hours.ago)
c5.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: 'Can I speak to human billing?', created_at: 2.hours.ago)
c5.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Transferring you now.', created_at: 2.hours.ago + 10.seconds)

# F. Single-message conversation (Edge case: duration should be '—')
c6 = create_conv(account, inbox, 'Solo Message Lead', status: :pending, created_at: 30.minutes.ago)
c6.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: 'Just pinging', created_at: 30.minutes.ago)

puts 'Fixtures seeded successfully! Scout ID: ' + scout.id.to_s
"
```

---

## 3. Automated Validation

### 3.1 Backend Request Specs (RSpec)
Execute the controller and builder request specs:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb
```
**Expected Outcome**: All examples pass (0 failures).

### 3.2 Frontend Unit/Component Tests (Vitest)
Execute Vitest across the Scout overview components:
```bash
docker compose exec vite pnpm test app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js
```
**Expected Outcome**: Tests verify rendering of the Recent Conversations table, status badges, filter pill interactions, and row click behavior.

---

## 4. Manual / End-to-End Scenarios

### Scenario 1: Verify Conversations Endpoint
Query the conversations endpoint directly:
```bash
docker compose exec rails bundle exec rails runner "
account = Account.first
scout = account.scouts.first
builder = Reports::ScoutOverviewConversationsBuilder.new(
  account: account,
  scout: scout,
  range: '7',
  status: 'all',
  page: 1,
  per_page: 25
)
result = builder.build
puts 'Total conversations: ' + result[:pagination][:total_count].to_s
puts 'Status counts: ' + result[:status_counts].inspect
puts 'Sample row: ' + result[:conversations].first.slice(:contact, :status, :duration_seconds, :messages_count).inspect
"
```

**Expected Outcome**:
- `total_count` reflects 6 conversations.
- `status_counts` contains all 5 categories (`qualified`, `disqualified`, `abandoned`, `in_progress`, `transferred_without_opportunity`).
- `Maria Qualified` is classified as `qualified`.
- `David Handoff` is classified as `transferred_without_opportunity`.
- `Solo Message Lead` has `duration_seconds: nil` and `messages_count: 1`.

---

### Scenario 2: UI Inspection in Browser
1. Log into Chatwoot: `http://localhost:3000/app/accounts/1/scout` (or click Scout in the sidebar).
2. Click **Overview** (the first item in the Scout navigation).
3. Scroll to the bottom of the page to observe the **Recent Conversations** section:
   - Verify six status filter pills: `All`, `Qualified`, `Disqualified`, `Abandoned`, `In Progress`, `Transferred without opportunity`.
   - Verify each pill shows its respective count.
   - Verify columns: Contact, Start Time, Duration, Messages, Status.
   - Verify "Solo Message Lead" displays `—` for duration.
   - Verify "David Handoff" shows a neutral slate badge "Transferred without opportunity".
   - Click a row: verify a new browser tab opens to `/app/accounts/1/conversations/:id`.
   - Click the "Abandoned" filter pill: verify only abandoned conversations are displayed.
   - Change the period dropdown at the top: verify the table synchronizes cleanly.
