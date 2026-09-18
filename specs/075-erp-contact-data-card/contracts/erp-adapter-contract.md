# Internal Contract: ERP Adapter Base & Provider Contract

**Location**: `custom/app/services/erp/base_adapter.rb`
**Subclasses**: `custom/app/services/erp/younus/adapter.rb` (and future ERP adapters)

---

## 1. Responsibilities

- **`Erp::BaseAdapter`**: Holds the shared resolution algorithm, contact external ID cache read/write/clear operations, phone normalization and matching logic, and exception contracts.
- **Provider Subclasses (e.g., `Erp::Younus::Adapter`)**: Implement only provider-specific primitives (`find_by_id`, `search_by_phone`, `phone_from`, `external_id_from`, `test_connection`).

---

## 2. Base Adapter Interface (`Erp::BaseAdapter`)

### 2.1 Public Methods
- `initialize(hook)`: Receives `Integrations::Hook` instance and stores `@hook` and `@settings`.
- `fetch_data(contact)`: Drives the full resolution flow and returns `{ status: 'found', data: <hash>, multiple_matches: <boolean> }` or `{ status: 'not_found' }`. Raises `Erp::AuthenticationError` or `Erp::ApiError` on external failures.
- `erp_name`: Returns `self.class.erp_name`.

### 2.2 Subclass Required Class Methods
- `self.erp_name`: Returns the human-readable identifier (e.g., `'Younus'`). Raises `NotImplementedError` if not implemented.

### 2.3 Subclass Required Instance Methods
- `find_by_id(external_id)`:
  - Input: `external_id` (`string` or `integer`).
  - Output: Customer record `hash` if found; `nil` if not found.
  - Raises: `Erp::AuthenticationError`, `Erp::ApiError`.
- `search_by_phone(phone)`:
  - Input: `phone` (`string` digits).
  - Output: `{ record: <hash>, multiple_matches: <boolean> }` or `nil` if not found.
  - Raises: `Erp::AuthenticationError`, `Erp::ApiError`.
- `phone_from(data)`:
  - Input: Customer record `hash`.
  - Output: Raw phone number string extracted from `data`.
- `external_id_from(data)`:
  - Input: Customer record `hash`.
  - Output: External ID string or integer extracted from `data`.
- `test_connection`:
  - Output: `true` if credentials are valid; raises error otherwise.

### 2.4 Shared Helper Methods in Base Class
- `get_external_id(contact)`: Reads `contact.additional_attributes.dig('external', external_id_key)`.
- `store_external_id(contact, external_id)`: Writes to `contact.additional_attributes['external'][external_id_key]` and calls `contact.save!`.
- `clear_external_id(contact)`: Deletes `contact.additional_attributes['external'][external_id_key]` and calls `contact.save!`.
- `external_id_key`: Returns `"#{erp_name.downcase}_id"`.
- `phone_matches?(contact, erp_data)`: Compares normalized digits with fallback stripping country code `55`.
