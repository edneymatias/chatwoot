import { ref } from 'vue';
import { describe, it, expect, vi } from 'vitest';
import { useOpportunityCardFields } from '../useOpportunityCardFields';

vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      'pipelineStages/stageById': () => ({ stale_after_days: 5 }),
      'pipelineCurrencySetting/getCurrency': 'usd',
      'pipelineCardFieldConfigs/getRecords': [],
      'attributes/getAttributesByModel': () => [],
    },
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, fallback) => fallback || key,
    locale: ref('en'),
  }),
}));

describe('useOpportunityCardFields', () => {
  it('computes campaignAttribution for organic posts', () => {
    const opportunity = ref({
      id: 1,
      title: 'Organic Opportunity',
      campaign_platform: 'instagram',
      campaign_source_id: '123456',
      campaign_source_url: 'https://instagram.com/p/abc',
      campaign_headline: 'Organic Headline',
      campaign_body: 'Organic Post Body',
      campaign_thumbnail_url: 'https://example.com/thumb.jpg',
      campaign_resolution_status: 'organic_post',
    });

    const { campaignAttribution } = useOpportunityCardFields(opportunity);

    expect(campaignAttribution.value).not.toBeNull();
    expect(campaignAttribution.value.icon).toBe('i-lucide-instagram');
    expect(campaignAttribution.value.isOrganic).toBe(true);
    expect(campaignAttribution.value.headline).toBe('Organic Headline');
    expect(campaignAttribution.value.body).toBe('Organic Post Body');
    expect(campaignAttribution.value.thumbnailUrl).toBe(
      'https://example.com/thumb.jpg'
    );
  });

  it('computes campaignAttribution for resolved paid ads', () => {
    const opportunity = ref({
      id: 2,
      title: 'Ad Opportunity',
      campaign_platform: 'facebook',
      campaign_source_id: '999',
      campaign_name: 'Summer Sale',
      campaign_adset_name: 'AdSet 1',
      campaign_ad_name: 'Ad 1',
      campaign_resolution_status: 'resolved',
    });

    const { campaignAttribution } = useOpportunityCardFields(opportunity);

    expect(campaignAttribution.value.icon).toBe('i-lucide-facebook');
    expect(campaignAttribution.value.isResolved).toBe(true);
    expect(campaignAttribution.value.campaignName).toBe('Summer Sale');
    expect(campaignAttribution.value.adsetName).toBe('AdSet 1');
    expect(campaignAttribution.value.adName).toBe('Ad 1');
  });
});
