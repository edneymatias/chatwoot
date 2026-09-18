# Quickstart & Validation Guide: ERP Integration Foundation & Younus Setup

**Feature**: 074-erp-integration-foundation
**Date**: 2026-09-17
**Status**: Completed

This guide provides end-to-end runnable scenarios to verify all functional requirements and acceptance criteria for the ERP Integration Foundation and Younus Setup.

---

## 1. Prerequisites & Setup

Ensure the container stack is active:
```bash
docker compose up -d
```

Verify services (`rails`, `vite`, `postgres`, `redis`) are healthy.

Ensure test account exists (e.g. Account ID `1`) with an administrator user.

---

## 2. Validation Scenarios

### Scenario 1: Account-Level ERP Feature Flag Gating (US1 / FR-001, FR-002, FR-003)

#### Goal
Verify that accounts without `erp_integration` cannot see or access the ERP integration area, while accounts with the flag enabled can access it.

#### 1.1 Disabled Flag Verification
1. Ensure `erp_integration` is disabled for Account 1:
   ```bash
   docker compose exec rails bundle exec rails runner "Account.find(1).disable_features!('erp_integration')"
   ```
2. Log in as an administrator for Account 1 and navigate to **Settings > Integrations** (`/app/accounts/1/settings/integrations`).
   - **Expected Outcome**: The integrations gallery does **not** display any "ERP" card.
3. Manually enter the ERP URL into the browser: `/app/accounts/1/settings/integrations/erp`.
   - **Expected Outcome**: The router intercepts navigation and redirects to `/app/accounts/1/dashboard` (or integrations root), adhering to feature-flag gating.

#### 1.2 Enabled Flag Verification
1. Enable `erp_integration` for Account 1:
   ```bash
   docker compose exec rails bundle exec rails runner "Account.find(1).enable_features!('erp_integration')"
   ```
2. Refresh **Settings > Integrations** in the browser.
   - **Expected Outcome**: The integrations gallery displays a unified **ERP** card (`INTEGRATION_APPS.ERP.NAME`).
3. Click the **Configure** button on the "ERP" card.
   - **Expected Outcome**: The browser successfully navigates to `/app/accounts/1/settings/integrations/erp`.

---

### Scenario 2: ERP Provider Selection Gallery (US2 / FR-004, FR-005, FR-006)

#### Goal
Verify that the ERP gallery lists supported ERP providers and allows initiating provider setup.

1. Navigate to `/app/accounts/1/settings/integrations/erp`.
2. Inspect the displayed provider list:
   - **Expected Outcome**:
     - Header displays "ERP Integrations" with a back button returning to Settings > Integrations.
     - "Younus ERP" is listed with its logo, description, and a "Disconnected" / "Not Configured" status badge.
     - A "Configure" button is present on the Younus card.
3. Click **Configure** on the Younus card.
   - **Expected Outcome**: Browser navigates to `/app/accounts/1/settings/integrations/younus`, displaying the single integration overview with a **Connect** button.

---

### Scenario 3: Form Validation on Empty Inputs (US2 / FR-007)

#### Goal
Verify that missing mandatory credentials prevent form submission without invoking the remote service.

1. On `/app/accounts/1/settings/integrations/younus`, click **Connect**.
   - **Expected Outcome**: A modal opens displaying the Younus setup form with two inputs: "API Token" (`token`) and "Company ID" (`id_empresa`).
2. Leave both fields blank and click **Submit**.
   - **Expected Outcome**: FormKit client-side validation marks both fields as required and blocks the network request. No HTTP call is sent to Chatwoot or Younus.
3. Enter only an API token and leave Company ID blank, then click **Submit**.
   - **Expected Outcome**: Submission is blocked with a validation message under "Company ID".

---

### Scenario 4: Synchronous Invalid Credentials Rejection (US2 / FR-008, FR-009)

#### Goal
Verify that rejected authentication (HTTP 401/403) synchronously halts the save and displays "Invalid credentials".

#### CLI / cURL Test
```bash
docker compose exec rails bundle exec rails runner "
  hook = Integrations::Hook.new(
    account: Account.find(1),
    app_id: 'younus',
    settings: { 'token' => 'invalid-token-12345', 'id_empresa' => '999' }
  )
  if hook.save
    puts 'ERROR: Hook should not have saved'
  else
    puts 'SUCCESS: ' + hook.errors.full_messages.join(', ')
  end
"
```
- **Expected CLI Output**:
  ```text
  SUCCESS: Invalid credentials
  ```

#### UI Test
1. In the Younus connection modal, enter:
   - **API Token**: `invalid-token-12345`
   - **Company ID**: `999`
2. Click **Submit**.
   - **Expected Outcome**:
     - A brief loading state is displayed during the synchronous validation check.
     - The modal remains open and displays a toast error: "Invalid credentials" (or "Credenciais inválidas" in pt-BR).
     - No hook is persisted to the database.

