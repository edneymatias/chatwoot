# Contracts: Scout Native Tools

**Branch**: `043-scout-native-tools-pipeline` | **Date**: 2026-08-19 | **Spec**: [spec.md](file:///home/matias/dev/chatwoot/specs/043-scout-native-tools-pipeline/spec.md)

All native tools inherit from `RubyLLM::Tool` and are instantiated per turn with the active `scout` and `conversation` context.

---

## 1. `manage_opportunity`

Creates or updates a commercial Opportunity in the sales pipeline for the current conversation, preserving initial Meta/CTWA campaign attribution.

### Tool Definition
- **Tool Name**: `manage_opportunity`
- **Description**: `Creates or updates a commercial Opportunity in the sales pipeline for the current conversation.`

### Parameters

```json
{
  "type": "object",
  "properties": {
    "action": {
      "type": "string",
      "enum": ["create", "update"],
      "description": "Action to perform. Use 'create' for new leads and 'update' to adjust attributes.",
      "default": "create"
    },
    "title": {
      "type": "string",
      "description": "Descriptive title for the Opportunity card."
    },
    "stage_id": {
      "type": "integer",
      "description": "Target pipeline stage ID. If omitted during create, defaults to the Scout's default pipeline stage."
    },
    "estimated_value": {
      "type": "number",
      "description": "Estimated deal or contract value in account currency."
    },
    "custom_attributes": {
      "type": "object",
      "description": "Key-value map of qualification fields (e.g., pain point, budget, decision maker, timing)."
    }
  }
}
```

### Return Format
```json
{
  "success": true,
  "action": "created",
  "opportunity": {
    "id": 123,
    "title": "Oportunidade #456",
    "stage_id": 10,
    "value": 1500.0,
    "status": "open",
    "campaign_headline": "Promoção Exclusiva",
    "campaign_platform": "facebook"
  }
}
```

---

## 2. `move_opportunity_stage`

Moves the conversation's Opportunity to a new pipeline stage and records a lost reason if disqualified.

### Tool Definition
- **Tool Name**: `move_opportunity_stage`
- **Description**: `Moves the conversation's Opportunity to a new pipeline stage and records a reason if lost or disqualified.`

### Parameters

```json
{
  "type": "object",
  "properties": {
    "stage_id": {
      "type": "integer",
      "description": "Target pipeline stage ID to move the Opportunity into."
    },
    "lost_reason": {
      "type": "string",
      "description": "Reason for loss/disqualification when moving to an unqualified or lost stage."
    }
  },
  "required": ["stage_id"]
}
```

### Return Format
- On success:
  ```json
  {
    "success": true,
    "opportunity_id": 123,
    "stage_id": 12,
    "status": "lost",
    "lost_reason": "Orçamento insuficiente"
  }
  ```
- When no Opportunity exists for conversation (graceful failure):
  ```json
  {
    "success": false,
    "message": "No opportunity found for this conversation."
  }
  ```

---

## 3. `update_contact`

Updates contact details and custom qualification attributes.

### Tool Definition
- **Tool Name**: `update_contact`
- **Description**: `Updates the contact profile information (name, email, phone number, and custom attributes).`

### Parameters

```json
{
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Contact's full or preferred name."
    },
    "email": {
      "type": "string",
      "description": "Contact's email address."
    },
    "phone": {
      "type": "string",
      "description": "Contact's phone number."
    },
    "custom_attributes": {
      "type": "object",
      "description": "Key-value map of contact attributes to update or merge."
    }
  }
}
```

### Return Format
```json
{
  "success": true,
  "contact_id": 789,
  "updated_fields": ["name", "email", "custom_attributes"]
}
```

---

## 4. `create_private_note`

Posts an internal private note on the conversation visible only to the internal team.

### Tool Definition
- **Tool Name**: `create_private_note`
- **Description**: `Creates an internal private note on the conversation with summary notes for the human sales team.`

### Parameters

```json
{
  "type": "object",
  "properties": {
    "content": {
      "type": "string",
      "description": "The markdown or text content of the private note."
    }
  },
  "required": ["content"]
}
```

### Return Format
```json
{
  "success": true,
  "message_id": 9999,
  "private": true
}
```

---

## 5. `handover_to_human`

Hands over the conversation to a human agent or team, moving the conversation status from `pending` to `open` and halting further bot replies.

### Tool Definition
- **Tool Name**: `handover_to_human`
- **Description**: `Transfers the conversation to a human agent or team and stops AI responses.`

### Parameters

```json
{
  "type": "object",
  "properties": {
    "assignee_id": {
      "type": "integer",
      "description": "ID of the specific human agent to assign (optional)."
    },
    "team_id": {
      "type": "integer",
      "description": "ID of the team to assign (optional; falls back to Scout handover_team_id if omitted)."
    },
    "reason": {
      "type": "string",
      "description": "Explanation of why the conversation is being transferred to a human."
    }
  }
}
```

### Return Format
```json
{
  "success": true,
  "handoff_executed": true,
  "status": "open",
  "assigned_team_id": 4,
  "assigned_user_id": 15
}
```
