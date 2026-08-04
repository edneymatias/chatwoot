<!--
Sync Impact Report
Version change: 1.1.0 → 1.1.1
Modified principles: none
Added sections: none (scoped clarification appended to the existing Personalization
  Boundaries translation bullet)
Removed sections: none
Rationale: The project owner explicitly required pt-BR translations for the
  015-opportunity-funnel-report feature's OPPORTUNITY_FUNNEL_REPORTS strings because the
  feature is used in practice in that locale today, ahead of the normal Crowdin sync cycle.
  This is a narrow, named exception, not a change to the general rule.
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ no edit needed
  - .specify/templates/spec-template.md ✅ no edit needed
  - .specify/templates/tasks-template.md ✅ no edit needed
  - .specify/templates/checklist-template.md ✅ no edit needed
Follow-up TODOs: none
-->

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
- Translation changes for product/source strings touch only `en.yml` / `en.json`; other locales
  remain Crowdin-owned and are not hand-edited. **Named exception**: the
  `OPPORTUNITY_FUNNEL_REPORTS` keys in `app/javascript/dashboard/i18n/locale/pt_BR/report.json`
  (feature `015-opportunity-funnel-report`) were hand-edited by explicit project-owner request,
  since that locale is used in practice ahead of the normal Crowdin cycle. This exception is
  scoped to those keys only and does not extend to other features or locales.

## Development Workflow & Quality Gates

- Use the build/test/lint commands already defined for this repo (`bundle exec rspec`,
  `pnpm test`, `pnpm eslint`, `bundle exec rubocop -a`) before considering work done; do not
  invent parallel tooling.
- Follow the repo's commit message convention (Conventional Commits: `type(scope): subject`) and
  PR description format (user-facing summary, `Closes`, `How to test`/`How to reproduce`, optional
  `What changed`) as already documented for this project.
- Avoid writing specs unless explicitly asked; when specs are written, follow the existing spec
  conventions (favor `let` and per-example setup over bespoke helpers).
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

**Version**: 1.1.1 | **Ratified**: 2026-07-29 | **Last Amended**: 2026-08-04
