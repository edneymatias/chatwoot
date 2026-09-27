# Contract: Scout General Settings Screen — "New version of the Scout" section

Component: `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutGeneralSettings.vue`
(mounted by `routes/dashboard/scout/pages/ScoutDetail.vue` with `:scout` from `ScoutAPI.show`;
`@updated` refetches). Rendered for every scout — no feature-flag or engine check (FR-014).

## Placement

Existing fields keep their order and copy (Name, Persona — label/placeholder/hint unchanged per
FR-020 — then debounce/quota). The new section sits between Persona and the debounce/quota grid:
section title + one-line description, then Role, Scope, Tone + Response length (two-column grid
on `md+`, like debounce/quota), Greeting.

## Fields

| Field | Component | Binding | Constraints | Prefill from `scout` |
|---|---|---|---|---|
| Role | `TextArea` (`components-next/textarea`) | `role` | `:max-length="500"`, `show-character-count`, `auto-height`; counter renders `"{used} / 500"`; native `maxlength` stops typing at 500 | `scout.role \|\| ''` |
| Scope | `TextArea` | `scope` | same as Role | `scout.scope \|\| ''` |
| Tone | `Select` (`components-next/select`) | `tone` | options exactly `friendly, neutral, matter_of_fact, professional, humorous`, in this order, translated labels | `scout.tone` |
| Response length | `Select` | `responseLength` | options exactly `concise, standard, thorough`, in this order, translated labels | `scout.response_length` |
| Greeting | `Input` (`components-next/input`) | `greeting` | none new | `scout.greeting \|\| ''` |

Every field has a label and a hint (`text-[11px] text-n-slate-10`, same pattern as Persona); each
hint states that the setting applies to the new version of the Scout; the Greeting hint also
advises leaving it blank when the inbox already sends its own greeting (FR-017). Role, Scope and
Greeting have placeholders.

## Save payload (`ScoutAPI.update(scout.id, payload)`)

Existing keys unchanged (`name`, `persona`, `debounce_delay_seconds`, `responses_quota`,
`enabled`) plus:

```js
{
  role: role.value,               // as typed; server trims / nulls
  scope: scope.value,             // as typed; server trims / nulls
  tone: tone.value,               // one of the 5 names
  response_length: responseLength.value, // one of the 3 names
  greeting: greeting.value || null, // empty ⇒ null, as a never-filled Greeting
}
```

## i18n keys (`app/javascript/dashboard/i18n/locale/{en,pt_BR}/scout.json`, under `SCOUT.GENERAL`)

```text
V2_SECTION_TITLE, V2_SECTION_DESCRIPTION,
ROLE_LABEL, ROLE_PLACEHOLDER, ROLE_HINT,
SCOPE_LABEL, SCOPE_PLACEHOLDER, SCOPE_HINT,
TONE_LABEL, TONE_HINT,
TONE_OPTIONS.{FRIENDLY, NEUTRAL, MATTER_OF_FACT, PROFESSIONAL, HUMOROUS},
RESPONSE_LENGTH_LABEL, RESPONSE_LENGTH_HINT,
RESPONSE_LENGTH_OPTIONS.{CONCISE, STANDARD, THOROUGH},
GREETING_LABEL, GREETING_PLACEHOLDER, GREETING_HINT
```

Option label key = `SCOUT.GENERAL.TONE_OPTIONS.${value.toUpperCase()}` /
`SCOUT.GENERAL.RESPONSE_LENGTH_OPTIONS.${value.toUpperCase()}`. Every key exists in both files
(FR-021, SC-007). No bare strings in the template.

## Observable behaviors (component-test surface)

1. The five fields render for a scout regardless of any flag.
2. Prefill: a scout with `tone: 'professional'`, `response_length: 'thorough'`, `role`, `scope`,
   `greeting` set shows those values; a scout with `role/scope/greeting: null` shows empty fields
   and the counters show `0 / 500`.
3. Tone `<select>` has exactly 5 `<option>`s with the values above; Response length exactly 3.
4. Role/Scope `<textarea>` carry `maxlength="500"`; a 500-char value renders `500 / 500`.
5. Clicking Save calls `ScoutAPI.update(id, payload)` with the five keys and the edited values;
   an empty Greeting is sent as `null`.
6. Hint texts (en), asserted as literal phrases in the rendered hints — not values read back from
   the catalog: each of the five hints states that the setting applies to the new version of the
   Scout, and the Greeting hint advises leaving it blank when the inbox already sends its own
   greeting (FR-017, US2-AC1/AC5).
7. After switching `locale.value` to `pt_BR` on the i18n instance returned by `withFullI18n()`,
   labels, options and the Greeting hint render the Portuguese text from `pt_BR/scout.json`, not the
   key path (FR-021, SC-007).
