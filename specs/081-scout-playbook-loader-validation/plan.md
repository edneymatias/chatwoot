# Implementation Plan: Scout Playbook Loader and Boot Validation

**Branch**: `081-scout-playbook-loader-validation` | **Date**: 2026-09-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/081-scout-playbook-loader-validation/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

Add a file-based "playbook" catalog to the ScoutV2 fork module: a loader parses versioned
`.md` files (YAML frontmatter + verbatim markdown body) under `custom/playbooks/` into typed
`Custom::ScoutV2::Playbook` objects, collected into a queryable `Playbook::Catalog`. A boot-time
validator (`Playbook::Validator`, wired via a dedicated Rails initializer) rejects the whole
process before it becomes ready to serve conversations if any reference is broken: blank
`name`/`title`/`trigger`, unregistered `when_state` predicate, unknown `requires` capability, an
`exit_<name>`/`open_playbook(<name>)` token in the body not matching a declared ending/playbook,
missing/non-integer/duplicate `priority`, or duplicate `name` — reporting every violation found
in one pass, never a silent partial start. A small `Predicates::Registry` (two concrete predicates,
`opportunity_open`/`pending_required_fields`, resolved by name) and an AND-only evaluator make
"when does this playbook apply" testable without a model, satisfying US3. No existing
`system_prompts_service.rb`/`agent_runner.rb`/`response_auditor.rb` code changes — this phase is
additive only, isolated under `custom/app/services/custom/scout_v2/`.

## Technical Context

**Language/Version**: Ruby 3.4.4 (existing Rails 7 app; no new language/runtime).

**Primary Dependencies**: None new. Frontmatter parsing uses Ruby stdlib `Psych`
(`YAML.safe_load`, already available via Rails) on a manually split `---\n...\n---\n` header —
no new frontmatter/markdown gem (`commonmarker` is already a dependency but is not used here:
FR-002 requires the body preserved verbatim, not rendered to HTML). Classes autoload via the
existing Zeitwerk `custom/app/**` eager-load path (`config/application.rb:51`); no new
autoload configuration.

**Storage**: Plain versioned files (`custom/playbooks/*.md`), not a database table. No migration
in this phase — the routing-context persistence table (`ichatr_scout_conversation_states`) belongs
to brief 02 (router), out of scope here.

**Testing**: RSpec under `custom/spec/services/custom/scout_v2/**`, run inside the `rails`
container (`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec
<path>`, per `AGENTS.md`). Fixtures are real temporary files (`Dir.mktmpdir` + `File.write`), not
mocks — Constitution Principle VII forbids mocking internal collaborators, and a loader whose job
is "read files off disk" is exactly the kind of behavior a real temp-file fixture proves and a
stub would hide.

**Target Platform**: Same Rails app server / Sidekiq / `rails console` / RSpec boot that already
exists. Boot validation runs via `Rails.application.config.after_initialize` (same idiom as
`config/initializers/ai_agents.rb`, `geocoder.rb`, `rack_timeout.rb`), so it fires in every
environment (dev, test, prod) and therefore also fails CI (FR-012) without a separate CI task.

**Performance Goals**: Boot-time cost is a handful of small file reads plus in-memory validation
— the first cut ships zero playbook files (authoring is brief 06) and the design's own roadmap
caps the near-term catalog at 6 files (design.md §6). Zero network or LLM calls during load/validate
(FR-013/SC-002).

**Constraints**: Boot validation must fail loud (raise, non-zero exit / unready process), never
degrade silently (FR-012); must report every violation found in one pass, not just the first
(Assumptions); RuboCop's 150-char line limit and complexity cops (`AbcSize`,
`CyclomaticComplexity`, `MethodLength`) are resolved by extracting private helpers, never by new
`.rubocop_todo.yml`/`Max` overrides (`AGENTS.md`).

**Scale/Scope**: First cut: loader + catalog + validator + 2 predicates + a static declared
capability name list (`scheduling`, `customer_registry`, sourced from design.md's own committed
roadmap table, §6). Ships with an empty `custom/playbooks/` directory — authoring the six
first-cut playbooks is brief 06, explicitly out of scope here.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. Every new file lives under `custom/`
  (`custom/app/services/custom/scout_v2/**`, `custom/playbooks/`, `custom/spec/...`) plus one new,
  wholly additive initializer (`config/initializers/scout_v2_playbooks.rb`) — no existing
  upstream/enterprise/`custom/` file is edited. Zero lines of diff in
  `system_prompts_service.rb`, `agent_runner.rb`, `response_auditor.rb` (brief §6, design decision
  5). No new DB table this phase, so the migration exception doesn't apply.
