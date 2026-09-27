# Implementation Plan: Scout V2 Identity and Style Settings

**Branch**: `086-scout-v2-identity-settings` | **Date**: 2026-09-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/086-scout-v2-identity-settings/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

Give the Scout V2 engine an account-specific Identity and make its style settings editable without
the console. Two new nullable `text` columns on the fork-owned `ichatr_scouts` table — `role` and
`scope` — normalized by Rails `normalizes` (ends stripped, blank ⇒ `nil`) and length-validated
(≤ 500 after normalization) on `Scout`. `Custom::ScoutV2::Instructions::IdentityBuilder` swaps each
Default Identity statement independently: Role replaces the qualifier-bearing intro (→ neutral
intro) and the purpose statement; Scope replaces the scope statement; both empty stays
byte-identical to today. `ScoutsController#scout_params` permits the five fields, and a
`before_action` rejects any `tone`/`response_length` that is not a documented String name
(including `1` and `"1"`, which today cast silently or 500) with a translated 422 before anything
is written. `ScoutGeneralSettings.vue` gains an always-visible section with Role/Scope (TextArea,
500 counter), Tone/Response length (`Select`, translated closed lists) and Greeting, sent in the
existing save payload. V1 (`SystemPromptsService`) and Persona are untouched; invariance is pinned
by specs.

## Technical Context

**Language/Version**: Ruby 3.4.4 / Rails 7.2.3.1 (container); JavaScript (Vue 3.5, `<script setup>`)

**Primary Dependencies**: ActiveRecord `normalizes` + `enum` (Rails 7.2), `rails-i18n` (present but
keyed `pt-BR`, so pt_BR messages must be added — research §2), existing
`Custom::ScoutV2::Instructions::{Builder,IdentityBuilder,CommunicationBuilder}`, `components-next`
`TextArea`/`Select`/`Input`, `vue-i18n`, `dashboard/api/scout`

**Storage**: PostgreSQL — one additive migration (`add_column` × 2, `text`, nullable) on
`ichatr_scouts`; no backfill

**Testing**: RSpec (`type: :request` for the API, model/service specs against the real test DB, no
doubles except the existing `RubyLLM::Chat` boundary in `turn_runner_spec.rb`; `freeze_time` for the
V1 prompt comparison); Vitest + `@vue/test-utils` for the settings component, `ScoutAPI` mocked at
the HTTP-client boundary (existing Scout tab spec convention), `withFullI18n` for translated-copy
assertions

**Target Platform**: Rails app server + Vite dashboard SPA, containerized (rootless Podman)

**Project Type**: Web application (Rails monolith with fork-owned `custom/` tree + Vue dashboard)

**Performance Goals**: No new queries per turn (Role/Scope are columns on the already-loaded
scout); no extra LLM calls; Identity build stays string concatenation

**Constraints**: Default Identity byte-identical when Role/Scope empty (SC-003); V1 prompt
byte-identical (SC-004); no 5xx for any Tone/Response length/Role/Scope input (SC-006); en + pt_BR
for all new UI and error strings (FR-013, FR-021); no upstream/Enterprise file edits

**Scale/Scope**: 1 migration, 1 model (2 lines of rules), 1 controller (permit list +
1 `before_action`), 1 builder, 1 Vue component, 2 JSON + 2 YAML locale files; specs: 1 new builder
spec, 1 new component spec, extensions to 5 existing spec files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Upstream Compatibility First | PASS | Backend changes live in `custom/` (model, controller, V2 builder); migration is additive on a fork-prefixed table under the allowed `db/migrate/2126…` exception; Vue component, `scout.json`, `config/locales/{en,pt_BR}.yml` are fork-owned/already excluded in `bin/sync-custom-module-hooks` (research §9). No upstream/Enterprise file edited → no MANIFEST entry required. |
| II. Smallest Production-Ready Change | PASS | Exactly the brief's §5 touch points. Enum check lives only at the request boundary (no `validate: true` duplicate, research §1); length/normalization only on the model; no controller duplicate for Role/Scope; `CommunicationBuilder` and V1 untouched; no flag gating, no Persona migration, no screen error-display rework. |
| III. Established Conventions | PASS | Error body reuses the controller's `{ error: full_messages }` shape; i18n keys follow the `scout_tool` `activerecord.errors.models…` precedent; UI uses `components-next` `TextArea`/`Select`/`Input` with Tailwind utilities and existing hint pattern; `<script setup>`; en + pt_BR synchronously; LLM-facing Identity prose stays Portuguese in code, as in Brief 04. |
| IV. Safe, Reversible Change | PASS | Reversible `change` migration; no destructive op. `schema.rb` regeneration verified for contamination per `AGENTS.md`. |
| V. Dual-Tree Awareness | PASS | `grep -rln '\bScout\b' enterprise/` → none; no Enterprise overlay for Scout; API contract shared, recorded here. |
| VI. TDD | PASS (carried into `/speckit.tasks`) | Every FR/acceptance scenario maps to a failing-first test at a real entry point: request spec for API (US3), builder specs for Identity (US1), component spec for the screen (US2). |
| VII. Observable Behavior / Mutation Resistance | PASS (carried) | Identity asserted by exact-string equality per case (a swapped slot, missing fallback, or `squish` mutant fails); API asserted on response body + reloaded DB state (name and required attributes unchanged on reject); V1 asserted by full-prompt equality before/after. Only doubles: `ScoutAPI` HTTP client in Vitest, `RubyLLM::Chat` already in `turn_runner_spec.rb`. |
| VIII. Functional Slices | PASS (carried) | Three slices = three user stories (Identity; API; screen), each built with its full happy/boundary/error matrix; no step journals. |
| IX. Surgical Execution | PASS (carried) | Quickstart §1 lists the exact spec files; full suites reserved for pre-release. |

