---
detected_at: b80a0f31ce # short SHA the profile was detected against
ecosystems: [ruby, javascript] # polyglot repo: Rails backend + Vue/Vite frontend
default: ruby # ambiguous path (no extension hint) -> backend is treated as primary
stacks:
  ruby:
    cwd: . # commands below run from repo root; they shell into the `rails` container
    runner: rspec
    single: 'docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file} -e "{name}"'
    file: docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file}
    suite: docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec
    watch: null # no guard-rspec or equivalent in the Gemfile
    coverage: null # simplecov is in the Gemfile/Gemfile.lock and .circleci/config.yml sets COVERAGE=true, but nothing calls SimpleCov.start anywhere in the repo (spec_helper.rb has no reference) - the gem is present but not wired up
    mutation: null # no mutant / cosmic-ray in Gemfile or Gemfile.lock
    acceptance: null # backend has no separate acceptance runner; cross-boundary behavior is covered by `type: :request` specs in the same rspec run
    property: null # no rantly / propcheck / rspec-parameterized in Gemfile.lock
    approval: null
    contract: 'Skooma::RSpec[swagger/swagger.json], auto-included for every `type: :request` spec via spec/rails_helper.rb:92 - validates responses against the OpenAPI schema'
    test_glob: '{spec,custom/spec}/**/*_spec.rb'
    exemplar: # one per test kind the stack can run
      unit: custom/spec/services/custom/scout/value_estimation_service_spec.rb
      request: custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb
    helpers: # test utilities a new test reuses instead of hand-rolling
      - spec/rails_helper.rb
      - spec/spec_helper.rb
      - spec/support/negated_matchers.rb
      - spec/support/file_upload_helpers.rb
      - spec/support/csv_spec_helpers.rb
      - spec/support/instagram_spec_helpers.rb
      - spec/support/slack_stubs.rb
      - spec/support/conversations_unread_counts_helpers.rb
      - spec/support/examples/encrypted_external_credential_examples.rb
      - spec/factories/ # FactoryBot factories, reused (not duplicated) by custom/spec/**
    verified: [single, file, suite]
    suite_baseline: red # see "Ruby suite: red baseline is order-dependent" below - NOT a regression to fix here
    suite_seconds: 977 # 16m17s, full run: 8924 examples, 1 failure, 1 pending
  javascript:
    cwd: . # commands below run from repo root; they shell into the `vite` container
    runner: vitest
    single: 'docker compose exec -T vite env TZ=UTC pnpm vitest run {file} -t "{name}"'
    file: docker compose exec -T vite env TZ=UTC pnpm vitest run {file}
    suite: docker compose exec -T vite pnpm test
    watch: docker compose exec -T vite pnpm test:watch
    coverage: docker compose exec -T vite pnpm test:coverage
    mutation: null # no StrykerJS in package.json/pnpm-lock.yaml devDependencies
    acceptance: 'cd tests/playwright && pnpm run playwright:run' # separate pnpm package (tests/playwright/), Playwright - NOT run by this command, see notes below
    property: null # no fast-check in devDependencies
    approval: 'vitest built-in snapshots (toMatchSnapshot), e.g. app/javascript/shared/components/specs/Spinner.spec.js'
    contract: null
    test_glob: 'app/**/*.{test,spec}.?(c|m)[jt]s?(x)'
    exemplar:
      unit: app/javascript/dashboard/store/modules/specs/opportunities/actions.spec.js
      component: app/javascript/dashboard/components-next/Opportunities/specs/KanbanCard.spec.js
      acceptance: tests/playwright/tests/e2e/ui/inbox-creation-flow.spec.ts # detected, NOT run - see notes
    helpers:
      - vitest.config.ts
      - vitest.setup.js # global stubs: i18n with no messages, FloatingVue, WootModal/NextButton stubs
      - vitest.i18n.js # withFullI18n() - opt-in real i18n messages for specs asserting translated copy
    verified: [single, file, suite, coverage]
    suite_baseline: green
    suite_seconds: 88 # 441 files, 4348 tests, all passed
---

# TDD Stack Profile

## Conventions to match

### Ruby (RSpec)

- Spec files sit under `spec/**/*_spec.rb` (upstream OSS + enterprise) and
  `custom/spec/**/*_spec.rb` (this fork's own module, mirroring the `app/` vs
  `custom/app/` split). `spec/**` mirrors `app/**`/`enterprise/**` one-to-one;
  `custom/spec/**` mirrors `custom/app/**`.