- **II. Smallest Production-Ready Change** — PASS. Scope is exactly the brief's §5 preliminary
  scope: loader, validator, two named predicates the brief commits to pre-building, and the boot
  wiring point. No speculative `CapabilityRegistry` adapter resolution, no router, no turn
  execution (brief's own §6 "Fora de escopo").
  Predicates::Registry's static two-entry hash matches the brief's `predicates/base.rb +
  registro por nome + os predicados exigidos pela playbook do brief 03` scope line verbatim — cited
  here because it precedes the reader who might otherwise flag it as speculative.
- **III. Adhere to Established Conventions** — PASS (design commitment, verified at implementation
  time via `rubocop`/`eslint`). Follows the existing `Custom::Scout::*` v1 file/class-naming and
  `class << self` factory-method conventions already in `custom/app/services/custom/scout/`.
- **IV. Safe, Reversible Change Management** — PASS. Additive files only; no destructive operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS, decision recorded: ScoutV2 is a
  fork-original module with no upstream or Enterprise equivalent (Chatwoot's own `Captain`
  Enterprise AI agent is a structurally different system — DB-row `Scenario`, UI-authored,
  validated on `save`, per brief §3 precedent note) and touches no shared core/Enterprise public
  API surface. No `prepend_mod_with`/`include_mod_with` extension point is needed because there is
  no OSS behavior being extended — this is wholly new, isolated behavior.
- **VI–VIII. TDD / Observable Behavior / Functional Slices** — Plan commits to spec-first delivery
  per brief §8: `loader_spec.rb` (full frontmatter, minimal frontmatter, verbatim body,
  empty-collection defaults), `validator_spec.rb` (one example per violation class in FR-004,
  FR-007–011, FR-017, plus a positive no-`exits` case), `predicates/*_spec.rb` (true/false per
  predicate, AND semantics over a multi-entry list), and `spec/config/scout_v2_playbooks_spec.rb`
  (boot initializer itself, per `spec/config/searchkick_spec.rb`'s `load initializer_path` +
  `with_modified_env` convention — the real entry point FR-012's boot-gating behavior runs
  through). All fixtures are real files/objects; no mocking of the loader, catalog, validator, or
  predicates under test.
- **IX. Surgical Execution Scope** — Plan commits to running only the targeted spec files during
  implementation (`bundle exec rspec custom/spec/services/custom/scout_v2/...`), full suite
  reserved for pre-integration/release gates.

No violations. Complexity Tracking is not needed.

**Post-Phase 1 re-check**: data-model.md/contracts/quickstart.md introduce no new files outside
`custom/` + the one additive initializer, no database migration, no mocking of internal
collaborators in the planned specs, and no new gem — all gates above still PASS unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/081-scout-playbook-loader-validation/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md         # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── playbook-file-format.md
│   └── ruby-interfaces.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

**Structure Decision**: Single Rails monolith (existing app). New feature code is isolated under
the fork's `custom/` overlay tree (mirrors the `enterprise/` overlay convention per Constitution
I), inside a new `scout_v2` namespace sitting alongside the existing `custom/app/services/custom/scout/`
(v1) tree — v1 stays untouched. One new Rails initializer wires boot validation; no other core
config changes (autoloading of `custom/app/**` is already wired).

```text
custom/
├── playbooks/                                              # NEW — versioned playbook files
│                                                            #   (empty this phase; brief 06 authors)
└── app/services/custom/scout_v2/
    ├── playbook.rb                                         # Custom::ScoutV2::Playbook (value object)
    ├── playbook/
    │   ├── catalog.rb                                      # ::Playbook::Catalog (by-name / by-priority)
    │   ├── loader.rb                                       # ::Playbook::Loader (file → Playbook)
    │   └── validator.rb                                    # ::Playbook::Validator (+ nested ValidationError)
    ├── routing_context.rb                                  # minimal RoutingContext (opportunity, pending_fields)
    ├── predicates/
    │   ├── base.rb                                         # ::Predicates::Base (#call contract)
    │   ├── registry.rb                                     # ::Predicates::Registry (name → class)
    │   ├── evaluator.rb                                    # ::Predicates::Evaluator (AND over when_state)
    │   ├── opportunity_open.rb
    │   └── pending_required_fields.rb
    └── capabilities/
        └── catalog.rb                                      # ::Capabilities::Catalog (declared known names)

config/initializers/
└── scout_v2_playbooks.rb                                   # NEW — boot: load + validate!, after_initialize

custom/spec/
├── services/custom/scout_v2/
│   ├── playbook/
│   │   ├── loader_spec.rb
│   │   ├── catalog_spec.rb
│   │   └── validator_spec.rb
│   └── predicates/
│       ├── evaluator_spec.rb
│       ├── opportunity_open_spec.rb
│       └── pending_required_fields_spec.rb
└── fixtures/scout_v2/playbooks/                            # temp-dir style fixtures generated in specs

spec/config/
└── scout_v2_playbooks_spec.rb                              # NEW — boot initializer spec (real entry point)
```