**Post-design re-check (after Phase 1)**: unchanged — PASS on all principles. Design adds no
abstraction beyond the brief, no new files outside `custom/`, `db/migrate/`, the Scout Vue tree and
locale files, and no backup guards.

## Project Structure

### Documentation (this feature)

```text
specs/086-scout-v2-identity-settings/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── identity_section.md
│   ├── scouts_api.md
│   └── general_settings_ui.md
├── checklists/
│   └── requirements.md  # from /speckit.specify
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
db/migrate/
└── 21260927000000_add_role_and_scope_to_ichatr_scouts.rb   # NEW — add_column role/scope (text)
db/schema.rb                                                # regenerated (2 columns only)

custom/app/
├── models/scout.rb                                         # + normalizes :role, :scope; + length ≤ 500
├── controllers/api/v1/accounts/scouts_controller.rb        # + 5 fields in scout_params; + before_action enum check (create/update)
└── services/custom/scout_v2/instructions/
    └── identity_builder.rb                                 # intro/purpose ← role, scope-statement ← scope, independent fallback

config/locales/
├── en.yml                                                  # + activerecord.attributes.scout.*, activerecord.errors.models.scout.*
└── pt_BR.yml                                               # same keys, Portuguese

app/javascript/dashboard/
├── components-next/Scout/pageComponents/
│   ├── ScoutGeneralSettings.vue                            # + V2 section (role, scope, tone, response_length, greeting) + payload
│   └── specs/ScoutGeneralSettings.spec.js                  # NEW
└── i18n/locale/{en,pt_BR}/scout.json                       # + SCOUT.GENERAL.* keys (contracts/general_settings_ui.md)

custom/spec/
├── models/scout_spec.rb                                    # + normalization / length boundary
├── controllers/api/v1/accounts/scouts_controller_spec.rb   # (type: :request) + US3 matrix, create/show, pt_BR message
└── services/custom/
    ├── scout_v2/instructions/
    │   ├── identity_builder_spec.rb                        # NEW — 4 cases exact text, multi-line, persona absent
    │   └── builder_spec.rb                                 # + persona absent from all sections
    ├── scout_v2/turn_runner_spec.rb                        # + saved role/scope reach composed instructions (FR-019)
    └── scout/system_prompts_service_spec.rb                # + V1 prompt identical before/after setting the 5 fields
```

**Structure Decision**: Rails monolith with the fork-owned `custom/` overlay for all backend
logic (model, controller, V2 builder), one additive migration on the fork-prefixed table, and the
existing fork-owned Scout Vue page component + `scout.json` locale files for the UI. No new
directories, no upstream or Enterprise files.

## Design Notes by User Story

- **US1 (P1) Identity** — [contracts/identity_section.md](./contracts/identity_section.md).
  Tests: `identity_builder_spec.rb` asserts the full section string for the four Role/Scope
  combinations (incl. a multi-line Scope and a Role with internal line breaks), and Persona absence;
  `builder_spec.rb` asserts Persona absence across all four sections and that `[Safety]` keeps its
  anti-hallucination/commercial-scope rules with Role/Scope empty and filled; `system_prompts_service_spec.rb`
  asserts V1 prompt equality before/after under `freeze_time`; `turn_runner_spec.rb` asserts saved
  Role/Scope appear in the instructions handed to `with_instructions`.
- **US3 (P3) API** — [contracts/scouts_api.md](./contracts/scouts_api.md). Built before US2 so the
  screen has a working endpoint. Request-spec matrix: valid update/create/show echo the five fields;
  rejects `tone` ∈ {`"bogus"`, `1`, `"1"`, `""`, `null`} and the same set for `response_length`, each
  sent with a `name` change **and** `required_custom_attribute_definition_ids` (both unchanged after);
  a `POST` with `tone: 1` returns 422 and creates no scout; Role/Scope 501 rejected, 500 + padding
  accepted and stored trimmed; whitespace-only ⇒ `null`; the exact message for each of `tone`,
  `response_length`, `role`, `scope` is asserted under an en requester and under a pt_BR requester.
  Backend locale keys are added after this spec is observed failing (Constitution VI). Model spec
  covers normalization on direct writes.
- **US2 (P2) Screen** — [contracts/general_settings_ui.md](./contracts/general_settings_ui.md).
  Built after US3 (the screen saves through the US3 endpoint). Component spec covers the seven
  observable behaviors listed there, including concrete hint texts and pt_BR rendering.

## Complexity Tracking

No violations — table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
