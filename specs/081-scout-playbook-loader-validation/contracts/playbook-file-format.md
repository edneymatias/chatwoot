# Contract: Playbook File Format

This is the contract every `custom/playbooks/*.md` file must satisfy, and the one later phases
(brief 02 router, brief 06 playbook authoring) build against. Source of truth for the shape:
`design.md` §4.3; field requiredness: spec.md FR-004; loader/validator behavior for each field:
`data-model.md`.

## Shape

```
---
name: <string, required, unique across the catalog, format [a-z][a-z0-9_]*>
title: <string, required>
priority: <integer, required, unique across the catalog>
when_state:                       # optional, defaults to []
  - <predicate_name>                        # bare form, no argument
  - <predicate_name>: <argument>            # single-key-hash form, with argument
trigger: >
  <string, required — free-form recognition sentence>
requires: [<capability_name>, ...]  # optional, defaults to []
needs:   [<knowledge_item_name>, ...]  # optional, defaults to []
tools:   [<tool_name>, ...]          # optional, defaults to []
exits:
  <ending_name>: { <field_name>: <type_name_string>, ... }   # optional, defaults to {}; ending_name uses the name format
---

<free-form markdown procedure body, preserved verbatim>
```

## Field contract

| Field | Required | Empty/absent behavior | Boot-validated against |
|---|---|---|---|
| `name` | yes, must match `[a-z][a-z0-9_]*` | boot failure if blank or outside the format | uniqueness across catalog |
| `title` | yes | boot failure if blank | — |
| `priority` | yes, must be YAML integer | boot failure if absent/non-integer | uniqueness across catalog |
| `when_state` | no; a list whose entries are a bare predicate name or a single-key mapping | `[]` | every predicate name must be `Predicates::Registry.registered?`; any other shape is a boot failure |
| `trigger` | yes | boot failure if blank | — (not validated for content, only presence) |
| `requires` | no | `[]` | every name must be `Capabilities::Catalog.known?` |
| `needs` | no | `[]` | none |
| `tools` | no | `[]` | none |
| `exits` | no; a mapping whose keys use the name format | `{}` | any other shape or key format is a boot failure; every `exit_<name>` token in the body must match a declared key here |
| body | no | `''` | every `open_playbook(<name>)` token must name an existing catalog playbook |

Frontmatter YAML that cannot be parsed (a syntax error, or a value `YAML.safe_load` refuses, such
as a date) is a boot failure naming the file. The playbooks directory itself must exist (an empty
one is valid); a missing directory fails boot.

## Body reference tokens (static, scanned by the validator, not executed)

- `exit_<ending_name>` — must match a key declared in this same playbook's `exits:`. Example:
  `exits: { agendado: {...} }` requires the body to spell the token as `exit_agendado`. The scan
  captures word characters and hyphens after `exit_`, so `exit_Agendado` or `exit_sem-horario` is
  reported rather than ignored.
- `open_playbook(<name>)` (quotes around `<name>` optional) — `<name>` must be the `name` of some
  playbook loaded in the catalog (may be any playbook, not just this one). The scan captures
  everything inside the parentheses, so a target outside the name format is reported, not ignored.

These are plain substring/regex conventions used only for boot-time reference checking in this
phase; they are not parsed as a DSL and carry no other runtime meaning here (runtime execution of
`open_playbook`/`exit_*` as actual tools is brief 02/05).

## Example (from design.md §4.3, non-normative — no playbook files ship in this phase)

```yaml
---
name: agendamento
title: Agendamento de avaliação
priority: 50
when_state:
  - opportunity_in_stage: qualificado
  - contact_has_phone
trigger: >
  O lead confirmou interesse e quer marcar horário, ou perguntou
  sobre disponibilidade de agenda.
requires: [scheduling, customer_registry]
needs:   [politica_reagendamento]
tools:   [update_contact]
exits:
  agendado:    { opportunity_id: integer, starts_at: datetime }
  sem_horario: { motivo: string }
  handoff:     { reason: string }
---

## Passos

1. ...
3. Com o horário escolhido, marque com `scheduling.book`, ... e encerre com `exit_agendado`.
5. Pedido de atendente, urgência clínica ou duas falhas de cadastro: `exit_handoff`.
```
