# Contract: `campaign_referral_present` Automation Condition

Extends the `message_created` automation trigger's condition set with one boolean filter,
mirroring the existing `private_note` condition end-to-end.

## Filter key definition (`lib/filters/filter_keys.yml`, under `messages:`)

```yaml
campaign_referral_present:
  attribute_type: "standard"
  data_type: "boolean"
  filter_operators:
    - "equal_to"
    - "not_equal_to"
```

## Condition JSON shape (as stored on an `AutomationRule`)

```json
{
  "attribute_key": "campaign_referral_present",
  "filter_operator": "equal_to",
  "values": [true],
  "query_operator": "AND"
}
```

## Evaluation semantics

- `equal_to [true]` → matches when the triggering message's `content_attributes['referral']` is
  present (non-null).
- `equal_to [false]` / `not_equal_to [true]` → matches when it is absent.
- Evaluation is a pure presence check — no other field of `referral` (platform, source_id, etc.)
  is inspectable via this condition in v1 (spec FR-015 / Out of Scope).
- Independent of message text content (FR-009) — this is the entire point of the condition;
  contract tests MUST include a case where the message's `content` has been edited/replaced but
  `referral` is still present, confirming the condition still matches.

## Frontend contract

- `AUTOMATIONS.message_created.conditions` (`constants.js`) gains one entry:
  `{ key: 'campaign_referral_present', name: 'CAMPAIGN_REFERRAL_PRESENT', inputType:
  'search_select', filterOperators: OPERATOR_TYPES_1 }`.
- `conditionFilterMaps` (`automationHelper.js`) gains `campaign_referral_present:
  booleanFilterOptions`.
- i18n keys added to `en.json`/`pt_BR.json` (frontend condition label) and `en.yml`/`pt_BR.yml`
  (backend, if the condition name is rendered server-side anywhere, e.g. audit logs).
