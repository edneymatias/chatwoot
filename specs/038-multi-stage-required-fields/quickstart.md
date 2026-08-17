# Quickstart & Validation Guide: Multi-Stage Required Fields

This guide details the validation procedures to verify that custom attributes can be required across multiple stages in the same pipeline without cross-stage interference or regression in opportunity transition enforcement.

## Prerequisites

1. Stack running in Docker Compose (`docker compose up -d`).
2. An account with the `opportunities` feature enabled.
3. At least two pipeline stages (e.g., "Stage A", "Stage B") and at least one opportunity custom attribute definition (e.g., `budget_confirmed`).

---

## Automated Validation (Test Suite)

Run the targeted RSpec suite covering models, controllers, and opportunity validations:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/pipeline_stage_required_field_spec.rb \
  custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb \
  spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb \
  spec/models/opportunity_spec.rb
```

### Expected Results:
- All specs pass with 0 failures.
- Uniqueness validation spec confirms scope is `[:account_id, :pipeline_stage_id]`.
- Controller specs confirm configuring attribute on Stage B does not remove it from Stage A.
- Opportunity specs confirm moving through Stage A and then Stage B does not re-prompt if the attribute was already populated.

---

## Manual End-to-End Validation Scenarios

### Scenario 1: Multi-Stage Requirement Configuration (User Story 1 / FR-001)

1. Navigate to **Settings > Pipeline Stages**.
2. Edit **Stage A** (e.g., "Qualification") and check custom attribute `Budget Confirmed` as required. Save.
3. Edit **Stage B** (e.g., "Proposal") and check the same custom attribute `Budget Confirmed` as required. Save.
4. **Verification**:
   - Both stages save successfully without errors.
   - Re-opening edit modal for Stage A shows `Budget Confirmed` is still checked.
   - Re-opening edit modal for Stage B shows `Budget Confirmed` is still checked.

### Scenario 2: Forward Opportunity Move with Preserved Attribute Value (User Story 2 / FR-003, FR-004)

1. Create a new opportunity in **Stage A** without `Budget Confirmed`.
2. Attempt to move the opportunity forward to **Stage B**.
3. **Verification**:
   - The move is blocked, indicating missing required field `Budget Confirmed`.
4. Fill in `Budget Confirmed` on the opportunity and advance it to **Stage B**.
5. **Verification**:
   - The move succeeds.
6. Now attempt to advance the opportunity to **Stage C** (which also requires `Budget Confirmed`).
7. **Verification**:
   - The move succeeds immediately without blocking or prompting again for `Budget Confirmed`.

### Scenario 3: Independent Stage Requirement Removal (User Story 1 / FR-005)

1. Edit **Stage A** and uncheck `Budget Confirmed`. Save.
2. Verify **Stage B** still has `Budget Confirmed` configured as required.
3. Create a new opportunity in Stage A (without `Budget Confirmed`) and attempt to move it directly to Stage B.
4. **Verification**:
   - Move to Stage B is blocked because Stage B's requirement remains active and intact.

---

## References

- [Data Model Specification](./data-model.md)
- [API Contracts](./contracts/pipeline-stage-required-fields-api.md)
- [Feature Specification](./spec.md)
