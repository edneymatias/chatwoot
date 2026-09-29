# Contract: state conditions (`when_state`) and their boot validation

## Syntax (unchanged Loader shape)

`when_state` is a YAML list; each entry is either a bare condition name or a single-key mapping
`name: argument`. All entries must hold (logical AND, `Predicates::Evaluator`). The Loader already
normalizes entries to `[name, arg_or_nil]` and records shape errors on `load_errors`; this feature
adds no Loader change.

```yaml
when_state:
  - opportunity_in_stage: qualified   # [ 'opportunity_in_stage', 'qualified' ]
  - contact_has_phone                  # [ 'contact_has_phone', nil ]
  - playbook_not_completed: agendamento
```

Spec notation `playbook_not_completed(agendamento)` ≡ the mapping form above.

## Registry (`Custom::ScoutV2::Predicates::Registry`)

| Name | Class | Argument kind |
|---|---|---|
| `opportunity_open` | existing | none |
| `pending_required_fields` | existing | none |
| `contact_identity_incomplete` | NEW `ContactIdentityIncomplete` | none |
| `contact_has_phone` | NEW `ContactHasPhone` | none |
| `in_qualification` | NEW `InQualification` | none |
| `opportunity_in_stage` | NEW `OpportunityInStage` | `:stage_role` — `qualified`, `unqualified`, `initial` (`OpportunityInStage::ROLES`) |
| `playbook_not_completed` | NEW `PlaybookNotCompleted` | `:playbook_name` — a procedure playbook (non-empty `when_state`) in the loaded catalog |

`Registry.argument_kind(name)` returns `nil`, `:stage_role` or `:playbook_name`.

Evaluation reads only the routing snapshot (`contact`, `opportunity`, `opportunity_stage_role`,
`pending_fields`, `completed_playbooks`); no predicate queries the database itself.

## Boot validation (`Playbook::DependencyRules`, called by `Playbook::Validator`)

One violation line per problem, `"<file>: <message>"`, collected with every other violation into a
single `ValidationError` (existing behavior):

| Problem | Message |
|---|---|
| unregistered name (existing rule, moved) | `Unregistered predicate: <name>` |
| argument-taking condition without argument | `Predicate <name> requires an argument` |
| argument given to a condition that takes none | `Predicate <name> takes no argument (got <arg>)` |
| `opportunity_in_stage` argument not a role | `Unknown stage role for opportunity_in_stage: <arg>` |
| `playbook_not_completed` argument not in catalog | `Unknown playbook for playbook_not_completed: <arg>` |
| `playbook_not_completed` argument names a situational playbook (FR-009a) | `playbook_not_completed must name a procedure playbook: <arg>` |
| `requires` name not a capability (existing rule, moved) | `Unknown capability: <name>` |
| `needs` name not a business fact (NEW, FR-020) | `Unknown business fact: <name>` |
| marker `[[depends: …]]` empty | `Empty pending-step marker` |
| marker name not in own `requires`/`needs` | `Pending-step marker references undeclared requirement: <name>` |

## Routing consequences (no Router change)

`Router` is unchanged: highest-priority playbook with a non-empty, fully-holding `when_state` wins
over the pinned one only if it has higher priority; situational playbooks (empty `when_state`) are
never candidates (FR-023). With the shipped catalog:

| Facts | Candidate by state |
|---|---|
| identity incomplete, `identificacao` not completed | `identificacao` |
| identity complete (or `identificacao` completed), no active opportunity, `qualificacao` not completed | `qualificacao` |
| open opportunity with pending fields, `qualificacao` not completed | `qualificacao` |
| opportunity in qualified stage, phone on record, `agendamento` not completed | `agendamento` |
| anything else | none — the pinned procedure (if any) stays; otherwise baseline only |
