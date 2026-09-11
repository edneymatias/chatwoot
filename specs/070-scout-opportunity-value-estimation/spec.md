# Feature Specification: Scout Opportunity Value Estimation

**Feature Branch**: `070-scout-opportunity-value-estimation`

**Created**: 2026-09-11

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/26-scout-opportunity-value-estimation/spec91.md" — Fase 26 do Scout: preencher automaticamente o valor monetário de uma Oportunidade a partir de um atributo de qualificação de interesse já configurado pela clínica (uma tabela interesse→valor mantida pelo operador), tanto quando o interesse é inferido do conteúdo do anúncio de origem quanto quando vem da resposta real do lead — nunca de um número inventado pelo modelo.

## Clarifications

### Session 2026-09-11

- Q: How should the system behave if an ad-content classification attempt technically fails (e.g., an error calling the classification model), rather than returning an ambiguous or no-match result? → A: Treat as not identified — failure is silently equivalent to "not identified" (no automatic value, conversation proceeds normally, failure visible only to engineers, not the admin or lead).
- Q: When an admin is choosing which qualification attribute to designate as the Scout's "interest" signal, should the configuration screen only let them pick from fixed-list attributes, or can they pick any attribute with the feature silently having no effect for unsupported types? → A: Restrict to list-type only — the configuration screen only offers fixed-list attributes as selectable options for "interest".
- Q: Should the interest qualification attribute be selectable from both contact and opportunity models, or strictly opportunity? → A: Restrict strictly to Opportunity model (`opportunity_attribute`) — since the interest signal and its estimated value belong directly to the Opportunity record, only list-type opportunity attributes are eligible.
- Q: What UI component pattern should be used for selecting the interest attribute in the Scout Funnel settings tab? → A: Interactive button chips (`[Nenhum (desativado)] [Interesse] ...`) with single-select behavior, matching the visual design and 1-click ergonomics of the "Campos Obrigatórios de Qualificação" section directly above it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure the interest-to-value table (Priority: P1)

An admin who already tracks an "interest" qualification attribute for their Scout (e.g. treatment type, service tier — a fixed list of options) wants to tell the system how much each of those options is typically worth, so that opportunities their Scout creates carry a realistic monetary value instead of always showing zero.

**Why this priority**: Without a configured table, there is nothing for the rest of the feature to look up — this is the foundation every other story depends on, and it is what keeps the feature safe (no value is ever invented without an operator-provided number behind it).

**Independent Test**: Can be fully tested by configuring a Scout's interest attribute and a value for one or more of its options, and confirming the configuration is saved and readable back, with no other behavior required.

**Acceptance Scenarios**:

1. **Given** a Scout that already has a list-type qualification attribute available, **When** an admin designates it as the Scout's "interest" attribute and assigns a monetary value to one or more of its options, **Then** that mapping is saved against the Scout.
2. **Given** a Scout's interest-to-value mapping, **When** an admin leaves one of the attribute's options without an assigned value (e.g. a catch-all "Other" option), **Then** that option is simply left unmapped — no default or placeholder value is required.
3. **Given** a Scout with no interest attribute designated, **When** the admin views the Scout's configuration, **Then** the value-estimation setting is clearly optional and inactive, with no behavior change elsewhere.

---

### User Story 2 - Opportunity value pre-filled from ad content before the lead replies (Priority: P2)

A lead arrives from a paid ad and an Opportunity is automatically created for them. Before the lead sends a single reply, the business wants the Opportunity's value already populated when the ad's own content (headline, body, ad/campaign name) clearly signals which interest option it targets — so forecast and pipeline reports reflect real expected revenue from the very first moment, not just after a human or the lead fills it in later.

**Why this priority**: This is the scenario the feature exists to fix — today, every Scout-originated opportunity reports as zero value until a human manually edits it, which silently deflates sales forecasting. Depends on Story 1 having a configured table to look up.

