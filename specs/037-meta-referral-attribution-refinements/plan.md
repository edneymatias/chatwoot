# Implementation Plan: Meta Referral Attribution Refinements

**Branch**: `037-meta-referral-attribution-refinements` | **Date**: 2026-08-14 | **Spec**: [`specs/037-meta-referral-attribution-refinements/spec.md`](spec.md)

**Input**: Feature specification from `specs/037-meta-referral-attribution-refinements/spec.md`

---

## Summary

Enhance Meta Campaign Attribution with:
1. Synchronous identification and capture of organic Facebook/Instagram posts (`organic_post`) with headline, body, and thumbnail storage, skipping ad marketing API queries to conserve rate limits.
2. Robust classification of Meta Graph API exceptions (`Meta::AuthenticationError` for code 190 vs `Meta::RateLimitError` for 17/32/613 vs `Meta::NodeNotFoundError` for code 100/404), eliminating false-positive account disconnections.
3. Persistent ActiveStorage thumbnail caching to prevent image expiration from Meta CDN signatures, surfaced via a rich popover on the Kanban card badge.
4. Auto-drain upon reconnection, a scheduled hourly Sidekiq sweeper, and a manual "Reprocessar Pendentes" button in Settings.

---

## Technical Context

**Language/Version**: Ruby 3.3.0 (Rails 7.0), JavaScript / TypeScript (Vue 3)  
**Primary Dependencies**: HTTParty, ActiveStorage, Sidekiq, Redis, Tailwind CSS, vue-i18n, FloatingVue / Headless UI Popover  
**Storage**: PostgreSQL (`ichatr_opportunities`), Redis (`Meta::RateLimiter`), ActiveStorage blobs  
**Testing**: RSpec (`custom/spec/`), Vitest (`app/javascript/dashboard/`)  
**Target Platform**: Web application (Chatwoot container stack on Linux)  
**Project Type**: Web service (Rails backend + Vue 3 SPA frontend)  
**Performance Goals**: Hover popover opens in <100ms; background resolution drain processes batches smoothly under Meta rate limits (200 req/min).  
**Constraints**: Keep changes strictly in `custom/` tree and existing fork components; no hard fork of core upstream models; 150-char RuboCop limit; synchronous `en` and `pt-BR` i18n.  
**Scale/Scope**: Accounts handling hundreds of daily Click-to-WhatsApp and organic referral leads.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)**: PASS. All new models, services, exceptions, and jobs reside exclusively under `custom/`. Additive migration touches only `ichatr_opportunities`.
- **II. Smallest Production-Ready Change**: PASS. Directly resolves identified production pain points (false disconnections, organic parsing, thumbnail caching, auto-recovery) without speculative abstractions.
- **III. Adhere to Established Conventions**: PASS. RuboCop rules, ESLint, Composition API `<script setup>`, Tailwind classes only, synchronous `en.yml`/`pt_BR.yml` and `en.json`/`pt_BR.json` translations.
- **IV. Safe, Reversible Change Management**: PASS. Standard additive database migration, reversible changes, no destructive database commands.
- **V. Dual-Tree Awareness**: PASS. Opportunity and Campaign Attribution modules are fork-isolated features.

---

## Project Structure

### Documentation (this feature)

```text
specs/037-meta-referral-attribution-refinements/
├── spec.md              # Feature specification
├── plan.md              # This implementation plan
├── research.md          # Phase 0 technical decisions
├── data-model.md        # Phase 1 data models and schema changes
├── quickstart.md        # Phase 1 verification and testing guide
├── contracts/           # Phase 1 interface and API contracts
│   ├── campaign-attribution-settings-api.md
│   ├── opportunity-attribution-payload.md
│   └── background-jobs-contract.md
└── checklists/
    └── requirements.md  # Specification quality checklist
```

### Source Code

```text
# Backend (custom/ and db/migrate/)
custom/
├── app/
│   ├── controllers/api/v1/accounts/
│   │   └── campaign_attribution_settings_controller.rb
│   ├── jobs/
│   │   ├── custom/
│   │   │   └── campaign_resolution_job.rb
│   │   └── meta/
│   │       ├── attach_campaign_thumbnail_job.rb
│   │       ├── drain_pending_attributions_job.rb
│   │       └── pending_attributions_sweeper_job.rb
│   ├── models/
│   │   └── opportunity.rb
│   └── services/
│       ├── custom/automation_rules/
│       │   └── action_service.rb
│       └── meta/
│           ├── exceptions.rb
│           └── graph_api_client.rb
db/migrate/
└── 20260815000000_add_attribution_refinements_to_ichatr_opportunities.rb

# Frontend
app/javascript/dashboard/
├── api/
│   └── campaignAttributionSettings.js
├── components-next/
│   └── Opportunities/
│       ├── KanbanCard.vue
│       └── OpportunityAttributionPopover.vue
├── composables/
│   └── useOpportunityCardFields.js
├── routes/dashboard/settings/pipelineStages/
│   └── CampaignAttributionSettings.vue
└── i18n/locale/
    ├── en.json
    └── pt_BR.json

# Backend Locales
config/locales/
├── en.yml
└── pt_BR.yml
```

**Structure Decision**: Decoupled architecture using `custom/` for all backend logic, additive migrations on `ichatr_opportunities`, and Vue 3 Composition API components for the Kanban board and settings.

---

## Complexity Tracking

*No constitution violations. All changes adhere strictly to project constitution principles.*
