## [4.16.2-ichatr.1] - 2026-08-07

### 🚀 Features

- Implement opportunity endpoints and policy
- *(kanban)* Implement pipeline stages and opportunities
- *(automation)* Add create_opportunity automation action
- *(kanban)* Implement Phase 3 frontend Kanban board, Vuex stores and pipeline stage settings
- *(kanban)* Wire realtime sync and main navigation
- *(opportunities)* Integrate conversation drawer into kanban board
- *(kanban)* Enrich cards with contact info and ordering
- *(kanban)* Implement stage transition rules
- *(kanban)* Implement sync script audit mode and add gap entries
- *(pipeline-stages)* Add drag-and-drop reordering
- *(opportunities)* Implement closing required fields for won/loss outcomes
- *(opportunities)* Implement drag-to-close status bar for kanban cards
- *(kanban)* Implement deal card customization and currency setting
- *(kanban)* Implement kanban lane visual improvements and totals
- *(opportunities)* Implement stage dwell-time tracking
- *(reports)* Add opportunity funnel report page
- *(reports)* Add sales forecast widget to opportunity funnel report
- *(reports)* Replace conversion funnel bar chart with SVG funnel chart
- *(reports)* Add opportunity attribute report
- *(automation)* Assign opportunity owner from automation and manual flows
- *(opportunities)* Add contact panel opportunities section
- *(release)* Automate fork tag computation and changelog generation

### 🐛 Bug Fixes

- *(kanban)* Resolve Phase 7 convergence gaps
- *(kanban)* Render OpportunityDetailView inside KanbanBoard
- *(kanban)* Fix card click event listener in KanbanColumn
- *(kanban)* Fetch pipeline stages on mount
- *(kanban)* Fix sync script shebang and ruby stdlib dependencies
- *(seed)* Restore realistic time distribution in opportunity seeding
- *(kanban)* Realign sync manifest entries with current fork wiring
- *(kanban)* Sanitize container env leakage for rspec baseline
- *(kanban)* Realign sync manifest after reverting upstream-develop merge
- *(kanban)* Correct upstream sync policy to target latest release tag, not develop HEAD
- *(ci)* Bump git-cliff-action to v4
- *(ci)* Merge rubocop excludes and mock enterprise constant in ce specs

### 💼 Other

- *(pt-BR)* Translate opportunity funnel report and menu entry
- *(pt-BR)* Translate opportunity assignment automation strings

### 📚 Documentation

- Note that commits must run inside vite container
- *(kanban)* Add design artifacts for sync script audit feature
- *(kanban)* Reorganize and update specs for cycles 3 and 4
- *(kanban)* Design Phase 14 deal card customization spec
- *(kanban)* Redesign lane total and accent color config (Phase 15)
- *(kanban)* Reorganize cycle 4-7 planning docs
- *(kanban)* Flesh out opportunity assignment rules planning doc
- *(kanban)* Add cycle 7 planning docs for deferred assignment scope
- *(kanban)* Flesh out contact panel opportunities spec and reorganize cycle docs
- *(kanban)* Scope upstream sync, branch rebranding, and versioning scheme
- *(kanban)* Scope table-prefix rename and CI/CD pipeline phases
- Document fork branch model and versioning scheme

### 🎨 Styling

- *(release)* Fix rubocop offenses in ichatr-release
- *(release)* Auto-generate .rubocop_todo.yml to fix ci
- Autocorrect rubocop offenses and remove scratch script
- Fix remaining rubocop offenses manually
- Track remaining offenses in .rubocop_todo.yml instead of inline
- Group let blocks to satisfy RSpec/ScatteredLet

### 🧪 Testing

- *(kanban)* Fix stale opportunity specs for baseline green

### ⚙️ Miscellaneous Tasks

