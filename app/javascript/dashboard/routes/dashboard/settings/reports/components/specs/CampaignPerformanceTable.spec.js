import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import CampaignPerformanceTable from '../CampaignPerformanceTable.vue';

describe('CampaignPerformanceTable.vue', () => {
  const mockReportDataWithMilestone = {
    summary: {
      leads: 10,
      milestone_stage_name: 'Agendado',
      milestone_count: 4,
      milestone_rate_pct: 40.0,
    },
    by_campaign: [
      {
        campaign_name: 'Summer Sale',
        leads: 7,
        won_count: 2,
        lost_count: 1,
        milestone_count: 3,
        milestone_rate_pct: 42.9,
      },
      {
        campaign_name: 'Não identificado',
        leads: 3,
        won_count: 0,
        lost_count: 1,
        milestone_count: 1,
        milestone_rate_pct: 33.3,
      },
    ],
    by_adset: [
      {
        campaign_name: 'Summer Sale',
        campaign_adset_name: 'Set 1',
        leads: 5,
        won_count: 2,
        lost_count: 0,
        milestone_count: 2,
        milestone_rate_pct: 40.0,
      },
    ],
    by_ad: [
      {
        campaign_name: 'Summer Sale',
        campaign_adset_name: 'Set 1',
        campaign_ad_name: 'Creative A',
        leads: 3,
        won_count: 1,
        lost_count: 0,
        milestone_count: 1,
        milestone_rate_pct: 33.3,
      },
    ],
  };

  const createWrapper = (reportData = mockReportDataWithMilestone) => {
    return mount(CampaignPerformanceTable, {
      props: { reportData },
      global: {
        mocks: {
          $t: key => key,
        },
      },
    });
  };

  it('renders 3 tabs and defaults to ads view', () => {
    const wrapper = createWrapper();
    const tabButtons = wrapper.findAll('button');
    expect(tabButtons.length).toBe(3);
    expect(wrapper.text()).toContain('Creative A');
    expect(wrapper.text()).toContain('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.AD');
  });

  it('switches to adsets tab and displays adset columns and rows', async () => {
    const wrapper = createWrapper();
    const tabButtons = wrapper.findAll('button');
    await tabButtons[1].trigger('click'); // 'adsets'

    expect(wrapper.text()).toContain('Set 1');
    expect(wrapper.text()).toContain(
      'CAMPAIGN_PERFORMANCE_REPORTS.TABLE.ADSET'
    );
    expect(wrapper.text()).not.toContain('Creative A');
  });

  it('switches to campaigns tab and displays campaign columns and rows', async () => {
    const wrapper = createWrapper();
    const tabButtons = wrapper.findAll('button');
    await tabButtons[2].trigger('click'); // 'campaigns'

    expect(wrapper.text()).toContain('Summer Sale');
    expect(wrapper.text()).toContain('Não identificado');
    expect(wrapper.text()).not.toContain('Creative A');
  });

  it('renders milestone column when milestone stage exists in report data', () => {
    const wrapper = createWrapper();
    expect(wrapper.text()).toContain('Agendado');
    expect(wrapper.text()).toContain('1 (33.3%)');
  });

  it('omits milestone column when no milestone stage is configured', () => {
    const noMilestoneData = {
      summary: {
        leads: 5,
      },
      by_ad: [
        {
          campaign_name: 'Promo',
          campaign_adset_name: 'Set A',
          campaign_ad_name: 'Creative 1',
          leads: 5,
          won_count: 1,
          lost_count: 0,
        },
      ],
    };

    const wrapper = createWrapper(noMilestoneData);
    expect(wrapper.text()).not.toContain('Agendado');
    expect(wrapper.text()).not.toContain(
      'CAMPAIGN_PERFORMANCE_REPORTS.TABLE.MILESTONE_RATE'
    );
  });

  it('shows empty state when no data for tab', () => {
    const emptyData = {
      summary: { leads: 0 },
      by_ad: [],
    };
    const wrapper = createWrapper(emptyData);
    expect(wrapper.text()).toContain(
      'CAMPAIGN_PERFORMANCE_REPORTS.TABLE.EMPTY'
    );
  });
});
