# Implementation Plan: Scout Native Tools & Message Pipeline

**Branch**: `043-scout-native-tools-pipeline` | **Date**: 2026-08-19 | **Spec**: [spec.md](file:///home/matias/dev/chatwoot/specs/043-scout-native-tools-pipeline/spec.md)

**Input**: Feature specification from `/specs/043-scout-native-tools-pipeline/spec.md` (Phase 2 of Scout AI agent engine, master spec `docs/kanban/ciclo 9/scout/spec60.md` §2, §4, §5, §8, §10).

## Summary

Phase 2 connects incoming WhatsApp messages to the Scout AI agent via a sliding Redis debounce buffer and Sidekiq worker, executes turn orchestration with multimodal and out-of-office context, equips the Scout with 5 native Ruby tools (`manage_opportunity`, `move_opportunity_stage`, `update_contact`, `create_private_note`, `handover_to_human`), preserves Meta/CTWA ad attribution, generates contact memories at handoff via `Custom::Scout::ContactNotesService` (using `scout.llm_chat`), and enforces a Fail-Safe handoff guarantee so no lead is ever left stranded in `pending`.

## Technical Context

**Language/Version**: Ruby 3.3.x / Rails 7.0.x  
**Primary Dependencies**: `ruby_llm` (1.15.0), Sidekiq, Redis (`Redis::Alfred`), ActiveStorage  
**Storage**: PostgreSQL (`ichatr_scouts`, `ichatr_scout_inboxes`, `ichatr_opportunities`, `contacts`, `conversations`, `messages`), Redis (debounce buffer keys)  
**Testing**: RSpec (`custom/spec/`) executed via Docker container environment  
**Target Platform**: Linux container (`rails` / `sidekiq`)  
**Project Type**: Decoupled custom Rails engine/module under `custom/`  
**Performance Goals**: Debounce buffer handles incoming bursts with $< 10\text{ms}$ Redis latency; single LLM turn triggered per burst after debounce window  
**Constraints**: Zero edits to core database schema; strict isolation within `custom/`; Fail-Safe guarantee on any pre-call or runtime LLM failure; multi-provider BYOK support  
**Scale/Scope**: Multi-account WhatsApp sales qualification funnel  

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evaluation |
|-----------|--------|------------|
| **I. Upstream Compatibility First** | PASS | All new models, services, jobs, and listeners are isolated in `custom/` (e.g. `custom/app/services/custom/scout/`, `custom/app/jobs/custom/scout/`, `custom/app/listeners/custom/`). Database tables use the `ichatr_` prefix. No core tables are modified. Module extensions hook via `prepend_mod_with` / `include_mod_with`. |
| **II. Smallest Production-Ready Change** | PASS | Reuses existing `RubyLLM` gem, `Custom::ReferralAttributionService`, and `Custom::AutomationRules::ActionService`. Debounce uses a lightweight Redis timestamp pattern. |
| **III. Adhere to Established Conventions** | PASS | Follows RuboCop 150-char line limit, compact Ruby class definitions (`module Custom::Scout`), standard Rails strong params and validations. |
| **IV. Safe, Reversible Change Management** | PASS | Additive reversible migration with `2126...` timestamp (`21260819000005_add_pipeline_fields_to_ichatr_scouts.rb`). |
| **V. Dual-Tree Awareness** | PASS | Checked both `app/` and `enterprise/`. `Custom::Scout::ContactNotesService` implemented cleanly under `custom/` to avoid tight coupling with enterprise OpenAI-only classes while supporting all Scout providers. |

## Project Structure

### Documentation (this feature)

```text
specs/043-scout-native-tools-pipeline/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── native_tools.md
│   └── message_pipeline.md
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code Layout

```text
custom/
├── app/
│   ├── dispatchers/
│   │   └── custom/
│   │       └── async_dispatcher.rb                     # Prepend Custom::ScoutListener
│   ├── jobs/
│   │   └── custom/
│   │       └── scout/
│   │           └── process_message_job.rb             # Sliding debounce Sidekiq job
│   ├── listeners/
│   │   └── custom/
│   │       └── scout_listener.rb                      # message_created event listener
│   ├── models/
│   │   ├── custom/
│   │   │   └── concerns/
│   │   │       └── inbox.rb                           # has_one :scout association
│   │   └── scout.rb                                   # Extended Scout model with validations & aliases
│   └── services/
│       └── custom/
│           └── scout/
│               ├── agent_runner.rb                    # Turn orchestrator & fail-safe handler
│               ├── contact_notes_service.rb           # Multi-provider contact memory generator
│               └── tools/                             # RubyLLM native tools
│                   ├── base_tool.rb
│                   ├── manage_opportunity.rb
│                   ├── move_opportunity_stage.rb
│                   ├── update_contact.rb
│                   ├── create_private_note.rb
│                   └── handover_to_human.rb
└── spec/
    ├── jobs/
    │   └── custom/
    │       └── scout/
    │           └── process_message_job_spec.rb
    ├── listeners/
    │   └── custom/
    │       └── scout_listener_spec.rb
    └── services/
        └── custom/
            └── scout/
                ├── agent_runner_spec.rb
                ├── contact_notes_service_spec.rb
                └── tools/
                    ├── manage_opportunity_spec.rb
                    ├── move_opportunity_stage_spec.rb
                    ├── update_contact_spec.rb
                    ├── create_private_note_spec.rb
                    └── handover_to_human_spec.rb

db/migrate/
└── 21260819000005_add_pipeline_fields_to_ichatr_scouts.rb
```

**Structure Decision**: Code lives exclusively under `custom/` and `db/migrate/` using standard Chatwoot fork namespaces (`Custom::Scout::*`), matching existing Opportunity and Kanban architecture.

## Complexity Tracking

*No constitutional violations identified. Standard architectural patterns and existing services reused.*