- Bootstrap Speckit workflow and container dev setup
- *(kanban)* Update pt-BR translations and fix date localization
- *(build)* Map pt_BR locale upstream hooks to module manifest
- Upgrade spec-kit tooling to 0.16.0
- *(speckit)* Add opportunity-assignment-rules feature artifacts
- *(speckit)* Add contact-panel-opportunities feature artifacts
- *(speckit)* Add upstream-sync-versioning feature artifacts
- *(speckit)* Mark completed setup and US3 doc tasks in 021 tasks.md
- *(speckit)* Mark T005/T006 baseline test runs done in 021 tasks.md
- Verify PR flow against ichatr-main (throwaway)
- *(speckit)* Close out 021-upstream-sync-versioning tasks
- *(speckit)* Mark T029 done with PR #2 link
- Adapt CI/CD pipeline and commit pending kanban tasks
- *(release)* Update changelog for ichatr-main [skip ci]
- Add fallbacks for dockerhub secrets
- Fetch upstream tags for git-cliff to resolve base version tag
- Fix ambiguous push refspec for changelog
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Explicity specify repo for gh release create to prevent targeting upstream
## [ichatr-main] - 2026-07-29

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)

### 🐛 Bug Fixes

- *(whatsapp)* Preserve phone health when business enrichment fails (#15200)
- Default Captain overview to last 7 days (#15206)
- *(perf)* Lazy load super admin dashboard stats (#15147)
- Add if_not_exists to conversations.created_at index migration (#15214)
- *(whatsapp)* Resolve replies across scoped message ids (#15107)
- Reject cross-account author on help center articles (#15191)
- *(inboxes)* Guide users through meta api incident (#15210)
- Don't show the self-hosted upgrade banner on chatwoot cloud (#15195)
- Unread notification dot and unread preview sizing (#15216)
- Consolidate widget rack-attack throttles with per-endpoint kill switches + saner defaults (#14376)
- Stabilize conversation FAQ lock spec (#15236)
- Harden article author updates (#15229)
- *(captain)* Respect channel message limits (#14982)
- Freeze SLA misses after resolution (#15024)
- *(whatsapp)* Collect text header parameters (#15199)

### ⚙️ Miscellaneous Tasks

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)

## [4.16.2-ichatr.1] - 2026-08-07

### 🚀 Features

- Implement opportunity endpoints and policy
- *(kanban)* Implement pipeline stages and opportunities
- *(automation)* Add create_opportunity automation action
- *(kanban)* Implement Phase 3 frontend Kanban board, Vuex stores and pipeline stage settings
- *(kanban)* Wire realtime sync and main navigation
- *(opportunities)* Integrate conversation drawer into kanban board
- *(kanban)* Enrich cards with contact info and ordering
- *(kanban)* Implement stage transition rules
- *(kanban)* Implement sync script audit mode and add gap entries
- *(pipeline-stages)* Add drag-and-drop reordering
- *(opportunities)* Implement closing required fields for won/loss outcomes
- *(opportunities)* Implement drag-to-close status bar for kanban cards
- *(kanban)* Implement deal card customization and currency setting
- *(kanban)* Implement kanban lane visual improvements and totals
- *(opportunities)* Implement stage dwell-time tracking
- *(reports)* Add opportunity funnel report page
- *(reports)* Add sales forecast widget to opportunity funnel report
- *(reports)* Replace conversion funnel bar chart with SVG funnel chart
- *(reports)* Add opportunity attribute report
- *(automation)* Assign opportunity owner from automation and manual flows
- *(opportunities)* Add contact panel opportunities section
- *(release)* Automate fork tag computation and changelog generation

### 🐛 Bug Fixes

- *(kanban)* Resolve Phase 7 convergence gaps
- *(kanban)* Render OpportunityDetailView inside KanbanBoard
- *(kanban)* Fix card click event listener in KanbanColumn
- *(kanban)* Fetch pipeline stages on mount
- *(kanban)* Fix sync script shebang and ruby stdlib dependencies
- *(seed)* Restore realistic time distribution in opportunity seeding
- *(kanban)* Realign sync manifest entries with current fork wiring
- *(kanban)* Sanitize container env leakage for rspec baseline
- *(kanban)* Realign sync manifest after reverting upstream-develop merge
- *(kanban)* Correct upstream sync policy to target latest release tag, not develop HEAD
- *(ci)* Bump git-cliff-action to v4
- *(ci)* Merge rubocop excludes and mock enterprise constant in ce specs

### 💼 Other

- *(pt-BR)* Translate opportunity funnel report and menu entry
- *(pt-BR)* Translate opportunity assignment automation strings

### 📚 Documentation

- Note that commits must run inside vite container
- *(kanban)* Add design artifacts for sync script audit feature
- *(kanban)* Reorganize and update specs for cycles 3 and 4
- *(kanban)* Design Phase 14 deal card customization spec
- *(kanban)* Redesign lane total and accent color config (Phase 15)
- *(kanban)* Reorganize cycle 4-7 planning docs
- *(kanban)* Flesh out opportunity assignment rules planning doc
- *(kanban)* Add cycle 7 planning docs for deferred assignment scope
- *(kanban)* Flesh out contact panel opportunities spec and reorganize cycle docs
- *(kanban)* Scope upstream sync, branch rebranding, and versioning scheme
- *(kanban)* Scope table-prefix rename and CI/CD pipeline phases
- Document fork branch model and versioning scheme

### 🎨 Styling

- *(release)* Fix rubocop offenses in ichatr-release
- *(release)* Auto-generate .rubocop_todo.yml to fix ci
- Autocorrect rubocop offenses and remove scratch script
- Fix remaining rubocop offenses manually
- Track remaining offenses in .rubocop_todo.yml instead of inline
- Group let blocks to satisfy RSpec/ScatteredLet

### 🧪 Testing

- *(kanban)* Fix stale opportunity specs for baseline green

### ⚙️ Miscellaneous Tasks

- Bootstrap Speckit workflow and container dev setup
- *(kanban)* Update pt-BR translations and fix date localization
- *(build)* Map pt_BR locale upstream hooks to module manifest
- Upgrade spec-kit tooling to 0.16.0
- *(speckit)* Add opportunity-assignment-rules feature artifacts
- *(speckit)* Add contact-panel-opportunities feature artifacts
- *(speckit)* Add upstream-sync-versioning feature artifacts
- *(speckit)* Mark completed setup and US3 doc tasks in 021 tasks.md
- *(speckit)* Mark T005/T006 baseline test runs done in 021 tasks.md
- Verify PR flow against ichatr-main (throwaway)
- *(speckit)* Close out 021-upstream-sync-versioning tasks
- *(speckit)* Mark T029 done with PR #2 link
- Adapt CI/CD pipeline and commit pending kanban tasks
- *(release)* Update changelog for ichatr-main [skip ci]
- Add fallbacks for dockerhub secrets
- Fetch upstream tags for git-cliff to resolve base version tag
- Fix ambiguous push refspec for changelog
## [ichatr-main] - 2026-07-29

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)

### 🐛 Bug Fixes

- *(whatsapp)* Preserve phone health when business enrichment fails (#15200)
- Default Captain overview to last 7 days (#15206)
- *(perf)* Lazy load super admin dashboard stats (#15147)
- Add if_not_exists to conversations.created_at index migration (#15214)
- *(whatsapp)* Resolve replies across scoped message ids (#15107)
- Reject cross-account author on help center articles (#15191)
- *(inboxes)* Guide users through meta api incident (#15210)
- Don't show the self-hosted upgrade banner on chatwoot cloud (#15195)
- Unread notification dot and unread preview sizing (#15216)
- Consolidate widget rack-attack throttles with per-endpoint kill switches + saner defaults (#14376)
- Stabilize conversation FAQ lock spec (#15236)
- Harden article author updates (#15229)
- *(captain)* Respect channel message limits (#14982)
- Freeze SLA misses after resolution (#15024)
- *(whatsapp)* Collect text header parameters (#15199)

### ⚙️ Miscellaneous Tasks

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)

## [unreleased]

### 🐛 Bug Fixes

- *(ci)* Merge rubocop excludes and mock enterprise constant in ce specs

### 🎨 Styling

- *(release)* Fix rubocop offenses in ichatr-release
- *(release)* Auto-generate .rubocop_todo.yml to fix ci
- Autocorrect rubocop offenses and remove scratch script
- Fix remaining rubocop offenses manually
- Track remaining offenses in .rubocop_todo.yml instead of inline
- Group let blocks to satisfy RSpec/ScatteredLet

