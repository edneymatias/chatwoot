# Contract: Opportunity Attribution UI & Payload

## 1. Opportunity JSON Representation

When opportunities are retrieved via Kanban or List APIs (`/api/v1/accounts/:account_id/opportunities`):

```json
{
  "id": 482,
  "title": "Oportunidade #1042",
  "status": "open",
  "value": 1500.0,
  "campaign_source_id": "12020584938290123",
  "campaign_source_url": "https://fb.me/xyz",
  "campaign_platform": "instagram",
  "campaign_name": "Campanha Conversão Q3",
  "campaign_adset_name": "Lookalike 1% Compradores",
  "campaign_ad_name": "Anúncio Oferta Principal",
  "campaign_headline": "Garanta seu plano com 30% OFF",
  "campaign_body": "Condição exclusiva válida apenas para as próximas 48 horas.",
  "campaign_thumbnail_url": "https://chatwoot.example.com/rails/active_storage/blobs/proxy/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBZzA9.../ad_thumbnail.jpg",
  "campaign_resolution_status": "resolved"
}
```

### Organic Post Opportunity Example

```json
{
  "id": 483,
  "title": "Oportunidade #1043",
  "status": "open",
  "value": null,
  "campaign_source_id": "179834729182348",
  "campaign_source_url": "https://instagram.com/p/Cxyz123",
  "campaign_platform": "instagram",
  "campaign_name": null,
  "campaign_adset_name": null,
  "campaign_ad_name": null,
  "campaign_headline": "Dica da semana: como escalar suas vendas",
  "campaign_body": "Confira no post de hoje o passo a passo completo...",
  "campaign_thumbnail_url": "https://chatwoot.example.com/rails/active_storage/blobs/proxy/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBZzQ9.../post_thumbnail.jpg",
  "campaign_resolution_status": "organic_post"
}
```

---

## 2. Frontend Composable Contract (`useOpportunityCardFields.js`)

Returns computed `campaignAttribution`:

```javascript
{
  icon: 'i-lucide-instagram', // or 'i-lucide-facebook', 'i-lucide-megaphone'
  status: 'resolved', // 'resolved' | 'organic_post' | 'pending' | 'failed'
  platform: 'instagram',
  isOrganic: false,
  title: 'Campanha Conversão Q3',
  subtitle: 'Lookalike 1% Compradores • Anúncio Oferta Principal',
  headline: 'Garanta seu plano com 30% OFF',
  body: 'Condição exclusiva válida apenas para as próximas 48 horas.',
  thumbnailUrl: 'https://chatwoot.example.com/rails/active_storage/blobs/...',
  sourceUrl: 'https://fb.me/xyz',
  sourceId: '12020584938290123',
  errorLabel: null
}
```
