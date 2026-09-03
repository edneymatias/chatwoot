# Chatwoot Development Guidelines

## Container-Based Development (Preferred Mode for This Fork)

This fork has no host-level Ruby/Node toolchain. All development happens inside containers
managed by Docker Compose, running on rootless Podman with SELinux enforcing (the `docker` CLI
on this host is the `podman-docker` shim, transparently execing `podman`/`podman-compose`).

- **This is the preferred and default dev mode for this fork.** Do not install a host-level
  `rbenv`/Ruby/Node toolchain to work around it; fix container issues instead of bypassing the
  container environment.
- **Start the stack**: `docker compose up -d` (services: `rails` on :3000, `vite` on :3036,
  `sidekiq`, `postgres` on :5432, `redis` on :6379, `mailhog` on :1025/:8025)
- **Stop the stack**: `docker compose down` (add `-v` only if you explicitly intend to wipe
  volumes/data — confirm with the user first)
- **Run a one-off command**: `docker compose exec <service> <command>` (e.g.
  `docker compose exec rails bundle exec rspec spec/path/to/file_spec.rb`)
- **Tail logs**: `docker compose logs -f <service>` or `docker logs -f chatwoot_<service>_1`
- **Local-only overrides**: rootless Podman + SELinux tweaks (e.g. `:z` volume relabeling) live in
  the untracked `docker-compose.override.yaml`, merged automatically by `docker compose`. Never
  commit environment-specific overrides into the tracked `docker-compose.yaml`.
- **Secrets**: `.env` (gitignored) holds real generated secrets (`SECRET_KEY_BASE`,
  `POSTGRES_PASSWORD`, `REDIS_PASSWORD`); create it from `.env.example` if missing.
- **Committing**: the pre-commit hook (husky + `lint-staged`) shells out to `npx`, which needs a
  Node toolchain this host doesn't have. Run `git commit` inside the `vite` container instead of
  on the host: `docker compose exec vite git commit -m "..."`. The container also has no git
  identity configured (no host `~/.gitconfig` mount), so pass it inline the first time or whenever
  it's missing: `docker compose exec vite git -c user.name="Your Name" -c user.email="you@example.com" commit -m "..."`.

## Build / Test / Lint

All commands below assume the stack is already up (`docker compose up -d`); prefix ad hoc Ruby/JS
commands with `docker compose exec <service>`.

- **Setup**: `docker compose build && docker compose up -d` (dependencies install automatically
  via the container entrypoints on boot)
