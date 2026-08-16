# Data Model: Meta Referral Attribution Refinements

**Feature**: Meta Referral Attribution Refinements  
**Spec Reference**: `specs/037-meta-referral-attribution-refinements/spec.md`  
**Date**: 2026-08-14  

---

## 1. Schema Modifications (`ichatr_opportunities`)

### Migration: `AddAttributionRefinementsToIchatrOpportunities`

```ruby
class AddAttributionRefinementsToIchatrOpportunities < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_opportunities, :campaign_headline, :string
    add_column :ichatr_opportunities, :campaign_body, :text
    add_column :ichatr_opportunities, :campaign_thumbnail_url, :text
  end
end
```

---

## 2. Entity Definitions

### 2.1 `Opportunity` (`custom/app/models/opportunity.rb`)

Represents a sales opportunity in the Kanban pipeline.

| Attribute | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | `bigint` | No | Primary Key | Opportunity identifier |
| `account_id` | `bigint` | No | Foreign Key | Owning account |
| `campaign_source_id` | `string` | Yes | `nil` | Meta Ad ID or Organic Post ID |
| `campaign_source_url` | `string` | Yes | `nil` | Webhook referral source URL |
| `campaign_platform` | `string` | Yes | `nil` | `facebook`, `instagram` |
| `campaign_name` | `string` | Yes | `nil` | Meta Campaign Name (paid ads) |
| `campaign_adset_name` | `string` | Yes | `nil` | Meta Ad Set Name (paid ads) |
| `campaign_ad_name` | `string` | Yes | `nil` | Meta Ad Name (paid ads) |
| `campaign_headline` | `string` | Yes | `nil` | Headline of the ad or organic post |
| `campaign_body` | `text` | Yes | `nil` | Body copy / text snippet of the post or ad |
| `campaign_thumbnail_url` | `text` | Yes | `nil` | Remote CDN thumbnail URL |
| `campaign_resolution_status` | `string` | Yes | `nil` | Resolution lifecycle state |

#### ActiveStorage Attachment:
```ruby
has_one_attached :campaign_thumbnail
```

#### Status Enum / Allowed Values:
- `'pending'`: Awaiting async resolution via Meta Graph API.
- `'resolved'`: Successfully resolved as a paid ad.
- `'organic_post'`: Identified as an organic Facebook/Instagram publication or story.
- `'failed'`: Resolution failed (invalid ID, node mismatch, unrecoverable query error).
- `'not_applicable'`: No referral attribution payload present on conversation.

---

## 3. Resolution Lifecycle & State Transitions

```
[Inbound WhatsApp Message with Referral]
                   │
                   ▼
  Is source_type == 'post' or organic post payload?
        ├── YES ──► Save headline, body, thumbnail
        │           Set status: 'organic_post'
        │           Enqueue: Meta::AttachCampaignThumbnailJob
        │
        └── NO ───► Is ad_id present?
                      ├── NO  ──► Set status: 'not_applicable'
                      └── YES ──► Set status: 'pending'
                                  Enqueue: Custom::CampaignResolutionJob
                                              │
                    ┌─────────────────────────┴────────────────────────┐
                    ▼                                                  ▼
          [Meta Graph API Success]                             [Meta Graph API Error]
                    │                                                  │
          Set status: 'resolved'                       ├── Meta::AuthenticationError
          Save campaign/adset/ad names                 │   Set status: 'failed'
          Save headline/body/thumbnail                 │   setting.update!(enabled: false)
          Enqueue: AttachCampaignThumbnailJob          │
                                                       ├── Meta::RateLimitError
                                                       │   retry_job wait: 2.minutes
                                                       │
                                                       └── Meta::NodeNotFoundError / ApiError
                                                           Set status: 'failed' (account stays enabled)
```

---

## 4. Serialization (`Opportunity` JSON Representation)

The API response for opportunities adds:

```json
{
  "id": 123,
  "title": "Oportunidade #45",
  "campaign_source_id": "12020584938290123",
  "campaign_source_url": "https://fb.me/...",
  "campaign_platform": "instagram",
  "campaign_name": "Campanha Black Friday 2026",
  "campaign_adset_name": "Público Aberto 25-45",
  "campaign_ad_name": "Criativo Vídeo 01",
  "campaign_headline": "Super Promoção de Lançamento",
  "campaign_body": "Garanta seu acesso com condições especiais hoje mesmo.",
  "campaign_thumbnail_url": "/rails/active_storage/blobs/proxy/.../thumbnail.jpg",
  "campaign_resolution_status": "resolved"
}
```
