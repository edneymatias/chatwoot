# Quickstart & Validation Guide: ERP Contact Panel Data Card

**Branch**: `075-erp-contact-data-card`
**Date**: 2026-09-18
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

---

## 1. Prerequisites & Environment Setup

Ensure the container stack is running per `AGENTS.md`:

```bash
# Verify containers are running
docker compose ps

# Start stack if not already running
docker compose up -d
```

Services: `rails` (:3000), `vite` (:3036), `postgres` (:5432), `redis` (:6379).

---

## 2. Test Execution Commands

### 2.1 Backend Tests (RSpec)

Run targeted unit and request specs:

```bash
# Erp::BaseAdapter and Erp::Younus::Adapter unit specs
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/erp/base_adapter_spec.rb \
  custom/spec/services/erp/younus/adapter_spec.rb \
  custom/spec/services/erp/younus/client_spec.rb

# ErpController request spec
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb

# Full custom spec suite
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/
```

### 2.2 Frontend Tests (Vitest)

Run component, store, and composable specs:

```bash
# ErpDataCard component spec (covers whitelist, formatting, sub-objects, error handling)
docker compose exec vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js

# useUISettings and integrations store specs
docker compose exec vite env TZ=UTC pnpm vitest run \
  app/javascript/dashboard/composables/spec/useUISettings.spec.js \
  app/javascript/dashboard/store/modules/specs/integrations/getters.spec.js
```

### 2.3 Linting & Code Quality

```bash
# Backend RuboCop
docker compose exec rails bundle exec rubocop \
  custom/app/services/erp/ \
  custom/app/controllers/api/v1/accounts/integrations/erp_controller.rb

# Frontend ESLint
docker compose exec vite pnpm eslint \
  app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue \
  app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js
```

---

## 3. Manual Validation Scenarios

### Scenario 1: Customer ERP Data Whitelist & Friendly Labels (P1 / SC-001 / SC-008)
1. In Chatwoot dashboard, log in as an agent in an account with an active Younus ERP integration.
2. Open a conversation whose contact has phone number `+5541996937898` matching an ERP customer record.
3. Observe the right-hand Contact Panel:
   - "ERP Data" accordion appears immediately below "Contact Attributes" and is expanded by default.
   - Shows loading spinner briefly (< 2 seconds), then renders curated customer data.
   - **Technical IDs excluded**: `idPessoa`, `idEmpresa`, `pessoaTipo`, `tpPessoa`, `nmPaispessoa`, `stTermo`, `stCadastro`, `stPessoa`, `indClientePadrao` are NOT visible.
   - **Friendly labels**: `nmPessoa` is labeled "Nome", `nrCpfcnpjpessoa` is labeled "CPF", `nrRgpessoa` is labeled "RG" and positioned immediately adjacent to CPF.
   - **Medical Chart**: `nrFicha` is labeled "Prontuário".
   - **Strict Whitelist**: Unmapped or null fields are completely omitted.

### Scenario 2: Brazilian Document & Telephone Masks (P1 / FR-022 / SC-011)
1. In the customer data card:
   - Verify `nrCpfcnpjpessoa` is displayed with mask `000.000.000-00` (for CPF) or `00.000.000/0000-00` (for CNPJ).
   - Verify `nrCeppessoa` is displayed with mask `00000-000`.
   - Verify `nrTelcelpessoa` is displayed with mask `(00) 00000-0000`.
   - Verify `nrTelrespessoa` is displayed with mask `(00) 0000-0000`.
   - Verify irregular strings safely fall back to the raw value without throwing errors.

### Scenario 3: Birthday Highlight & Date Formatting (P1 / FR-018 / SC-009)
1. Open a contact whose `dtNascpessoa` matches today's calendar day and month:
   - Date of birth displays formatted in browser locale without time component (`DD/MM/YYYY`).
   - A prominent birthday highlight badge (`🎂 Aniversariante hoje` / `Birthday today`) appears.
