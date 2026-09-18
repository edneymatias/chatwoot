# Chatwoot (Personal Fork) Constitution

## Core Principles

### I. Upstream Compatibility First (NON-NEGOTIABLE)
This fork exists to layer personal customizations on top of Chatwoot, not to diverge from it.
Every change MUST be evaluated against one question: "would this make it harder to pull in
future upstream `develop` changes?" Prefer additive, isolated changes over edits to shared core
files. When a customization requires touching core OSS behavior, it MUST go through an existing
extension point (`prepend_mod_with`/`include_mod_with`, configuration, feature flags, the
`enterprise/` overlay) rather than a hard fork of the file. Renaming, relocating, or restructuring
files that exist upstream is prohibited unless upstream has already done so — mirror upstream's
shape, don't reinvent it.

When a customization can be built either by editing an existing core/enterprise file (coupled,
simpler, faster today) or by isolating it behind an explicit extension point (decoupled, more
engineering up front), the decoupled approach MUST be chosen. Concretely: new fork-specific
domain features live in their own isolated top-level tree (e.g. `custom/`), mirroring the
`enterprise/` overlay convention rather than being interleaved into `app/`; database tables use a
fork-specific prefix so they can never collide with an upstream table of the same name if
upstream later ships the same feature natively; the tree is wired into the app via the smallest
possible edit to core config (ideally one line, mirroring how `enterprise/` is already wired in
`config/application.rb`); and any hook into an existing model/controller/service uses
`prepend_mod_with`/`include_mod_with` or another already-unwired extension point (e.g.
`ChatwootApp.custom?`/`ChatwootApp.extensions`) rather than editing the upstream file's body. The
only allowed exception is infrastructure Rails/Chatwoot hard-requires to live in a fixed shared
location (e.g. migrations under `db/migrate/`) — even there, such changes MUST be additive,
reversible, and MUST NOT alter existing core tables.
**Rationale**: The value of tracking Chatwoot long-term comes from staying mergeable. A
customization that cannot survive a `git merge upstream/develop` is a liability, not a feature.
A coupled-but-simple edit saves engineering time once but re-pays that debt as a merge conflict
on every future upstream sync; a decoupled module, once built, keeps merging for free. The fork
should prefer paying the one-time engineering cost of isolation over the recurring cost of
conflict resolution.

### II. Smallest Production-Ready Change
Implement the smallest change that satisfies the actual, current requirement. Do not add
speculative guards, fallbacks, retries, feature flags, or edge-case handling for scenarios the
caller cannot hit today. Do not refactor, rename, or "clean up" surrounding code as a side effect
of an unrelated change. Three similar lines beat a premature abstraction; a one-use helper is only
justified when it hides real complexity.
**Rationale**: Small diffs are easy to review, easy to revert, and easy to reconcile with
upstream changes to the same files. Speculative code is exactly what tends to conflict with
upstream's own evolution of that area.

### III. Adhere to Established Conventions
All code MUST follow the conventions already documented and enforced in this repository:
RuboCop for Ruby (150-char lines), ESLint (Airbnb base + Vue 3 recommended) for JS/Vue, Tailwind
utility classes only (no custom/scoped/inline CSS), Composition API with `<script setup>` for Vue
components, PascalCase component names, camelCase events, i18n for all user-facing strings (no
bare template strings), and strong params / PropTypes at data boundaries. Personal preferences
that conflict with these house conventions MUST NOT be introduced project-wide; if a genuinely
better convention is desired, it is proposed as an amendment to this constitution and the
project's lint configuration, not applied ad hoc.
**Rationale**: Consistency lets upstream diffs apply cleanly and keeps the codebase legible to
anyone (including future-you) who has only read the standard Chatwoot docs.

### IV. Safe, Reversible Change Management
Prefer local, reversible actions (editing files, running tests) freely. Treat destructive or
hard-to-reverse operations — force-push, `git reset --hard`, deleting branches/volumes, dropping
databases, amending published commits, disabling CI/lint checks — as requiring explicit
confirmation and a clear reason, never as a shortcut around a failing check. Investigate root
causes of obstacles (build failures, permission errors, environment issues) rather than bypassing
them with `--no-verify`, disabled checks, or deleted state. Only take a destructive action when it
is the best available option and the blast radius is understood.
**Rationale**: A personal fork is still a long-lived project; recoverability matters more than
speed when the two are in tension.

### V. Dual-Tree Awareness (OSS + Enterprise)
Any change to core logic or public API surface MUST be checked against both `app/` and
`enterprise/` before it is considered complete. New endpoints, services, or models MUST decide
explicitly whether Enterprise needs an override or an extension point, and that decision MUST be
recorded (in the PR description or an inline comment) rather than left implicit. Request/response
contracts stay stable across OSS and Enterprise editions. Enterprise-only behavior added to
existing OSS features MUST use `prepend_mod_with`/`include_mod_with` rather than editing OSS
files directly.
**Rationale**: Chatwoot's enterprise overlay is a first-class part of the architecture; ignoring
it silently breaks the enterprise build even when the OSS build looks fine.