- Every spec starts `require 'rails_helper'` (or `spec_helper` for a pure-Ruby
  unit with no Rails boot). `type:` is inferred from file location
  (`config.infer_spec_type_from_file_location!` in `spec/rails_helper.rb`) - a
  spec under `spec/requests/` is automatically `type: :request`, no explicit tag
  needed.
- Assertions are plain RSpec `expect(...).to`. Doubles use `instance_double` /
  `verify_partial_doubles = true` (`spec/spec_helper.rb`) - stub only what the
  class actually exposes, no loose `double`.
- Data setup uses FactoryBot (`config.include FactoryBot::Syntax::Methods`) for
  models that have a factory in `spec/factories/*.rb` (`create(:account)`,
  `create(:user, ...)`, `create(:custom_attribute_definition, ...)`). Fork-owned
  models with no factory (`Scout`, `PipelineStage`, `PipelineStageRequiredField`,
  `OpportunityActivity`, ...) are built with plain `ModelName.create!(...)`
  directly in a `let` - do not add a factory as a side effect of writing a test.
- `let`/`let_it_be` (test-prof) over custom setup helper methods, matching
  `AGENTS.md`'s "avoid custom helper methods for setup/data" rule.
- `type: :request` specs assert authorization first (`unauthenticated` /
  `unauthorized role` contexts) before the happy path, and get free OpenAPI
  response-shape validation from Skooma against `swagger/swagger.json` - a new
  endpoint needs a swagger entry or its request spec responses fail contract
  validation.
- Negated matcher `not_change` (`spec/support/negated_matchers.rb`) reads better
  than `expect { }.not_to change { }.by(...)` chains.
- Time: `ActiveSupport::Testing::TimeHelpers` (`travel_to`, `freeze_time`) is
  globally included - never stub `Time.now`/`Date.today` by hand.
- Jobs/mailers: `ActiveJob::TestHelper` and `have_enqueued_job`/
  `have_enqueued_mail` are globally included - assert on enqueued jobs, not on
  side effects of a job that hasn't run.
- Exemplars to imitate: `custom/spec/services/custom/scout/value_estimation_service_spec.rb`
  for a plain service/model unit spec, `custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb`
  for a request spec (authz contexts, nested `describe` per HTTP verb + path).

### JavaScript/Vue (Vitest)

- Spec files sit next to what they test, either as `<name>.spec.js` beside the
  source or under a sibling `specs/`/`spec/` directory (both patterns are used
  interchangeably across the tree; match whichever the target directory already
  uses).
- `globals: true` in `vitest.config.ts` - `describe`/`it`/`expect`/`vi` are
  ambient, no explicit import is required, though most existing specs import
  them from `vitest` explicitly anyway; match the file you're extending.
- Doubles are `vi.fn()` / `vi.mock()` - there is no separate mocking library.
  `vitest.config.ts` sets `mockReset: true` and `clearMocks: true` globally, so
  a new spec does not need its own `afterEach(() => vi.clearAllMocks())` purely
  for that purpose (specs that do it anyway, like `KanbanCard.spec.js`, are
  being explicit, not compensating for a gap).
- Vuex modules are tested by importing `actions`/`mutations`/`getters` directly
  and calling them with a hand-built `{ commit, state }`/`{ commit }` - never
  spin up a real Vuex store for a unit test of one module
  (`store/modules/specs/opportunities/actions.spec.js`).
- Vue components are tested with `mount` from `@vue/test-utils`. `vue-router`
  and cross-cutting composables are `vi.mock()`-ed at the top of the file
  (`KanbanCard.spec.js` mocks `useRouter`/`useRoute` and
  `useOpportunityCardFields`). A local Vuex store needed only for the component
  under test is built inline with `createStore({...})`, not imported from the
  app's real store modules.
- i18n: the global `vitest.setup.js` wires an **empty** i18n instance (loading
  all 2500+ locale files in every spec is deliberately avoided) plus
  `FloatingVue` and stubs for `WootModal`/`WootModalHeader`/`NextButton`. A spec
  that asserts on actual translated copy must opt in with
  `withFullI18n()` from `vitest.i18n.js`, called at the top of the file, outside
  any hook.
- Snapshot tests (`toMatchSnapshot`) exist (`Spinner.spec.js`,
  `DateSeparator.spec.js`) for small presentational components - reserve them
  for markup-only assertions, not behavior.
