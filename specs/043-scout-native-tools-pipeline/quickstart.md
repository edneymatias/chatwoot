# Quickstart: Scout Native Tools & Message Pipeline

**Branch**: `043-scout-native-tools-pipeline` | **Date**: 2026-08-19 | **Spec**: [spec.md](file:///home/matias/dev/chatwoot/specs/043-scout-native-tools-pipeline/spec.md)

This guide provides executable validation steps to verify the Scout Native Tools and Message Pipeline end-to-end.

---

## Prerequisites & Setup

1. Ensure the container environment is running:
   ```bash
   docker compose up -d
   ```

2. Seed test data or ensure standard seed accounts exist:
   ```bash
   docker compose exec rails bundle exec rails db:seed
   ```

---

## Validation Scenarios

### Scenario 1: WhatsApp Message Burst & Sliding Debounce

**Goal**: Verify that multiple messages sent within the debounce window produce a single Scout processing pass, sliding the window on each arrival.

1. Open Rails console:
   ```bash
   docker compose exec rails bundle exec rails console
   ```
2. Set up test Scout and Conversation:
   ```ruby
   account = Account.first
   inbox = account.inboxes.create!(name: 'WhatsApp Test', channel: Channel::Whatsapp.create!(account: account, phone_number: '+1234567890'))
   scout = Scout.create!(
     account: account,
     name: 'SDR Scout',
     provider: :gemini,
     model_name: 'gemini-2.0-flash',
     debounce_delay_seconds: 4,
     enabled: true
   )
   ScoutInbox.create!(scout: scout, inbox: inbox)

   contact = account.contacts.create!(name: 'Lead Test', phone_number: '+1987654321')
   contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: '+1987654321')
   conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending)
   ```
3. Send 3 incoming messages spaced 2 seconds apart (total span 4s > initial delay 4s, but sliding resets):
   ```ruby
   3.times do |i|
     msg = conversation.messages.create!(account: account, inbox: inbox, sender: contact, message_type: :incoming, content: "Mensagem #{i + 1}")
     Rails.configuration.dispatcher.dispatch(Events::Types::MESSAGE_CREATED, Time.current, message: msg)
     sleep 2
   end
   ```
4. **Expected Outcome**:
   - Exactly 1 `Custom::Scout::ProcessMessageJob` executes to completion 4 seconds after the *third* message.
   - Exactly 1 Scout outgoing reply is posted to the conversation.

---

### Scenario 2: CTWA Ad Referral Attribution Preservation

**Goal**: Verify that an Opportunity created via `manage_opportunity` inherits campaign attribution from the referral message and remains intact across turns.

1. Create incoming message with CTWA referral payload:
   ```ruby
   referral_payload = {
     'source_url' => 'https://facebook.com/ads/123?ad_id=987654321',
     'headline' => 'Oferta Especial 50% OFF',
     'body' => 'Clique para falar com um consultor',
     'thumbnail_url' => 'https://example.com/thumb.jpg',
     'source_type' => 'ad'
   }
   conversation.messages.create!(
     account: account,
     inbox: inbox,
     sender: contact,
     message_type: :incoming,
     content: 'Olá, vi o anúncio!',
     content_attributes: { referral: referral_payload }
   )
   ```
2. Execute `Custom::Scout::Tools::ManageOpportunity`:
   ```ruby
   tool = Custom::Scout::Tools::ManageOpportunity.new(scout, conversation)
   tool.execute(action: 'create', title: 'Oportunidade WhatsApp', estimated_value: 5000.0)
   ```
3. **Expected Outcome**:
   - `Opportunity` is created with:
     - `campaign_platform`: `'facebook'`
     - `campaign_source_id`: `'987654321'`
     - `campaign_headline`: `'Oferta Especial 50% OFF'`
     - `campaign_thumbnail_url`: `'https://example.com/thumb.jpg'`

---

### Scenario 3: Fail-Safe Trigger on Quota / Key / Runtime Error

**Goal**: Verify that exhausted quota or runtime errors trigger immediate handoff to human with an alert note and never leave the conversation stuck in `pending`.

1. Set `scout.responses_quota = 0` (or `responses_consumed = 5`, `responses_quota = 5`).
2. Trigger runner:
   ```ruby
   Custom::Scout::AgentRunner.new(scout: scout, conversation: conversation).perform
   ```
3. **Expected Outcome**:
   - `conversation.reload.status` is `'open'` (not `'pending'`).
   - A private note exists containing: `⚠️ [IA Pausada]`.
   - LLM provider was never called.

---

### Scenario 4: Contact Memory on Handoff (`feature_memory`)

**Goal**: Verify that handoff creates contact notes summarizing qualification when `feature_memory: true`, and omits them when `false`.

1. With `scout.update!(feature_memory: true)`:
   - Execute `Custom::Scout::Tools::HandoverToHuman.new(scout, conversation).execute(reason: 'Lead qualificado')`
   - **Expected Outcome**: `contact.notes` has at least 1 new record.
2. With `scout.update!(feature_memory: false)`:
   - Note count on contact does not increase on handoff.

---

## Automated Test Verification

Run targeted RSpec suite:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/ custom/spec/jobs/custom/scout/ custom/spec/listeners/custom/
```
