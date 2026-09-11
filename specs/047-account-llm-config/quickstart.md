# Quickstart & Validation Guide: Account-Level LLM Configuration

## 1. Prerequisites

- Docker container stack running: `docker compose up -d`
- Active account created and accessible via web interface (`http://localhost:3000`)
- Database migrations applied.

## 2. Validation Scenarios

### Scenario 1: Configure Account LLM Settings
1. Log in as an Administrator (`admin@example.com`).
2. In the sidebar, expand the **Scout** menu item.
3. Verify the submenu contains:
   - **Agentes** (Agents)
   - **Configurações** (Settings)
   - **Ferramentas** (Tools)
4. Click on **Configurações**.
5. Select a provider (e.g., Google Gemini), input model name `gemini-2.5-flash`, and enter a valid API key.
6. Click **Salvar** (Save).
7. Verify:
   - Save succeeds with success alert.
   - API key input resets to blank with placeholder indicating the key is configured.

### Scenario 2: Create a Scout Agent
1. Navigate to **Scout > Agentes**.
2. Click **Criar Scout** (Create Scout).
3. Verify that provider, model, and API key inputs are **not present** in the dialog.
4. Fill in Scout Name and Persona, then save.
5. Verify Scout is created successfully and uses the account-level LLM configuration.

### Scenario 3: Verify Gating for Unconfigured Account
1. On an account without an LLM configuration, navigate to **Scout > Agentes**.
2. Attempt to create a Scout or use tools.
3. Verify that the UI displays a gating prompt/empty state redirecting the administrator to complete LLM configuration first.

### Scenario 4: Automated Test Execution
Run targeted test suites inside the Rails container:
```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/scout_spec.rb custom/spec/models/scout_account_config_spec.rb custom/spec/controllers/api/v1/accounts/scout_account_configs_controller_spec.rb
```

Frontend lint & test verification:
```bash
docker compose exec vite pnpm eslint
docker compose exec vite pnpm test
```
