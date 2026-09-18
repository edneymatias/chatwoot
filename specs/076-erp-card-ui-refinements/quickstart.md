# Quickstart & Validation Guide: ERP Contact Card UI Refinements

**Branch**: `076-erp-card-ui-refinements`
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

### 2.1 Targeted Frontend Component Tests (Vitest)

All behavioral criteria for this feature are verified through Vitest specs in `ErpDataCard.spec.js`:

```bash
# Run ErpDataCard component spec
docker compose exec vite env TZ=UTC pnpm vitest run \
  app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js
```

### 2.2 Frontend Linting

```bash
# Run ESLint on modified files
docker compose exec vite pnpm eslint \
  app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue \
  app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js
```

---

## 3. Manual Verification Scenarios

### Scenario 1: Consolidated Single-Line Address (US-1, FR-001, FR-002, FR-003)

1. **Full Address**:
   - Given a contact with `nmEndpessoa: "Rua das Flores"`, `nrEndpessoa: "123"`, `compEndpessoa: "Apto 45"`, `nmBaipessoa: "Centro"`, `nmCidpessoa: "Curitiba"`, `ufEndpessoa: "PR"`, `nrCeppessoa: "80000000"`.
   - **Expected**: A single attribute row labeled "Endereço" displays:
     `Rua das Flores, 123, Apto 45, Centro, Curitiba/PR - 80000-000`.
   - None of the 7 individual address fields appear as separate rows.
2. **Missing Complement**:
   - Given `compEndpessoa: null` or empty string.
   - **Expected**: Address displays: `Rua das Flores, 123, Centro, Curitiba/PR - 80000-000` (no double comma `,,`).
3. **Only City/UF**:
   - Given only `nmCidpessoa: "Curitiba"` and `ufEndpessoa: "PR"`.
   - **Expected**: Address displays: `Curitiba/PR` (no trailing commas or dangling hyphens).
4. **Only CEP**:
   - Given only `nrCeppessoa: "80000000"`.
   - **Expected**: Address displays: `80000-000` (no dangling hyphen prefix `- `).
5. **No Address Fields**:
   - Given all address fields null or empty.
   - **Expected**: The "Endereço" row is omitted entirely from the card.

---

### Scenario 2: Primary Phone Display & Inline Disclosure Accordion (US-2, FR-004, FR-005, FR-006)

1. **Only Cell Phone**:
   - Given `nrTelcelpessoa: "11987654321"` with no other phones.
   - **Expected**: Displays `Celular: (11) 98765-4321`. No ellipsis button (`...`) is present.
2. **Cell Phone + Secondary Phones**:
   - Given `nrTelcelpessoa: "11987654321"` and `nrTelrespessoa: "1134567890"`.
   - **Expected**: Displays `Celular: (11) 98765-4321` with an adjacent ellipsis button `...` (`data-testid="erp-phone-expand-toggle"`).
   - Secondary phone is NOT visible in the DOM initially.
3. **Clicking the Ellipsis Button**:
   - Click `...`.
   - **Expected**: Expands inline to reveal:
     - `Telefone residencial: (11) 3456-7890` (`data-testid="erp-secondary-phone-row"`).
4. **Clicking Again to Collapse**:
   - Click `...` again.
   - **Expected**: Collapses back to only `Celular: (11) 98765-4321`.
5. **Fallback to Secondary When Cell Absent**:
   - Given `nrTelcelpessoa: null`, `nrTelrespessoa: "1134567890"`, and `nrTelcompessoa: "1133334444"`.
   - **Expected**: Displays `Telefone residencial: (11) 3456-7890` as the primary row with `...` button. Clicking `...` expands `Telefone comercial: (11) 3333-4444`.

---

### Scenario 3: Redesigned Clean Appointments List (US-3, FR-007)

1. **Both Past and Next Appointments Populated**:
   - Given `atendimentos.ultimo` with date, professional, attended `true`, and `atendimentos.proximo` with date, professional, confirmed `true`.
   - **Expected**:
     - No dark box frames (`bg-n-alpha-1 border border-n-weak`).
     - "Último atendimento" row shows formatted date/time, attending professional, and subtle attendance badge.
     - "Próximo atendimento" row shows formatted date/time, scheduled professional, and subtle teal `Confirmado` badge.
     - Overall appointments section height is reduced by > 30% compared to boxed design.
2. **No Upcoming Appointment**:
   - Given `atendimentos.proximo: null`.
   - **Expected**: "Próximo atendimento" displays clean subtle text "Nenhum agendamento futuro" without an empty box frame.

---

### Scenario 4: Centered Registration Audit Timestamps (US-4, FR-008, FR-009, FR-010)

1. **Both Timestamps Present**:
   - Given `dtCadpessoa` and `dtUltaltpessoa` present.
   - **Expected**: Both timestamps centered at the bottom of the card on a single line separated by `•`. Wraps gracefully on narrow sidebars without overflow.
2. **Single Timestamp Present**:
   - Given only `dtCadpessoa` present.
   - **Expected**: Timestamp centered without the bullet dot separator.
3. **No Timestamps Present**:
   - Given both null.
   - **Expected**: Audit footnote block omitted completely.

---

### Scenario 5: Synchronous Localization Parity (FR-011, SC-006)

1. Switch language between English and Brazilian Portuguese.
2. **Expected**:
   - Address label translates cleanly: "Address" (EN) vs. "Endereço" (pt-BR).
   - Phone expand toggle tooltip translates: "Show all phone numbers" / "Show main phone only" vs. "Ver todos os telefones" / "Exibir apenas telefone principal".
   - Appointments and footnote labels match locale definitions.
