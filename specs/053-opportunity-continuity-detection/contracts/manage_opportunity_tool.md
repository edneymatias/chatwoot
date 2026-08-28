# Contract: `manage_opportunity` tool schema & system-prompt context (LLM-facing surface)

This is the feature's externally-visible contract in the sense that matters for this project: the
interface the Scout LLM itself consumes — its tool schema (what parameters it may call with) and
the structured context it's given to reason about which value to pass. Both sides of this contract
change together.

## Tool parameter addition

`Custom::Scout::Tools::ManageOpportunity` gains one new optional parameter, alongside the existing
`action`, `title`, `stage_id`, `estimated_value`, `custom_attributes`:

| Parameter | Type | Required | Description |
|---|---|---|---|
| `opportunity_id` | integer | No | "ID of an existing open Opportunity from the candidate list in context, if this conversation continues one of them. Omit if this is a new deal or you're unsure which one." |

Confirmed against the actually-installed `ruby_llm` gem (1.15.0, per Gemfile.lock): the DSL method
here is `param` (as already used by every existing parameter on this tool), not `parameter` — the
gem's *currently published* docs use `parameter`, but that name doesn't exist in the pinned 1.15.0
`RubyLLM::Tool` source. Keep using `param` during implementation; don't "correct" it from the docs.
Also confirmed: when the LLM omits an optional param, it's simply absent from the args hash passed
to `execute(**args)`, so Ruby's own keyword default (`opportunity_id: nil`) applies — no special
handling needed, identical to how `title: nil` etc. already behave in this tool today.

Backend validation (never trust the declared value at face value, per FR-004): the resolver
(`continuity_resolver_service.md`) checks `opportunity_id` against the real, freshly-queried open
candidate set for the contact — an id outside that set is treated identically to no declaration at
all (`:ambiguous`), including the edge case where the id belongs to a different contact entirely.

## System-prompt structured context addition

`Custom::Scout::SystemPromptsService#build` gains a new context block, added inside (not replacing)
the existing `context_section`, alongside `contact.to_llm_text`. Mirrors the existing
`funnel_section` pattern (`custom/app/services/custom/scout/system_prompts_service.rb:104-142`) of
exposing structured, ID-bearing records the assistant can reference back in a tool call.

Present only when the contact has ≥1 open deal (candidate list empty → section omitted entirely,
matching the "0 candidates → create autonomously" branch needing no extra prompt noise):

```text
[Oportunidades Abertas do Contato]
- ID: 42 | Título: Plano Empresarial | Estágio: Proposta Enviada
- ID: 57 | Título: Upgrade de Plano | Estágio: Qualificação

Se a conversa atual continuar um destes negócios, informe o `opportunity_id` correspondente ao
chamar `manage_opportunity`. Caso contrário, ou se não tiver certeza, não informe `opportunity_id`.
```

Field source per candidate row: `id` (raw), `title` (raw), pipeline stage name (`pipeline_stage.name`
via the existing association — same source `funnel_section` already uses for stage names).

## Guardrail-text reinforcement

`Custom::Scout::SystemPromptsService#guardrails_section` gains one additional bullet instructing the
assistant to call `manage_opportunity` as soon as commercial interest is recognized *at any point*
in the conversation, not only at its outset — addressing spec FR-007. This is a text-only addition
to the existing guardrails list; no new mechanism.

## Backward compatibility

- Omitting `opportunity_id` remains fully valid (existing behavior for contacts with 0 open deals
  is unchanged — User Story 3 / FR-002).
- The tool's existing `action`/`title`/`stage_id`/`estimated_value`/`custom_attributes` parameters
  and their existing validation/update behavior are unchanged.