---

### Scenario 5: Synchronous Service Downtime / Timeout Handling (US2 / FR-010)

#### Goal
Verify that network timeouts (> 5s) or remote 503 errors halt the save and display "Could not connect to ERP".

#### CLI Test (Simulated Timeout / 503)
```bash
docker compose exec rails bundle exec rails runner "
  require 'webmock'
  include WebMock::API
  WebMock.enable!

  stub_request(:get, /wfh.ichatr.com.br\/webhook\/pessoas/)
    .to_return(status: 503, body: 'Service Unavailable')

  hook = Integrations::Hook.new(
    account: Account.find(1),
    app_id: 'younus',
    settings: { 'token' => 'valid-mock-token', 'id_empresa' => '104' }
  )

  hook.save
  puts 'Error message: ' + hook.errors.full_messages.join(', ')
"
```
- **Expected CLI Output**:
  ```text
  Error message: Could not connect to ERP
  ```

---

### Scenario 6: Successful Connection & Credential Masking (US2 / FR-011)

#### Goal
Verify that valid credentials result in a connected hook, cleartext Company ID, and masked API Token.

#### CLI Test (Simulated 200 OK from Younus)
```bash
docker compose exec rails bundle exec rails runner "
  require 'webmock'
  include WebMock::API
  WebMock.enable!

  stub_request(:get, /wfh.ichatr.com.br\/webhook\/pessoas/)
    .with(query: hash_including({'idEmpresa' => '104', 'nrTelcelpessoa' => '0'}))
    .to_return(status: 200, body: { sucesso: false, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

  hook = Integrations::Hook.find_or_initialize_by(account: Account.find(1), app_id: 'younus')
  hook.settings = { 'token' => '  real-younus-token-xyz  ', 'id_empresa' => ' 104 ' }
  hook.save!

  puts 'Saved hook ID: ' + hook.id.to_s
  puts 'Database token: ' + hook.settings['token']
  puts 'Masked token: ' + hook.masked_settings['token']
  puts 'Company ID: ' + hook.masked_settings['id_empresa']
"
```
- **Expected CLI Output**:
  ```text
  Database token: real-younus-token-xyz
  Masked token: ••••••••
  Company ID: 104
  ```
  *(Confirms whitespace was stripped, token is securely masked in serialization, and company ID is preserved in cleartext).*

#### UI Verification
1. Navigate to `/app/accounts/1/settings/integrations/younus`.
   - **Expected Outcome**:
     - The page shows the Younus integration as **Connected** with a **Disconnect** button.
     - The configuration details section displays:
       - **Company ID**: `104` (in cleartext)
       - **API Token**: `••••••••` (masked with dots)
2. Return to the ERP provider gallery `/app/accounts/1/settings/integrations/erp`.
   - **Expected Outcome**: The Younus card displays a green "Connected" status badge.

---

### Scenario 7: Extensible ERP Provider Framework (US3 / FR-012, FR-013, FR-014)

#### Goal
Verify that the provider adapter contract and factory enforce interface conformance.

```bash
docker compose exec rails bundle exec rails runner "
  # 1. Unknown provider resolution
  begin
    fake_hook = Integrations::Hook.new(app_id: 'unknown_erp')
    Erp::AdapterFactory.build(fake_hook)
    puts 'FAIL: Should have raised ArgumentError'
  rescue ArgumentError => e
    puts 'PASS: Raised expected error: ' + e.message
  end

  # 2. Incomplete adapter subclass contract enforcement
  class IncompleteAdapter < Erp::BaseAdapter; end
  begin
    IncompleteAdapter.new(Integrations::Hook.new(app_id: 'younus')).test_connection
    puts 'FAIL: Should have raised NotImplementedError'
  rescue NotImplementedError => e
    puts 'PASS: Raised expected error: ' + e.message
  end
"
```
- **Expected CLI Output**:
  ```text
  PASS: Raised expected error: Unsupported ERP provider: unknown_erp
  PASS: Raised expected error: IncompleteAdapter must implement #test_connection
  ```

---

## 3. Automated Test Suite Execution

Run the backend and frontend test suites to verify zero regressions:

### 3.1 Backend Specs (RSpec)
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/erp/ \
  custom/spec/models/custom/integrations/ \
  spec/models/integrations/hook_spec.rb
```

### 3.2 Frontend Tests (Vitest)
```bash
docker compose exec vite pnpm test
```

### 3.3 Linting & Style Checks
```bash
docker compose exec rails bundle exec rubocop
docker compose exec vite pnpm eslint
```

### 3.4 Sync Hooks Manifest Audit
```bash
docker compose exec rails ruby bin/sync-custom-module-hooks --check
docker compose exec rails ruby bin/sync-custom-module-hooks --audit
```
- **Expected Outcome**: All hooks present, 0 gaps.