- Exemplars to imitate: `store/modules/specs/opportunities/actions.spec.js` for
  a unit spec (race-condition/async-ordering behavior, not just a happy path),
  `components-next/Opportunities/specs/KanbanCard.spec.js` for a component spec.

### Playwright (E2E, detected but not run by this profile)

- Lives entirely under `tests/playwright/`, its **own** pnpm package (own
  `package.json`, own `node_modules`, own lockfile) - it is not part of the root
  workspace's `pnpm test` and is not in `.github/workflows/run_foss_spec.yml`.
  It targets a real, running Chatwoot instance via `BASE_URL` and a real
  login (`TEST_USER_EMAIL`/`TEST_USER_PASSWORD`) from `tests/playwright/.env`.
- Component Object Model: page objects under `components/ui/`, API helpers
  under `components/api/`, specs under `tests/e2e/ui/` and `tests/e2e/api/`.
  `inbox-creation-flow.spec.ts` is the exemplar: it creates a real inbox through
  the UI and cleans it up in `afterEach` via the API.
- Not run during this setup: hitting it would run UI flows (login, resource
  creation/deletion) against whatever instance `BASE_URL`/`.env` point at, which
  Hard Rule 4 excludes from an unattended run. Before the outer loop uses it,
  confirm which instance it should target and that `.env` credentials exist.

## Notes and constraints

- **Ruby suite: red baseline is order-dependent, not a regression to chase
  down here.** The full run (`bundle exec rspec`, 8924 examples, 977s) reports
  1 failure: `AgentBuilder#perform when user does not exist reserves email
  capacity and enqueues the invitation` (`spec/builders/agent_builder_spec.rb:47`),
  plus 1 known-pending example unrelated to this failure. Re-running that file
  alone (`bundle exec rspec spec/builders/agent_builder_spec.rb`) passes all 12
  examples in 1s. This is test pollution from another spec run earlier in the
  suite bleeding into this one (something upstream of it changes
  `Devise::Mailer#confirmation_instructions`'s arity as observed by
  `have_enqueued_mail`), not something this command's scope covers fixing. Any
  `/speckit.tdd.run` cycle that touches `AgentBuilder`, Devise mailers, or user
  invitation must re-run the **file** command, not trust a green single-test
  result in isolation, and should re-run the full suite before treating a
  feature as done.
- JS suite (88s) and the Ruby single-file/single-test commands (~7-9s each,
  dominated by Zeitwerk eager-load / Vite transform startup, not the test
  itself) are both fast enough for a per-cycle run. The Ruby **full** suite
  (977s / ~16m) is not - use the single-test or single-file command for the
  inner loop and reserve the full suite for a pre-commit/pre-PR gate, matching
  `AGENTS.md`'s existing guidance to scope local backend runs to
  `custom/spec/` plus the specific modified core files during iteration.
- `bundle exec rspec` implicitly needs `env -u FRONTEND_URL RAILS_ENV=test`
  ahead of it in this fork's containers - `docker compose exec` otherwise
  injects the container's `.env` (`RAILS_ENV=development`, a real
  `FRONTEND_URL`) into the process, which breaks redirect-safety and SAML specs
  (see `AGENTS.md`). Every Ruby command in this profile already includes it;
  never drop it.
- All commands assume the compose stack from `AGENTS.md` is already up
  (`docker compose up -d`) - `rails`, `vite`, `postgres`, `redis` were confirmed
  running during this detection.
- No coverage tool is wired for Ruby despite `simplecov`/`simplecov_json_formatter`
  sitting in the `Gemfile`/`Gemfile.lock` and `.circleci/config.yml` (a stale,
  unused CI config - this fork's actual CI is
  `.github/workflows/run_foss_spec.yml`) setting `COVERAGE: true`. Adding
  `SimpleCov.start` to `spec/spec_helper.rb` is the ecosystem default if Ruby
  coverage is wanted; that is a separate, explicit change, not made here.
  `/speckit.tdd.verify` must fall back to trace-checking every Ruby acceptance
  criterion against a named spec rather than a coverage number.
- No mutation-testing tool exists for either stack (no `mutant`/`cosmic-ray`
  gem, no StrykerJS package). `/speckit.tdd.verify` must use the
  deliberate-mutant spot-check fallback for both stacks.
- No property-based library exists for either stack (no `rantly`/`propcheck`
  gem, no `fast-check` package). Invariants become explicit boundary-value
  example tests; note in the test list that the invariant is sampled, not
  proven.
