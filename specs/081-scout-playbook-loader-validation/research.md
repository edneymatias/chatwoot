# Phase 0 Research: Scout Playbook Loader and Boot Validation

Technical Context in plan.md left no `NEEDS CLARIFICATION` markers — the three spec
clarifications (2026-09-24 session) already resolved the only genuinely ambiguous product
questions (`priority` required/unique, `exits` optional, `name` uniqueness). The remaining
unknowns are implementation-mechanism decisions, resolved below against `design.md` §4.3/§4.4 and
existing repo conventions.

## D1 — Frontmatter parsing: manual split + `Psych.safe_load`, no new gem

**Decision**: Split the file on the first two `---` delimiter lines with a single anchored regex
(`/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m`), `YAML.safe_load` the header, keep the remainder as the
raw body string.

**Rationale**: `YAML.safe_load`'s default permitted classes (`String`, `Integer`, `Float`,
`Array`, `Hash`, `TrueClass`/`FalseClass`, `NilClass`) already cover every value shape in the
format (design.md §4.3 example: strings, one integer `priority`, arrays, and nested string→string
hashes like `exits: { agendado: { opportunity_id: integer, starts_at: datetime } }` — `integer`/
`datetime` there are literal *type-name strings* for later payload validation, not YAML type
tags). No `permitted_classes:` override needed.

**Alternatives considered**: A `front_matter_parser`-style gem — rejected, not in `Gemfile.lock`
and the split is a single regex; adding a gem for one regex violates Constitution II.
`commonmarker` (already a dependency) — rejected, it renders Markdown → HTML, which would violate
FR-002 (body preserved exactly, no reformatting); it parses none of the YAML header either.

## D2 — Loader is permissive; Validator alone raises, once, with every violation

**Decision**: `Loader.load_all` never raises for anything inside a playbook file — it still builds a
`Playbook` object per file (nil `name`, nil `priority`, etc. flow through) so the full catalog
exists before any check runs. Frontmatter it cannot use (unparseable YAML, a non-list `when_state`,
a `when_state` entry that is neither a String nor a single-key mapping, a non-mapping `exits`) is
recorded on `Playbook#load_errors`, never normalized away: dropping it would silently turn a typo
into a broader or trigger-only playbook. `Validator.call!(catalog)` is the only thing that raises
for file content (it reports `load_errors` alongside its own rules), and it collects every violation
across every file before raising once. The one exception is a missing playbooks directory:
`Loader` raises `Errno::ENOENT` from `Dir.children`, because that is a deployment bug (for example
a mistyped `SCOUT_V2_PLAYBOOKS_DIR`), not a playbook problem, and loading zero playbooks would hide it.

**Rationale**: Spec Assumptions section is explicit: *"reported as a single failure ... after
collecting every broken reference found in that pass, so a developer sees the full list of
problems at once."* Edge case: *"A duplicate-priority error and a broken-reference error both
exist in the same startup attempt — every failure that can be identified in one pass is
surfaced."* Neither is satisfiable if the loader bails out on the first structurally-invalid file.

**Alternatives considered**: Loader raises immediately per file (fail-fast) — rejected, contradicts
the one-pass aggregate-reporting requirement above.

## D3 — Ending-reference scanning convention: `exit_<name>` tokens in body text

**Decision**: FR-009 validation scans the raw body string for `/\bexit_([[:word:]-]+)/` and requires
every captured `<name>` to be a key in that playbook's own `exits`. `exits` keys, like playbook
`name`s, must match `\A[a-z][a-z0-9_]*\z`. The scan deliberately captures more than that format so
a token like `exit_Agendado` or `exit_sem-horario` is reported instead of passing unseen.

