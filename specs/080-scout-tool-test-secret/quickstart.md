# Quickstart: Validating the Scout Tool "Test" Credential Fix

Prerequisites: stack running (`docker compose up -d`), per `AGENTS.md`.

## 1. Automated validation (primary proof)

Run the two targeted spec files this feature adds cases to — do not run the full suite mid-work
(Constitution Principle IX):

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/scout_tool_spec.rb \
  custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb

docker compose exec vite pnpm vitest run \
  app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutToolModal.spec.js
```

Expected: every new example (see `tasks.md` once generated) fails before the implementation
lands and passes after, per Constitution Principle VI/VIII. No existing example in either file
regresses.

## 2. Manual end-to-end scenario (matches User Story 1 / SC-001, SC-002)

1. In the dashboard, open Scout → Tools and create (or reuse) an external tool with `auth_type:
   bearer` and a real, working bearer token pointed at a reachable test endpoint (e.g. a local
   `httpbin`-style echo, or any endpoint you control that validates the `Authorization` header).
2. Save the tool. Re-open it for edit — confirm the token field shows only `••••••••`
   (User Story 3 / non-regression).
3. Without touching the credential field, click **Test**. Confirm the request reaches the real
   endpoint with the real token (200/expected response), not a 401/403 caused by sending the
   literal `••••••••` string.
4. Clear the token field entirely (leave blank), click **Test** again — confirm identical success
   (FR-002, blank treated same as masked).
5. Type a deliberately wrong token into the field, click **Test** — confirm the external endpoint
   now rejects it (proves the *typed* value is what's sent, not a silent fallback to the old
   saved good token — FR-003).
6. Start a brand-new, unsaved tool, leave the credential field at its default/blank, click
   **Test** — confirm behavior is unchanged from before this fix (no saved credential exists to
   substitute; the literal blank/placeholder is what's sent) — User Story 2 / SC-004.

## 3. Contract reference

See `contracts/scout-tools-test-endpoint.md` for the exact request/response shape and the
resolved edge-case behavior (missing/foreign `id`) exercised by scenario 6 and by the
cross-account case covered in the automated request specs.

See `data-model.md` for the new `ScoutTool#auth_headers_for_test` method signature exercised
directly by the model spec additions.
