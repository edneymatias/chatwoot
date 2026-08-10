# Contract: `GET /api/v1/accounts/:account_id/opportunities`

Existing endpoint (`custom/app/controllers/api/v1/accounts/opportunities_controller.rb#index`).
This feature changes its **default filtering behavior only** — no new params, no response shape
change.

## Request

| Param | Before this feature | After this feature |
|---|---|---|
| *(no status param/condition present)* | Returns opportunities of every status | Returns only `status: 'open'` opportunities |
| `status=all` | Not previously meaningful as a bypass (no default existed) | Returns opportunities of every status |
| `status=<open\|won\|lost>` | Filters to that status (unchanged) | Filters to that status (unchanged) — overrides the new default |
| `payload=[{attribute_key: "status", values: [...]}]` | Filters to those statuses (unchanged) | Filters to those statuses (unchanged) — overrides the new default |
| `contact_id=<id>` | Combined with no status → every status | Combined with no status → only `open`, **unless** caller also sends `status=all` (as `fetchForContact` now does) |

## Response

Unchanged — same JSON shape (`payload`/`meta` when paginated, bare array otherwise), same
`Opportunity` serialization. Only the *set* of records returned by default changes.

## Backward compatibility note

Any existing caller that relied on the unfiltered endpoint returning every status by default will
now receive only open opportunities unless it explicitly sends `status=all`. Within this codebase,
the only such caller was `fetchForContact`
(`app/javascript/dashboard/store/modules/opportunities/actions.js`), which is updated in this
feature to send `status: 'all'` explicitly (see [research.md](../research.md#decision-4-fetchforcontact-status-override)).