**Rationale**: This is not invented — it is the exact literal token already used in design.md's
own worked example body (`custom/playbooks/agendamento.md`, design.md:329,331,333: *"encerre com
`exit_agendado`"*, *"`exit_sem_horario`"*, *"`exit_handoff`"*), matching the `exits:` keys
declared in the same file's frontmatter (`agendado`, `sem_horario`, `handoff`). The edge case
*"mentions an ending in prose but the same ending is also properly declared"* is exactly this
mechanism: the token must exist in `exits`, regardless of how many times or where in the prose it
appears.

## D4 — Playbook-handoff-reference scanning convention: `open_playbook(<name>)` tokens

**Decision**: FR-010 validation scans body text for `/open_playbook\(\s*['"]?([^'")\s]+)['"]?\s*\)/`
and requires every captured `<name>` to be a `name` present in the loaded catalog. Playbook `name`s
must match `\A[a-z][a-z0-9_]*\z`; the scan captures anything inside the parentheses so a target
spelled outside that format (e.g. `Agendamento`, `no-such`) is reported as unresolved.

**Rationale**: `open_playbook(nome)` is design.md's own name for the exact mechanism FR-010
describes — "a playbook's procedure hands off to another playbook by name"
(design.md:260,284,413: *"`open_playbook(nome)` → corpo como tool result"*; *"É esse o mecanismo de
`open_playbook`"*; *"`open_playbook` só quando não há playbook forçada por estado"*). Reusing the
same token the design already commits to (rather than inventing a new one) keeps this phase's
static check meaningful once brief 02/05 wire the runtime tool of the same name.

**Alternatives considered**: A separate `transitions:` frontmatter field — rejected; design.md's
own worked example and roadmap table (§6) show transitions expressed as prose ("→ qualificacao")
inside the procedure, not as structured frontmatter, and brief §5 does not scope a new frontmatter
field for this.

## D5 — Declared Capability Catalog: static name list, seeded from design.md's own roadmap

**Decision**: `Custom::ScoutV2::Capabilities::Catalog::KNOWN_NAMES = %w[scheduling
customer_registry].freeze`, checked via `Catalog.known?(name)` (exact-string, case-sensitive —
matches the spec's Edge Cases: no fuzzy/normalized comparison).

**Rationale**: Spec's Key Entities section separates the *declared catalog of names* (this
phase, FR-008) from *resolving/exercising* the capability (`CapabilityRegistry`, brief 07,
explicitly out of scope here). `scheduling` and `customer_registry` are not invented — they are
the only two capability names design.md's own first-cut roadmap table (§6) commits to
(`agendamento` row: `requires: scheduling, customer_registry`). Seeding the catalog with exactly
those two, and no more, keeps the change to what's already decided rather than guessing at names
brief 07 hasn't specified yet.

**Alternatives considered**: Empty catalog (`[]`) — rejected, would make `agendamento` (the
brief's own worked example) fail validation the moment it's authored in brief 06, for a name the
design has already fixed. Dependency-injected list passed into `Validator.call!` — rejected as
unnecessary indirection; `Capabilities::Catalog` is a real, small, static collaborator (like
`Predicates::Registry`), not a boundary that needs mocking per Constitution VII, so tests exercise
it directly with its real names.

## D6 — Predicates: static name→class map, instance `#call(ctx, arg = nil)`

**Decision**: `Predicates::Registry::REGISTRY = { 'opportunity_open' =>
Predicates::OpportunityOpen, 'pending_required_fields' => Predicates::PendingRequiredFields
}.freeze`, with `Registry.registered?(name)` / `Registry.resolve(name)`. `Predicates::Base`
defines `#call(ctx, arg = nil)` raising `NotImplementedError` by default (mirrors
`Erp::BaseAdapter`'s existing `self.erp_name` raise-by-default convention).

**Rationale**: Brief §5 explicitly scopes exactly `predicates/base.rb + registro por nome + os
predicados exigidos pela playbook do brief 03 (opportunity_open, pending_required_fields)` — a
static two-entry map is the smallest structure satisfying that. `#call` as an *instance* method
(not `self.call`) matches design.md's own worked predicate example verbatim
(design.md:359-362: `class ... < Base; def call(ctx, stage_role) = ...; end; end`).

**Alternatives considered**: Dynamic registration DSL (`register :name, klass`) — rejected,
unnecessary for a closed, two-entry list; a `.freeze`d Hash literal is simpler and just as
testable (Constitution II).

## D7 — `opportunity_open` / `pending_required_fields` semantics

**Decision**: `OpportunityOpen#call(ctx, _arg = nil) = ctx.opportunity&.status.to_s == 'open'`
(the `Opportunity` model's own `status` enum is `{ open: 0, won: 1, lost: 2 }`,
`custom/app/models/opportunity.rb:21`). `PendingRequiredFields#call(ctx, _arg = nil) =
ctx.pending_fields.present?`.

**Rationale**: Reuses the real `Opportunity#status` enum already in the codebase rather than
inventing new state; `nil` opportunity is "not open" (`&.` short-circuits to `nil`, `.to_s` makes
it `''`, `!= 'open'`), matching the routing context where a contact may have no opportunity yet.

## D8 — Minimal `RoutingContext`: seed only the two fields the in-scope predicates need

**Decision**: `Custom::ScoutV2::RoutingContext = Struct.new(:opportunity, :pending_fields,
keyword_init: true)`.

**Rationale**: design.md §4.4 names the *eventual* full routing context (`conversation, contact,
inbox, scout, opportunity, pending_fields, active_playbook, transitions,
satisfied_capabilities`) — but building/populating all of that is the router's job (brief 02,
explicitly out of scope here per brief §6). This phase only needs a concrete `ctx` shape for the
two predicates it is scoped to pre-build; a two-field `Struct` is the minimum needed today. Brief
02 is expected to *extend* this struct's fields (additive), not replace it — no forward-compat
risk from starting minimal.

**Alternatives considered**: No formal `RoutingContext` class, duck-typed context objects built
ad hoc in specs — rejected; `Predicates::Base#call(ctx, arg)`'s contract needs *something* concrete
to type against for US3's own acceptance criteria to be checkable, and an un-named ad hoc shape
would be invisible to brief 02 as the seed it's meant to extend.

## D9 — Boot wiring: dedicated `Rails.application.config.after_initialize` initializer

**Decision**: New file `config/initializers/scout_v2_playbooks.rb`:
`Custom::ScoutV2::Playbook::Validator.call!(Custom::ScoutV2::Playbook::Loader.load_all)` inside
`Rails.application.config.after_initialize do ... end`.

**Rationale**: Matches three existing precedents in the same directory doing exactly this shape of
boot-time setup/validation (`ai_agents.rb`, `geocoder.rb`, `rack_timeout.rb`). `after_initialize`
runs on every process boot regardless of environment or `config.eager_load` setting, so it fires
for `rails server`, Sidekiq workers, `rails console`, `rails runner`, and — critically — every
RSpec run (Rails boots once per suite), which is exactly how FR-012's "the same failure MUST also
cause an automated build/CI run to fail" is satisfied without a separate Rake/CI task: a broken
playbook fails the *first* spec that boots Rails.

**Alternatives considered**: A dedicated Rake task run explicitly in CI — rejected, adds a second
place a developer must remember to run locally; the initializer gets it for free on every `rspec`
invocation, matching how this repo already treats `spec/config/schema_spec.rb`-style "boot/tree
health" checks (`AGENTS.md`, n8n schema contamination note) as regular spec-suite citizens.

## D10 — `Catalog#ordered_by_priority`: descending (highest first)

**Decision**: `Catalog#ordered_by_priority` sorts by `priority` descending.

**Rationale**: design.md §4.4's router decision rule picks "a de maior priority" among matching
playbooks (*"entre as que casam, vence a de maior priority"*) and compares with strict `>`.
Exposing the catalog pre-sorted highest-first is the natural consumption order for that brief-02
"first match wins" iteration; FR-005 only requires "orderable by priority," not a specific
direction, so this is a documented implementation choice, not a spec requirement.