2. Open a contact whose birthday is on a different date:
   - Date of birth displays formatted without time, and no birthday badge appears.

### Scenario 4: Appointments Sub-object & Confirmation Highlight (P1 / FR-020 / SC-010)
1. In the "Atendimentos" section of the card:
   - **Último atendimento**: displays localized date/time, professional name (`comQuem`), and attendance status.
   - **Próximo atendimento**: displays localized date/time, professional name (`comQuem`), and confirmation status.
   - When `confirmado === true`, a prominent confirmation badge ("Confirmado") is displayed.
   - When `proximo` is null, a friendly indicator ("Nenhum agendamento futuro") is displayed.

### Scenario 5: Financial Sub-object, Debtor Warning & Oldest Overdue Installment (P1 / FR-021 / SC-010)
1. In the "Financeiro" section of the card:
   - When `devedor === true`, a prominent warning badge ("Devedor") is displayed at the top of the financial section.
   - **Parcela vencida mais antiga**: `parcelaVencida` is clearly labeled as "Parcela vencida mais antiga", showing localized due date, original amount, and corrected amount formatted as currency (`R$ 250,00`).
   - **Próxima parcela**: displays localized due date and currency amount.
   - **Resumo financeiro**: `totalFinanceiro`, `totalRecebido`, `totalAberto`, and `totalDevedor` are displayed formatted as currency in the browser locale.

### Scenario 6: Audit Footnotes at Card Bottom (P1 / FR-019)
1. Look at the very bottom of the card:
   - `dtCadpessoa` ("Data de cadastro") and `dtUltaltpessoa` ("Data de atualização") appear in italics and smaller font as footnotes.
   - Timestamps are formatted according to the browser's active locale.

### Scenario 7: Multiple Matches Indicator (P1 / FR-006 / FR-012)
1. Open a conversation for a contact whose phone number returns multiple matching customer records in the ERP.
2. Verify:
   - First customer record is displayed.
   - An informational badge appears at the top: *"Multiple records found for this phone in the ERP."* (or Portuguese translation).
   - Refreshing re-fetches without errors.

### Scenario 8: Cached ID Lookup & Stale Link Recovery (P1 / SC-002 / SC-003)
1. Open the conversation from Scenario 1 a second time:
   - Data loads instantly using the cached identifier (`find_by_id`) without performing a phone search.
2. Change the contact's phone number to a different number that also exists in the ERP.
3. Refresh the ERP Data card using the header refresh button:
   - System detects the phone mismatch on the cached record.
   - Cached ID is automatically cleared.
   - Single phone search executes and matches the new number.
   - New ID is cached and updated customer details are displayed.

### Scenario 9: Friendly Empty State — Unregistered Contact (P2 / SC-005)
1. Open a conversation for a contact with phone number `+5511900000000` (not registered in ERP).
2. Verify:
   - Card displays friendly empty state suggesting customer registration in the ERP.
   - No error banners or broken elements appear.

### Scenario 10: Friendly Empty State — Contact Without Phone (P2 / FR-006)
1. Open a conversation for a contact with no phone number registered.
2. Verify:
   - Card immediately displays message stating a phone number is required to search in the ERP.
   - Zero remote HTTP calls are made to the ERP.

### Scenario 11: Service Resilience on ERP Downtime (P1 / SC-004)
1. Temporarily point ERP credentials to an unreachable host or simulate HTTP 503.
2. Open conversation with ERP card:
   - Card displays localized error message with a "Retry" button.
   - Contact panel, conversation messages, and conversation switching continue functioning without disruption.
   - Clicking "Retry" re-attempts the query.

### Scenario 12: Account Without ERP Integration (SC-006)
1. Switch to an account that has no enabled ERP hook.
2. Open any conversation.
3. Verify:
   - No "ERP Data" card appears in the contact panel.
   - No requests are sent to `/api/v1/accounts/:account_id/integrations/erp/data`.