**Independent Test**: Can be fully tested by creating an Opportunity from a referral whose ad content clearly matches one configured interest option, and confirming the Opportunity is created with both the interest qualification and its mapped value already filled in, with no lead reply yet received.

**Acceptance Scenarios**:

1. **Given** a Scout with an interest attribute and value table configured, **When** a new Opportunity is created from a lead whose originating ad content clearly identifies one of the configured interest options, **Then** the Opportunity is created with that interest option and its mapped monetary value already set.
2. **Given** the same setup, **When** the originating ad content is ambiguous, generic, or does not clearly match any configured option, **Then** no interest or value is set automatically, and the conversation continues asking the qualification question as it does today.
3. **Given** a matched interest option that has no value assigned in the table (e.g. "Other"), **When** the Opportunity is created, **Then** the interest option may still be recorded but no monetary value is assigned — not zero, not a placeholder.
4. **Given** an Opportunity not created from a paid-ad referral (e.g. organic conversation), **When** it is created, **Then** no automatic ad-content classification is attempted, since there is no ad content to classify.

---

### User Story 3 - Opportunity value stays in sync with the lead's own answer (Priority: P3)

During normal qualification, a lead tells the Scout which treatment/service they're interested in — either because no ad-based guess was made, or because they say something different from what the ad content suggested. The Opportunity's value must reflect the lead's actual answer, using the same operator-configured table.

**Why this priority**: This guarantees the value stays accurate even when the automatic ad-content guess (Story 2) was wrong, skipped, or never applicable — it's the safety net that makes the feature trustworthy end-to-end, but it depends on the table from Story 1 and is meaningful on its own even without Story 2.

**Independent Test**: Can be fully tested by having a lead answer the interest qualification question directly (no prior ad-based guess involved) and confirming the Opportunity's value updates to match the configured table entry for that answer.

**Acceptance Scenarios**:

1. **Given** a Scout with an interest attribute and value table configured, **When** a lead's qualification answer sets the interest attribute on their Opportunity, **Then** the Opportunity's value is updated to the mapped value for that answer.
2. **Given** an Opportunity whose interest was already set by automatic ad-content classification (Story 2), **When** the lead later gives a qualification answer that sets a different interest option, **Then** the Opportunity's value is updated to reflect the lead's answer, not the earlier ad-based guess.
3. **Given** an interest option the lead selects that has no value configured in the table, **When** the interest attribute is set, **Then** the Opportunity's existing value (if any) is left unchanged rather than being cleared or zeroed.

---

### Edge Cases