- **Run Dev**: `docker compose up -d`
- **Seed Local Test Data**: `docker compose exec rails bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `docker compose exec rails bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `docker compose exec rails bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `docker compose exec vite pnpm eslint` / `docker compose exec vite pnpm eslint:fix`
- **Lint Ruby (Full Global Check)**: `docker compose exec rails bundle exec rubocop` (must pass 100% clean across all 2,800+ files to match CI)
- **Lint Ruby (Auto-fix)**: `docker compose exec rails bundle exec rubocop -a`
- **Test JS (Full Suite)**: `docker compose exec vite pnpm test` or `docker compose exec vite pnpm test:watch`
- **Test Ruby (Full Suite)**: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec`
- **Test Ruby (Targeted Custom/Kanban & Modified Modules)**: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/ spec/models/opportunity_spec.rb spec/services/automation_rules/conditions_filter_service_spec.rb spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb`
- **Single Test**: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Test env caveat**: the compose services inject `.env` plus `RAILS_ENV=development` into every
  `docker compose exec` process. Running rspec without the `env -u FRONTEND_URL RAILS_ENV=test`
  prefix runs the suite against the development environment/database and breaks host-sensitive
  specs (redirect safety, SAML entity ids). Always use the prefixed form above for rspec.
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.), run inside the `rails` container.

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length). Complexity offenses (e.g. `AbcSize`, `CyclomaticComplexity`, `MethodLength`) MUST be resolved by refactoring (extracting private helpers). Do NOT add new `Exclude` entries or `Max` overrides to `.rubocop_todo.yml` or `.rubocop.yml`.
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- Prefer the smallest production-ready change that solves the current problem.
- Build for the expected production path first. Do not add speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit that case or production has proven it necessary.
- Enforce eligibility and exclusivity rules at the earliest shared entry point. Do not repeat backup guards across downstream jobs, callbacks, services, or writes unless a proven independent path bypasses that point.
- When an impossible or misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently skipping behavior.
- For locked/internal configs that must exist in production, prefer direct reads (`find`, `find_by!`, required hash keys) over silent fallbacks.
- Do not add validation or response checks unless the code uses the result or the check changes behavior meaningfully.
- Prefer existing repo dependencies/client libraries over hand-rolled protocol code for auth, signing, parsing, or API plumbing.
- Avoid one-use private helpers unless they hide real complexity or make the main flow meaningfully easier to read.
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- In specs, avoid custom helper methods for setup/data. Prefer `let` values and direct per-example setup; only add a helper when it removes meaningful repeated complexity.
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Branch Model

- **`ichatr-main`** is the fork's single permanent branch (renamed from `matias-kanban`). All
  feature branches, hotfixes, and upstream syncs branch off it and merge back into it via PR.
- **`develop`** is a fast-forward-only mirror of `upstream/develop` (`chatwoot/chatwoot`). It
  never receives local commits and is kept only as a reference for inspecting in-progress
  upstream work; update it with `git fetch upstream && git merge --ff-only upstream/develop`. It
  is **never** merged into `ichatr-main`.
- There is **no `release/*` branch scheme** — releases are tagged directly off `ichatr-main`.
- **Upstream sync target is always the latest tagged upstream release, never `upstream/develop`
  HEAD.** `develop` HEAD can carry upstream features that are incomplete, mid-rollout across
  multiple PRs, or not yet part of any release — merging it directly risks shipping unfinished
  upstream behavior and unstabilized build/toolchain changes.
- Upstream sync flow:
  1. Fast-forward `develop` first: `git fetch upstream develop --tags && git merge --ff-only
     upstream/develop && git push origin develop`. Do this *before* running `--audit` (see below)
     — `--audit`'s default base is `merge-base(ichatr-main, develop)`, and a stale `develop` (one
     that predates the last upstream merge into `ichatr-main`) makes that base land *before* the
     last sync, so the audit misreports upstream's own changes since then as fork gaps. This
     already happened once (452 false-positive gaps from a `develop` stale since 2026-07-29) —
     always fast-forward `develop` before trusting `--audit`'s output.
  2. Identify the latest tag on `chatwoot/chatwoot` (`git tag --sort=-creatordate --list 'v*' |
     head -1`) and merge it into `ichatr-main` with `git merge --no-ff <tag>` (skip if the branch
     is already at parity with it). A `pnpm-lock.yaml` conflict is expected and normal — resolve
     it by taking either side and regenerating with `pnpm install --no-frozen-lockfile`, not by
     hand-editing the lockfile.
  3. Validate with `bin/sync-custom-module-hooks --check` and `--audit` (now accurate, since
     `develop` is fresh) and the full test suites (`bundle exec rspec`, `pnpm test`,
     `pnpm eslint`, `bundle exec rubocop`) before considering the sync done.
  4. **Any genuine `--audit` gap the sync (or any fork commit) surfaces gets fixed in the same
     pass** — add a MANIFEST entry (`bin/sync-custom-module-hooks`) for a real upstream/enterprise
     file the fork patches, or extend the script's exclusion list if the flagged path is a
     wholesale fork-original file (no upstream equivalent to protect). Never defer this to "a
     future cleanup" — the commits that create a gap are also the ones responsible for closing it.

## Fork Versioning Scheme

- Release tags follow **`<upstream-base-version>-ichatr.<N>`** (hyphen-delimited, valid as a git
  tag, Docker tag, and `package.json` `version` value without translation).
- The upstream base version is the value of the `version` field in `package.json` at release-cut
  time (it mirrors the upstream Chatwoot version this fork is built on, e.g. `4.16.2`).
- `N` starts at `1` for the first release on a given upstream base, increments for every
  additional release on the same base (e.g. hotfixes), and resets to `1` when the first release
  is cut on a new upstream base — it is never carried across bases.
- Examples: base `4.16.2` first release → `4.16.2-ichatr.1`; same-base hotfix →
  `4.16.2-ichatr.2`; after syncing to base `4.17.0`, first release → `4.17.0-ichatr.1`.

## Release Process

- **Mandatory Pre-Release Verification Checklist** (must run and pass locally before cutting/tagging any release):
  1. **Working tree clean** on `ichatr-main`.
  2. **Full Frontend Lint**: `docker compose exec vite pnpm eslint` (0 errors).
  3. **Full Frontend Test Suite**: `docker compose exec vite pnpm test` (all tests passing).
  4. **Full Backend Lint (RuboCop Global)**: `docker compose exec rails bundle exec rubocop` (must pass with 0 offenses across the entire repository, exactly matching the `lint-backend` CI job).
  5. **Full / Comprehensive Backend Test Suite**: Run `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec` (or at minimum the full suite of custom and modified core models/controllers: `custom/spec/ spec/models/opportunity_spec.rb spec/services/automation_rules/conditions_filter_service_spec.rb spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb`).
  6. **Fast-forward `develop`** (`git fetch upstream develop --tags && git merge --ff-only upstream/develop && git push origin develop`) *before* the sync hooks audit below — a stale `develop` makes `--audit`'s default base land before the last upstream sync and misreports upstream's own changes as fork gaps (see Branch Model).
  7. **Sync Hooks Audit**: `docker compose exec rails ruby bin/sync-custom-module-hooks --check && docker compose exec rails ruby bin/sync-custom-module-hooks --audit` (all wiring points present, 0 gaps). Fix any genuine gap in the same pass — add a MANIFEST entry or extend the exclusion list in `bin/sync-custom-module-hooks` — rather than deferring it; do not cut a release on top of known, unfixed gaps.
  8. **Explicit User Approval**: Ask and obtain explicit user validation before executing release commands.
- Run `bin/ichatr-release`; it computes the next `<upstream-base-version>-ichatr.<N>` tag (see
  Fork Versioning Scheme above) and the changelog range for it, and asks for confirmation before
  creating and pushing the tag.
- Pushing the tag triggers CI automatically: it generates the changelog for that range, commits
  the updated `CHANGELOG.md` directly to `ichatr-main`, creates a GitHub Release for the tag, and
  publishes the Docker image.
- Artifacts land in three places: `CHANGELOG.md` in the repo, a GitHub Release entry, and
  `edneymatias/ichatr:<tag>` (plus a floating `latest`) on Docker Hub.
- The changelog only covers fork-specific commits (the range excludes everything already present
  in the upstream base tag); for upstream's own changes, consult upstream's release notes.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - This fork does not use Crowdin. The Kanban module is delivered with `pt-BR` translations included.
  - For product and source-string changes, update both English (`en.yml`, `en.json`) and Portuguese (`pt_BR.yml`, `pt_BR.json`) files synchronously.
  - Backend i18n → `en.yml` and `pt_BR.yml`, Frontend i18n → `en.json` and `pt_BR.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Frontend Conventions

- Prefer existing design-system utilities and shared composables.
- Use typography utilities instead of manually recreating font styles.
- Use logical Tailwind utilities (`ms`, `me`, `start`, `end`) for direction-aware layouts.
- Use `rem` for arbitrary CSS dimensions; preserve native numeric values required by chart/SVG APIs.
- Extract repeated or domain-specific strings, thresholds, colors, and durations into named constants.
- Use shared request-cancellation utilities instead of local `AbortController` logic.

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.
- **Workflow Constraint**: NUNCA crie commits ou envie alterações (push) para o remote antes de expressa validação/teste local pelo usuário. Aguarde sempre o 'ok' explícito antes de comitar e atualizar tags.
