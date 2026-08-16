## [4.16.2-ichatr.3] - 2026-08-16

### 🚀 Features

- *(opportunities)* Add rich-text stage description editor and kanban info panel
- *(kanban)* Add date filter comparisons and drag-to-pan navigation
- *(automations)* Add opportunity-triggered automation rules and actions
- *(attribution)* Add organic post attribution, robust oauth error handling, and thumbnail previews

### 🐛 Bug Fixes

- *(lint)* Resolve rubocop offenses across backend services and specs

### ⚙️ Miscellaneous Tasks

- *(release)* Update changelog for 4.16.2-ichatr.2 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.3 [skip ci]

## [4.16.2-ichatr.3] - 2026-08-16

### 🚀 Features

- *(opportunities)* Add rich-text stage description editor and kanban info panel
- *(kanban)* Add date filter comparisons and drag-to-pan navigation
- *(automations)* Add opportunity-triggered automation rules and actions
- *(attribution)* Add organic post attribution, robust oauth error handling, and thumbnail previews

### ⚙️ Miscellaneous Tasks

- *(release)* Update changelog for 4.16.2-ichatr.2 [skip ci]

## [4.16.2-ichatr.2] - 2026-08-13

### 🚀 Features

- *(opportunities)* Implement list view as kanban alternative
- *(opportunities)* Unified search, sort, and filtering for Kanban and List views
- *(opportunities)* Implement manual opportunity creation and conversation start
- *(opportunities)* Hide closed opportunities by default and fix dnd bug
- *(kanban)* Implement whatsapp referral attribution from meta ads
- *(opportunities)* Add contact panel quick create and adjust kanban action footer
- *(opportunities)* Add campaign attribution icon to opportunities list view

### 🐛 Bug Fixes

- *(opportunities)* Prevent kanban drag from committing unintended column moves
- *(db)* Remove leaked n8n listen/notify triggers from schema.rb
- Build errors and specs
- *(spec)* Resolve have_enqueued_mail argument mismatch
- Restore authenticated Meta connect request and campaign tooltip line breaks
- *(rake)* Extend statement_timeout for referral backfill task
- *(opportunities)* Resolve origin_conversation_id mismatch and stale broadcast overwrite
- *(rake)* Cast content_attributes to jsonb before referral lookup
- *(kanban)* Populate contact details and inboxes before opening start-conversation compose popover

### 💼 Other

- Integrate stray changelog commit from reverted 4.16.2-ichatr.3 tag

### 📚 Documentation

- *(kanban)* Add specs/plans for evolution-api referral patch and release CI/CD

### ⚙️ Miscellaneous Tasks

- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(lint)* Resolve rubocop complexity offenses and cleanup exclusions
- *(i18n)* Add missing pt_BR translation for reports opportunities
- *(i18n)* Add missing pt_BR translation for opportunity attribute reports
- Silence sync hook audit gaps
- *(release)* Update changelog for 4.16.2-ichatr.2 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.2 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.3 [skip ci]
- *(release)* Fold changelog for 4.16.2-ichatr.3 back into 4.16.2-ichatr.2
- *(release)* Update changelog for 4.16.2-ichatr.2 [skip ci]

### ◀️ Revert

- Remove clickable from base table

## [4.16.2-ichatr.2] - 2026-08-13

### 🚀 Features

- *(opportunities)* Implement list view as kanban alternative
- *(opportunities)* Unified search, sort, and filtering for Kanban and List views
- *(opportunities)* Implement manual opportunity creation and conversation start
- *(opportunities)* Hide closed opportunities by default and fix dnd bug
- *(kanban)* Implement whatsapp referral attribution from meta ads
- *(opportunities)* Add contact panel quick create and adjust kanban action footer
- *(opportunities)* Add campaign attribution icon to opportunities list view

### 🐛 Bug Fixes

- *(opportunities)* Prevent kanban drag from committing unintended column moves
- *(db)* Remove leaked n8n listen/notify triggers from schema.rb
- Build errors and specs
- *(spec)* Resolve have_enqueued_mail argument mismatch
- Restore authenticated Meta connect request and campaign tooltip line breaks
- *(rake)* Extend statement_timeout for referral backfill task
- *(opportunities)* Resolve origin_conversation_id mismatch and stale broadcast overwrite
- *(rake)* Cast content_attributes to jsonb before referral lookup

### 💼 Other

- Integrate stray changelog commit from reverted 4.16.2-ichatr.3 tag

### 📚 Documentation

- *(kanban)* Add specs/plans for evolution-api referral patch and release CI/CD

### ⚙️ Miscellaneous Tasks

- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(lint)* Resolve rubocop complexity offenses and cleanup exclusions
- *(i18n)* Add missing pt_BR translation for reports opportunities
- *(i18n)* Add missing pt_BR translation for opportunity attribute reports
- Silence sync hook audit gaps
- *(release)* Update changelog for 4.16.2-ichatr.2 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.2 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.3 [skip ci]
- *(release)* Fold changelog for 4.16.2-ichatr.3 back into 4.16.2-ichatr.2

### ◀️ Revert

- Remove clickable from base table

## [4.16.2-ichatr.2] - 2026-08-13

### 🚀 Features