- What happens when a Scout has an interest attribute configured but the value table is completely empty? No value is ever assigned automatically; behavior is identical to having no table configured.
- What happens when the admin changes the value table after opportunities already exist? Existing opportunities are not retroactively recalculated — the new mapping only applies going forward.
- What happens when the qualification attribute chosen as "interest" is not a fixed-list type (e.g. free text)? This is prevented at configuration time — only fixed-list attributes are offered as selectable "interest" options, so this misconfiguration cannot occur.
- What happens when the ad content is present but the lead's Scout has no interest attribute configured at all? No classification is attempted and no value is assigned — the feature is fully inactive.
- What happens when the classification attempt itself technically fails (e.g., an error calling the classification model, not just an inconclusive result)? It is treated identically to "not identified" — no automatic value is assigned, the qualification conversation proceeds normally, and the failure is only visible to engineers via internal error tracking, never surfaced to the admin or the lead.
- What happens when a value is already set on an Opportunity (e.g. entered manually by a human) and the automatic flow would compute a different one? The automatic sync always applies the mapped value when the interest attribute changes, so the most recent interest signal (ad-based guess, then lead's own answer) determines the value shown.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow an admin to designate one existing fixed-list opportunity qualification attribute per Scout as its "interest" signal for value estimation, offering only fixed-list opportunity attributes as selectable options via single-select chips (attributes of other types or models MUST NOT be selectable).
- **FR-002**: The system MUST allow an admin to configure a monetary value for any subset of that attribute's options, leaving others unmapped.
- **FR-003**: The system MUST leave all existing behavior unchanged for any Scout that has no interest attribute designated.
- **FR-004**: When a new Opportunity is created from a paid-ad referral, the system MUST attempt to determine which configured interest option the ad's own content (name, headline, body, ad/adset name) clearly indicates, without prompting the lead.
- **FR-005**: The system MUST only apply an automatically-determined interest option when it can be identified with confidence from the ad content; ambiguous, generic, or unclear content MUST result in no automatic interest or value assignment, distinct from and never defaulting to a catch-all business option.
- **FR-005a**: A technical failure during the classification attempt (e.g., an error from the classification model) MUST be handled identically to an inconclusive result — no automatic interest or value assignment, normal conversation flow continues, and the failure is recorded only for internal engineering visibility, never surfaced to the admin or the lead.
- **FR-006**: Whenever an Opportunity's interest attribute is set or changed — whether by automatic ad-content classification or by the lead's own qualification answer — the system MUST look up the configured value table and update the Opportunity's value when a mapping exists for that option.
- **FR-007**: The system MUST NOT assign any monetary value (including zero or a placeholder) to an Opportunity when the current interest option has no corresponding entry in the value table.
- **FR-008**: The system MUST NOT generate, guess, or let an AI model freely invent a monetary value at any point in this flow — every assigned value MUST trace back to an operator-configured table entry.
- **FR-009**: The system MUST NOT retroactively recompute the value of Opportunities already created when the operator later edits the value table.
- **FR-010**: The monetary value assigned through this flow MUST remain purely internal (used for reporting/forecasting) and MUST NOT be disclosed to the lead/customer in conversation.

### Key Entities

- **Scout**: The automated sales-qualification agent configuration. Gains an optional link to one opportunity qualification attribute ("interest") and an operator-maintained table mapping that attribute's options to monetary values.
- **Opportunity**: The sales pipeline record created for a qualified lead. Its qualification attributes (including "interest") and its monetary value are the fields this feature reads and writes.
- **Qualification Attribute ("Interest")**: An existing fixed-list opportunity custom attribute (`opportunity_attribute`) the clinic already uses to categorize what a lead is interested in (e.g. treatment type). Provides the closed set of options the automatic classification must choose from, or explicitly find none of.
- **Interest-to-Value Table**: The operator-configured mapping from each interest option to a monetary amount. The single source of truth consulted regardless of whether the interest was set automatically (from ad content) or by the lead's own answer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Sales forecast and pipeline-value reports for accounts using this feature no longer count Scout-originated opportunities as zero value by default.
- **SC-002**: 100% of Opportunities created from ad referrals whose content clearly matches a configured interest option carry a populated value at creation time, before any lead reply is received.
- **SC-003**: 0% of Opportunity values produced by this flow are freely generated numbers — every non-empty value is traceable to an operator-configured table entry.
- **SC-004**: Opportunities whose ad content is ambiguous or whose matched interest has no configured value show no automatically-assigned value (verified by absence of value, not a zero or placeholder), preserving the existing qualification conversation flow.
- **SC-005**: Enabling this feature for a Scout requires only configuring the interest attribute and its value table — no code change or per-campaign setup is needed to keep values accurate as ad campaigns change.

## Assumptions

- The qualification attribute used as "interest" is a fixed-list attribute with a small, stable set of options; free-text or other attribute types are out of scope for this feature and are not offered as selectable options when configuring it.
- Ad-content-based classification only applies to Opportunities created from a paid-ad referral where campaign content (name, headline, body, ad/adset name) is available; organic conversations rely solely on the lead's own qualification answer.
- Leaving an interest option out of the value table is an intentional operator choice (e.g. a catch-all "Other" bucket) and must never receive a value, not even zero.
- The monetary value produced by this feature is for internal reporting and forecasting only; it is unrelated to, and does not affect, any existing guardrail about never disclosing prices to the customer in conversation.
- Manually-entered values on an Opportunity remain editable by a human as they are today; this feature only changes what the system fills in automatically and when.