### VI. Test-Driven Development (NON-NEGOTIABLE)
Every behavior change — new feature, bugfix, or behavioral refactor — is driven by a test that
failed first, for the right reason, before the code that makes it pass exists. This applies to
both of this fork's stacks: RSpec under `spec/` and `custom/spec/`, and Vitest under
`app/javascript/`, following the container-based commands and conventions documented in `AGENTS.md`.
- A test exists and has been observed failing before its implementation lands. The red-then-green
  sequence is verified directly through targeted test execution in the active session or clean commit
  history, without creating or maintaining intermediate step-tracking files or bookkeeping journals
  (see Principle VIII).
- Tests are never weakened, skipped, deleted, or filtered out to reach green. When a test and the
  code disagree, the feature's `spec.md` — or, absent one, the stated requirement — decides which
  is wrong.
- Every acceptance criterion in a feature's `spec.md` has at least one test exercising the real
  entry point (an RSpec `type: :request` spec, or a Vitest component/store test), not only a test
  of an internal implementation detail.
- Refactoring happens only on a green suite and never changes a test in the same commit as a
  behavior change.
- Test strength is verified, not assumed. Tests MUST be resistant to mutation (see Principle VII);
  where automated mutation tooling is absent, high-risk logic is verified by deliberate-mutant checks
  against production invariants.
- This supersedes the former blanket "avoid writing specs unless explicitly asked" guidance: a
  test accompanying a genuine behavior change is expected, not optional. Restraint still applies
  to code the change does not touch — do not add specs for untouched behavior as a drive-by.
**Rationale**: This fork has no host-level toolchain and no CI safety net beyond the suites
themselves (rootless Podman, container-only dev). A behavior change exercised once by hand in dev
is a regression waiting for the next upstream sync; a test that failed first and now passes is
the only durable evidence the behavior was ever built correctly, and the only thing that catches
it breaking again when `develop` is merged in.

### VII. Observable Behavior and Mutation Resistance (NON-NEGOTIABLE)
Tests exist solely to guarantee observable behavior and detect real business regressions, never
to fulfill vanity coverage metrics or validate synthetic mock contracts.
- Rigid Boundary for Test Doubles: Test doubles (`mocks`, `stubs`, `spies`, `doubles`) are
  strictly restricted to uncontrollable external boundaries of the system: external third-party
  APIs/HTTP endpoints, external payment/SMS gateways, operating system time/clock helpers
  (`travel_to`), and hardware/filesystem drivers. Mocking database models, Active Record
  persistence layers, internal domain services, business logic, or the component under test itself
  is STRICTLY FORBIDDEN. Internal classes and collaborator services MUST interact using their real
  implementations and standard test database fixtures/factories.
- Validation by Observable State: Every assertion MUST validate a result observable by the client
  of the component — return values, actual changes in persisted database state, emitted events or
  enqueued jobs, or typed contract errors. Cosmetic assertions (e.g. asserting only `be_present`/
  non-nil, asserting a method was called with parameters without verifying its concrete effect, or
  tautological assertions testing only what a mock was programmed to return) are strictly prohibited
  as quality violations.
- Resistance to Mutation: A test is valid only if a deliberate mutation of the underlying business
  rule, condition, or edge case in production code causes the test to fail unequivocally.
**Rationale**: Tests coupled to internal mocks or method-call sequences break during valid
refactorings and continue passing when real business rules fail. Testing real behavior through
observable inputs and state changes makes the test suite durable, refactor-proof, and capable of
catching genuine regressions.

### VIII. Pragmatic Test-First by Functional Slice
Every new behavior, feature, or bugfix MUST be planned from a test-first perspective before
implementation, but executed in atomic, cohesive functional slices rather than mechanical
micro-steps.
- Delivery in Cohesive Functional Units: Development MUST NOT be fragmented into robotic
  micro-cycles (e.g. writing one line of code or one assertion at a time). A complete functional unit
  (such as a domain module, service, endpoint, or UI component with its complete matrix of happy-path,
  boundary, and error scenarios) MUST be designed, specified, and constructed together in a single
  logical work cycle.
- Prohibition of Intermediate Accounting and Step Journals: Creating or maintaining intermediate
  accounting files, step-by-step progress journals, execution logs (`cycle-log.md`), or audit
  artifacts whose sole purpose is tracking the AI/developer's own workflow steps is STRICTLY
  FORBIDDEN. The only accepted proof of quality and completion is clean, expressive test code passing
  in the repository.
- Failing for the Correct Reason: Every new test scenario MUST demonstrate that it fails due to
  the absence of the intended functionality before implementation begins, guaranteeing that the
  test is not a passive false positive.
**Rationale**: The discipline of TDD lies in contract-driven design and specification rigor, not in
rigid micro-steps that create artificial friction, consume unnecessary tokens and time, and inflate
process complexity without improving software quality. Delivering complete, cohesive functional
slices maximizes architectural clarity, maintainability, and delivery velocity.

