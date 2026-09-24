# Implementation Plan: Scout Tool "Test" Uses Real Saved Credential, Not the Masked Placeholder

**Branch**: `080-scout-tool-test-secret` | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/080-scout-tool-test-secret/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

`ScoutToolsController#test` never loads the `ScoutTool` being edited, so it forwards whatever
credential value the form currently holds — which is `ScoutTool::MASKED_SECRET` (`'••••••••'`)
or blank for any already-saved tool, since the read path (`masked_auth_headers`) never returns
the real secret and the Vue modal defaults the field to that placeholder. The external API then
rejects the placeholder, producing a false 401/403 even when the saved credential is correct.
The fix: (1) extract the existing masked/blank reconciliation logic already used by `update`
(`ScoutTool#apply_credentials_update` / `merge_preserved_secrets`) into a new, non-persisting
public method `ScoutTool#auth_headers_for_test`; (2) have the frontend send the tool's `id` with
the test payload when editing an existing tool; (3) have the controller resolve that `id` scoped
to `Current.account`, and when it resolves, reconcile the submitted `auth_headers` through the
new method before building `HttpRequestExecutor`. An unresolved id (absent, foreign account, or
brand-new unsaved tool) falls through to today's unchanged behavior — literal submitted value,
no substitution, no distinct error.

**Language/Version**: Ruby (Rails, matches repo's existing `custom/` module), Vue 3 (Composition
API, `<script setup>`)

**Primary Dependencies**: None new. Existing: `ScoutTool` (ActiveRecord, `encrypts
:auth_headers`), `Custom::Scout::Tools::HttpRequestExecutor`, `ScoutAPI` (`dashboard/api/scout`
axios client), `ScoutToolModal.vue`.

**Storage**: PostgreSQL via existing `ichatr_scout_tools` table — no schema change.

**Testing**: RSpec (`custom/spec/models/scout_tool_spec.rb`,
`custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`, `type: :request`) and
Vitest (new `ScoutToolModal.spec.js` under
`app/javascript/dashboard/components-next/Scout/pageComponents/specs/`).

**Target Platform**: Existing Chatwoot dashboard (browser) + Rails API, containerized dev stack.

**Project Type**: Web application (existing Rails backend + Vue frontend monorepo; fork-specific
module under `custom/`).

**Performance Goals**: N/A — single synchronous request-scoped credential lookup by primary key,
no measurable throughput/latency impact over the current behavior.

**Constraints**: Must not change the response shape of `GET/index`/`show` (masking stays
unchanged, FR-007); must not introduce a distinguishable response for a foreign/nonexistent tool
id (FR-008, security-relevant — no account-enumeration side channel).

**Scale/Scope**: One controller action, one new model method, one Vue component's test payload
construction. No new files beyond specs.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. All touched files (`custom/app/models/scout_tool.rb`,
  `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb`,
  `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue`) are
  fork-owned (`custom/` tree or a fork-original Scout component with no upstream equivalent) —
  no upstream/core file is touched, no extension point needed.
- **II. Smallest Production-Ready Change**: PASS. No route change (Decision 2 in `research.md`);
  reuses existing merge helpers instead of new abstractions; one new method, one new optional
  param, one new conditional payload key.
- **III. Adhere to Established Conventions**: PASS. Ruby/RuboCop line length, Vue Composition API
  `<script setup>`, existing i18n keys (no new user-facing strings needed — the fix is silent
  reconciliation, not a UI change per spec Assumptions).
- **IV. Safe, Reversible Change Management**: PASS. Purely additive/corrective diff; no
  destructive operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (N/A). Scout Tools is a fork-exclusive
  `custom/` feature with no OSS or `enterprise/` counterpart to check.
- **VI–IX. TDD / Observable Behavior / Functional Slice / Surgical Scope**: PASS (binding for
  implementation phase). New specs will be written to fail first, exercise the real
  `type: :request` entry point and the real Vue component, mock only the external boundary
  (`SafeFetch.fetch`, matching the existing `test` spec's convention) — never the `ScoutTool`
  model or `HttpRequestExecutor` internals. Test runs stay scoped to the two RSpec files and the
  one Vitest file listed in Testing above; no full-suite run during iteration.

No violations. Complexity Tracking section left empty.

## Project Structure

### Documentation (this feature)

```text
specs/080-scout-tool-test-secret/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── scout-tools-test-endpoint.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
custom/
├── app/
│   ├── controllers/api/v1/accounts/scout_tools_controller.rb   # test action + test_params (id)
│   └── models/scout_tool.rb                                    # new auth_headers_for_test
└── spec/
    ├── controllers/api/v1/accounts/scout_tools_controller_spec.rb
    └── models/scout_tool_spec.rb

app/javascript/dashboard/components-next/Scout/pageComponents/
├── ScoutToolModal.vue          # handleTest: include id in testPayload when editing
└── specs/
    └── ScoutToolModal.spec.js  # new
```

**Structure Decision**: No new project/directory. This is a bugfix confined to the fork's
existing `custom/` Rails module (model + controller) and the existing fork-original Vue component
`ScoutToolModal.vue` under `app/javascript/dashboard/components-next/Scout/pageComponents/`. Specs
land beside their existing counterparts in `custom/spec/` and a new `specs/` sibling directory for
the Vue component, matching the layout every other tested `components-next` component already
uses.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations to record — Constitution Check above is a full PASS.