- *(opportunities)* Implement list view as kanban alternative
- *(opportunities)* Unified search, sort, and filtering for Kanban and List views
- *(opportunities)* Implement manual opportunity creation and conversation start
- *(opportunities)* Hide closed opportunities by default and fix dnd bug
- *(kanban)* Implement whatsapp referral attribution from meta ads
- *(opportunities)* Add contact panel quick create and adjust kanban action footer
- *(opportunities)* Add campaign attribution icon to opportunities list view

### 🐛 Bug Fixes

- *(opportunities)* Prevent kanban drag from committing unintended column moves
- *(rake)* Extend statement_timeout for referral backfill task
- *(db)* Remove leaked n8n listen/notify triggers from schema.rb
- Build errors and specs
- *(spec)* Resolve have_enqueued_mail argument mismatch
- Restore authenticated Meta connect request and campaign tooltip line breaks

### 📚 Documentation

- *(kanban)* Add specs/plans for evolution-api referral patch and release CI/CD

### ⚙️ Miscellaneous Tasks

- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(lint)* Resolve rubocop complexity offenses and cleanup exclusions
- *(i18n)* Add missing pt_BR translation for reports opportunities
- *(i18n)* Add missing pt_BR translation for opportunity attribute reports
- Silence sync hook audit gaps

### ◀️ Revert

- Remove clickable from base table

## [4.16.2-ichatr.1] - 2026-08-08

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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
- *(docker)* Revert rubocop autocorrect that breaks pg_database_url.rb script
- *(automation)* Properly handle action_params as array in create_opportunity
- *(automation)* Bypass strong params array filter for create_opportunity
- *(pipeline_stages)* Allow agents to read pipeline stages
- *(kanban)* Allow agents to read pipeline configurations

### 💼 Other

- *(pt-BR)* Translate opportunity funnel report and menu entry
- *(pt-BR)* Translate opportunity assignment automation strings

### 🚜 Refactor

- *(opportunities)* Temporarily grant all agents full access to all opportunities

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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Remove dockerhub secrets fallback to prevent interpolation errors
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Replace docker login action with manual bash command to aggressively strip whitespace from tokens
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Add debug info and fix bash echo to handle empty username variables safely
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Restore docker/login-action now that secrets are corrected
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]

## [4.16.2-ichatr.1] - 2026-08-08

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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
- *(docker)* Revert rubocop autocorrect that breaks pg_database_url.rb script
- *(automation)* Properly handle action_params as array in create_opportunity
- *(automation)* Bypass strong params array filter for create_opportunity
- *(pipeline_stages)* Allow agents to read pipeline stages
- *(kanban)* Allow agents to read pipeline configurations

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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Remove dockerhub secrets fallback to prevent interpolation errors
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Replace docker login action with manual bash command to aggressively strip whitespace from tokens
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Add debug info and fix bash echo to handle empty username variables safely
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Restore docker/login-action now that secrets are corrected
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]

## [4.16.2-ichatr.1] - 2026-08-08

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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
- *(docker)* Revert rubocop autocorrect that breaks pg_database_url.rb script
- *(automation)* Properly handle action_params as array in create_opportunity
- *(automation)* Bypass strong params array filter for create_opportunity

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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Remove dockerhub secrets fallback to prevent interpolation errors
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Replace docker login action with manual bash command to aggressively strip whitespace from tokens
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Add debug info and fix bash echo to handle empty username variables safely
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Restore docker/login-action now that secrets are corrected
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]

## [4.16.2-ichatr.1] - 2026-08-07

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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
- *(docker)* Revert rubocop autocorrect that breaks pg_database_url.rb script

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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Remove dockerhub secrets fallback to prevent interpolation errors
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Replace docker login action with manual bash command to aggressively strip whitespace from tokens
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Add debug info and fix bash echo to handle empty username variables safely
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Restore docker/login-action now that secrets are corrected
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]

## [4.16.2-ichatr.1] - 2026-08-07

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Remove dockerhub secrets fallback to prevent interpolation errors
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Replace docker login action with manual bash command to aggressively strip whitespace from tokens
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Add debug info and fix bash echo to handle empty username variables safely
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Restore docker/login-action now that secrets are corrected

## [4.16.2-ichatr.1] - 2026-08-07

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Remove dockerhub secrets fallback to prevent interpolation errors
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Replace docker login action with manual bash command to aggressively strip whitespace from tokens
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Add debug info and fix bash echo to handle empty username variables safely

## [4.16.2-ichatr.1] - 2026-08-07

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Remove dockerhub secrets fallback to prevent interpolation errors
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Replace docker login action with manual bash command to aggressively strip whitespace from tokens

## [4.16.2-ichatr.1] - 2026-08-07

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Remove dockerhub secrets fallback to prevent interpolation errors

## [4.16.2-ichatr.1] - 2026-08-07

### 🚀 Features

- *(conversations)* Add opt-in merge for custom attributes (#15119)
- Register Slovenian (sl) locale in the live-chat widget (#15148)
- *(whatsapp)* Add cloud template management token (#15218)
- Add Video option to the article editor slash menu (#15164)
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

- Support opening links in the editor with Cmd/Ctrl+Click (#15130)
- Register Slovenian (sl) locale in survey (#15217)
- *(search)* Support Elastic Cloud API keys (#15231)
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
- *(release)* Update changelog for 4.16.2-ichatr.1 [skip ci]
- Drop arm64 support from docker build matrix

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

