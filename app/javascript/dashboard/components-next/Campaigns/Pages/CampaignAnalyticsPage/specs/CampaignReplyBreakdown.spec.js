import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CampaignReplyBreakdown from '../CampaignReplyBreakdown.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      CAMPAIGN: {
        WHATSAPP: {
          ANALYTICS: {
            REPLY_BREAKDOWN: {
              TITLE: 'Quick reply button performance',
              DESCRIPTION: 'Breakdown of button clicks and other replies.',
              BUTTON_LABEL: 'Button / Action',
              TOTAL_CLICKS: 'Clicks / Replies',
              CLICK_RATE: 'Click rate',
              OTHER_REPLIES: 'Other replies',
            },
          },
        },
      },
    },
  },
});

describe('CampaignReplyBreakdown.vue', () => {
  it('renders loading state when loading is true', () => {
    const wrapper = mount(CampaignReplyBreakdown, {
      props: {
        loading: true,
        breakdown: [],
      },
      global: {
        plugins: [i18n],
      },
    });

    expect(wrapper.findComponent({ name: 'Spinner' }).exists()).toBe(true);
  });

  it('renders table with button clicks and translates other label', () => {
    const breakdown = [
      { label: 'Schedule Now', total_clicks: 10, click_rate: 0.4 },
      { label: 'other', total_clicks: 5, click_rate: 0.2 },
    ];

    const wrapper = mount(CampaignReplyBreakdown, {
      props: {
        loading: false,
        breakdown,
      },
      global: {
        plugins: [i18n],
      },
    });

    const text = wrapper.text();
    expect(text).toContain('Quick reply button performance');
    expect(text).toContain('Schedule Now');
    expect(text).toContain('Other replies');
    expect(text).toContain('10');
    expect(text).toContain('40%');
    expect(text).toContain('5');
    expect(text).toContain('20%');
  });
});
