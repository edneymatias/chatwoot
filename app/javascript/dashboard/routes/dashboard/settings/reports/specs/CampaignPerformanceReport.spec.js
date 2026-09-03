import { describe, it, expect, vi, beforeEach } from 'vitest';
import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import CampaignPerformanceReport from '../CampaignPerformanceReport.vue';

vi.mock('dashboard/composables/store');

describe('CampaignPerformanceReport.vue', () => {
  let dispatchMock;

  const createWrapper = ({
    uiFlags = { fetchingItems: false },
    data = {},
  } = {}) => {
    dispatchMock = vi.fn();
    useStore.mockReturnValue({ dispatch: dispatchMock });
    useMapGetter.mockImplementation(getter => {
      if (getter === 'campaignPerformanceReports/getUIFlags') {
        return ref(uiFlags);
      }
      if (getter === 'campaignPerformanceReports/getData') {
        return ref(data);
      }
      return ref({});
    });

    return shallowMount(CampaignPerformanceReport, {
      global: {
        mocks: {
          $t: key => key,
        },
        stubs: {
          ReportHeader: true,
          ReportFilters: true,
          ReportMetricCard: true,
          CampaignPerformanceTable: true,
        },
      },
    });
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('dispatches campaignPerformanceReports/get on mount', () => {
    createWrapper();
    expect(dispatchMock).toHaveBeenCalledWith(
      'campaignPerformanceReports/get',
      expect.objectContaining({
        since: expect.any(Number),
        until: expect.any(Number),
      })
    );
  });

  it('renders loading indicator when fetchingItems is true', () => {
    const wrapper = createWrapper({ uiFlags: { fetchingItems: true } });
    expect(wrapper.text()).toContain('CAMPAIGN_PERFORMANCE_REPORTS.LOADING');
  });

  it('renders metric cards with zero values and breakdown table when leads is 0', () => {
    const wrapper = createWrapper({
      data: { summary: { leads: 0 } },
    });
    const metricCards = wrapper.findAllComponents({ name: 'ReportMetricCard' });
    expect(metricCards.length).toBe(6);
    expect(
      wrapper.findComponent({ name: 'CampaignPerformanceTable' }).exists()
    ).toBe(true);
  });

  it('renders metric cards and table when report data is present', () => {
    const wrapper = createWrapper({
      data: {
        summary: {
          leads: 10,
          milestone_stage_name: 'Agendado',
          milestone_count: 3,
          milestone_rate_pct: 30.0,
          won_count: 2,
          won_rate_pct: 20.0,
          lost_count: 1,
          lost_rate_pct: 10.0,
          distinct_campaigns: 2,
          distinct_adsets: 4,
          distinct_ads: 6,
        },
        by_campaign: [{ campaign_name: 'Promo A', leads: 10 }],
      },
    });

    const metricCards = wrapper.findAllComponents({ name: 'ReportMetricCard' });
    expect(metricCards.length).toBe(7); // Leads, Milestone, Won, Lost, Campaigns, Adsets, Ads
    expect(
      wrapper.findComponent({ name: 'CampaignPerformanceTable' }).exists()
    ).toBe(true);
  });

  it('omits milestone card when no milestone stage is configured', () => {
    const wrapper = createWrapper({
      data: {
        summary: {
          leads: 5,
          won_count: 1,
          won_rate_pct: 20.0,
          lost_count: 0,
          lost_rate_pct: 0.0,
          distinct_campaigns: 1,
          distinct_adsets: 1,
          distinct_ads: 1,
        },
      },
    });

    const metricCards = wrapper.findAllComponents({ name: 'ReportMetricCard' });
    expect(metricCards.length).toBe(6);
  });
});