### IX. Surgical Execution Scope and Decoupled Global Gates
Test execution during iterative development MUST be strictly scoped to the immediate context of
the component being modified.
- Prohibition of Global Suite Runs During Iteration: Running the complete repository test suite
  during preflight checks, on every minor change, or after every subtask is STRICTLY FORBIDDEN.
  Full suite validation MUST be decoupled from iterative development and reserved exclusively for
  pre-integration, pre-release verification, or CI pipelines.
- Targeted File or Module Execution: During the implementation of a behavior, automated test
  execution MUST run exclusively the specific test file corresponding to the modified component or
  the immediate functional subset (e.g. `bundle exec rspec spec/path/to/file_spec.rb` or `pnpm vitest
  run path/to/file.spec.js`).
- Zero Tolerance for Log Pollution: Test runners and automated tools MUST use concise output flags
  (`--quiet`, targeted filters by test/example name, suppression of massive stack traces or
  redundant database SQL logs) to prevent performance degradation and working context pollution.
**Rationale**: In large-scale applications like Chatwoot, complete test suites require 16+ minutes to
run and often contain order-dependent pollution or pre-existing flaky tests. Mandating global runs
during iteration destroys the rapid feedback loop, overburdens container resources, and distracts
from the task at hand.

## Personalization Boundaries

Personal customizations (branding, workflow tweaks, integrations, UI adjustments) are welcome,
but MUST be built so they can be toggled or lifted out without surgery on core files:

- Prefer configuration, environment variables, feature flags, or the existing
  `useBranding`/`replaceInstallationName` pattern over hardcoding personal/brand-specific values
  into shared components.
- New, fork-specific features MUST live in an isolated, clearly delimited location (a dedicated
  top-level tree such as `custom/`, a new namespaced module, or the `enterprise/` overlay when
  extending enterprise concepts) rather than being interleaved into unrelated upstream files —
  even when the isolated approach takes more engineering effort than a direct edit would.
- Do not remove or weaken upstream tests, lint rules, or CI gates to make a personal feature fit.
  If a personal feature is fundamentally incompatible with an upstream constraint, that tension
  MUST be resolved by redesigning the feature, not by loosening the constraint.
- Translation changes: This fork does not use Crowdin. The Kanban module and fork-specific additions are delivered with `pt-BR` translations included. For product and source-string changes in fork-owned features and modules, update both English (`en.yml`, `en.json`) and Portuguese (`pt_BR.yml`, `pt_BR.json`) files synchronously. Core upstream strings outside fork features remain English-first.

## Development Workflow & Quality Gates

- Use the build/test/lint commands already defined for this repo (`bundle exec rspec`,
  `pnpm test`, `pnpm eslint`, `bundle exec rubocop -a`) before considering work done; do not
  invent parallel tooling. In the inner development loop, always scope test runs surgically to the
  affected file or example (Principle IX); run full suites only as pre-release or pre-integration gates.
- Follow the repo's commit message convention (Conventional Commits: `type(scope): subject`) and
  PR description format (user-facing summary, `Closes`, `How to test`/`How to reproduce`, optional
  `What changed`) as already documented for this project.
- Every genuine behavior change ships with a test that failed first (Principles VI, VII, VIII); when
  specs are written, follow the existing repo conventions (favor `let` and per-example setup over bespoke
  helpers) documented in `AGENTS.md`. Intermediate step-log files or audit diaries are forbidden
  (Principle VIII); executable tests are the sole proof of delivery.
- Any exploratory or experimental environment setup (e.g., local Docker/Podman overrides,
  `.env` values, SELinux relabeling) that diverges from the documented dev workflow stays local
  and untracked (e.g., `docker-compose.override.yaml`) — it is not committed as if it were the
  project's standard setup unless it is proposed and adopted as such.

## Governance

This constitution governs how personal customizations are made to this Chatwoot fork; it
supplements, and does not replace, the tactical guidance already recorded in `CLAUDE.md`. Where
the two conflict, this constitution's principles take precedence for architectural/governance
questions, and `CLAUDE.md` takes precedence for day-to-day tactical detail (exact commands, file
locations). Both should be kept mutually consistent.

Amendments to this constitution require: (1) a stated reason the current principle is
insufficient or wrong, (2) an explicit version bump following semantic versioning — MAJOR for
backward-incompatible governance changes or principle removals, MINOR for new principles or
materially expanded guidance, PATCH for clarifications and wording fixes — and (3) propagation of
any resulting changes to dependent templates (`plan`, `spec`, `tasks`, `checklist`) in the same
change.

Every plan or feature produced under Spec Kit MUST pass a Constitution Check against the
principles above before implementation begins; violations must be justified explicitly (see the
Complexity Tracking section of the plan template) or the approach must be revised.

**Version**: 1.4.0 | **Ratified**: 2026-07-29 | **Last Amended**: 2026-09-18
