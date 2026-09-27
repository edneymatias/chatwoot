# Contract: V2 `[Identity]` Section

Producer: `Custom::ScoutV2::Instructions::IdentityBuilder.call(scout:)` → String.
Consumer: `Custom::ScoutV2::Instructions::Builder` (first of the four sections, joined with `"\n\n"`),
used by `Custom::ScoutV2::TurnRunner` on every turn (inbox and playground).

Placeholders: `{name}` = `scout.name`, `{account}` = `scout.account.name`, `{role}` = `scout.role`,
`{scope}` = `scout.scope` (stored values, inserted verbatim — internal line breaks preserved, no
squish/escape). Lines joined with a single `"\n"`; no trailing newline.

## Fixed statements

| Name | Text |
|---|---|
| DEFAULT_INTRO | `Você é {name}, um assistente inteligente de qualificação comercial e vendas da empresa {account}.` |
| NEUTRAL_INTRO | `Você é {name}, assistente da empresa {account}.` |
| DEFAULT_PURPOSE | `Seu objetivo é qualificar leads, tirar dúvidas sobre produtos e serviços e auxiliar no processo comercial.` |
| DEFAULT_SCOPE | `Você deve responder apenas sobre os produtos, serviços, catálogo e informações fornecidas neste contexto ou acessíveis através das ferramentas disponíveis.` |

## Output per case

**Both empty** (FR-005, SC-003 — byte-identical to pre-feature output):

```text
[Identity]
DEFAULT_INTRO
DEFAULT_PURPOSE
DEFAULT_SCOPE
```

**Role filled, Scope empty** (US1-3, FR-002/FR-003):

```text
[Identity]
NEUTRAL_INTRO
{role}
DEFAULT_SCOPE
```

**Role empty, Scope filled** (US1-4, FR-004):

```text
[Identity]
DEFAULT_INTRO
DEFAULT_PURPOSE
{scope}
```

**Both filled** (US1-1):

```text
[Identity]
NEUTRAL_INTRO
{role}
{scope}
```

Example with multi-line Scope (FR-004a) — stored `"- não informa preços de tratamento\n- não agenda urgências"`:

```text
[Identity]
Você é Clara, assistente da empresa Sorriso Odonto.
SDR da clínica, atende pacientes adultos em São Paulo.
- não informa preços de tratamento
- não agenda urgências
```

## Invariants

- Never contains any `persona`/`system_prompt` content (FR-006).
- Role filled ⇒ output contains neither the substring `assistente inteligente de qualificação comercial e vendas`
  nor DEFAULT_PURPOSE.
- Scope filled ⇒ output does not contain DEFAULT_SCOPE.
- Role and Scope fall back independently.
- `[Communication]`, `[Memory]`, `[Safety]` are unaffected by Role/Scope; `[Safety]` keeps the
  anti-hallucination and commercial-scope rules in every case (FR-004).
- Legacy V1 prompt (`Custom::Scout::SystemPromptsService.build`) is independent of `role`, `scope`,
  `tone`, `response_length`, `greeting` (FR-007, SC-004).
