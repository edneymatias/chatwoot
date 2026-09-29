# Contract: Exit declarations in playbook frontmatter

Consumer: playbook authors (`custom/playbooks/*.md`, fixture catalogs via `SCOUT_V2_PLAYBOOKS_DIR`).
Producer/checker: `Custom::ScoutV2::Playbook::Loader` (shape) and `Custom::ScoutV2::Playbook::Validator`
(semantics), run at boot by `config/initializers/scout_v2_playbooks.rb`.

## Grammar

```yaml
exits:                      # optional; mapping; omitted ⇒ no exits
  <exit_name>:              # /\A[a-z][a-z0-9_]*\z/, not "handoff"
    kind: terminal | transition | escalation     # required
    fields:                 # optional mapping, declaration order is kept
      <field_name>: string | integer | number | boolean | datetime
    target: <playbook name> # transition only, required there
    stage: qualified | unqualified               # optional, any kind
```

Tool name offered to the model: `exit_<exit_name>`. A body may reference `exit_<exit_name>` for
declared exits and `exit_handoff` without declaring it.

## Example (fixture)

```yaml
---
name: fluxo_teste
title: Fluxo de teste
priority: 20
when_state:
  - opportunity_open
trigger: Fixture com as três espécies de exit.
tools: [manage_opportunity]
exits:
  concluido:
    kind: terminal
    fields: { resumo: string }
  seguir_outro:
    kind: transition
    target: outro_procedimento
  qualificado:
    kind: escalation
    stage: qualified
    fields: { motivo: string, quantidade: integer }
---
Encerre com `exit_concluido`, siga com `exit_seguir_outro`, ou transfira com `exit_qualificado`
(ou `exit_handoff` em qualquer outro caso).
```

## Rejections (all reported in one pass, boot fails with `Validator::ValidationError`)

Each violation is prefixed with the file path, like the existing ones.

| Condition | Stage | Message (contains) |
|---|---|---|
| `exits` not a mapping | Loader | `exits must be a mapping` (existing) |
| exit entry not a mapping | Loader | `Invalid exit '<name>': expected a mapping` |
| `fields` not a mapping | Loader | `Invalid exit '<name>': fields must be a mapping` |
| unknown key in an exit entry | Loader | `Invalid exit '<name>': unknown key '<key>'` |
| exit name outside format | Validator | `Invalid exit name` (existing) |
| exit named `handoff` | Validator | `Reserved exit name: handoff` |
| situational playbook declares any exit | Validator | `Situational playbook cannot declare exits: <name>` |
| `kind` missing or unknown | Validator | `Unknown exit kind for '<name>': <kind>` |
| transition without `target` | Validator | `Transition exit '<name>' requires a target` |
| `target` not in catalog | Validator | `Unknown transition target for '<name>': <target>` |
| `target` is the declaring playbook | Validator | `Transition exit '<name>' cannot target its own playbook` |
| `target` is situational | Validator | `Transition exit '<name>' cannot target situational playbook <target>` |
| `target` on terminal/escalation | Validator | `Exit '<name>' declares a target but is not a transition` |
| field name outside format | Validator | `Invalid field name in exit '<name>': <field>` |
| field type outside set | Validator | `Unsupported field type in exit '<name>': <field>: <type>` |
| `stage` outside set | Validator | `Unknown stage role for '<name>': <stage>` |
| body references undeclared `exit_x` (x ≠ handoff) | Validator | `Undeclared exit token: exit_x` (existing) |

Situational = `when_state` empty (Brief 11 meaning).
