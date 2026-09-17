import { vi, describe, it, expect, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import ScoutOverview from './ScoutOverview.vue';
import ScoutAPI from 'dashboard/api/scout';
import scoutOverviewReportsAPI from 'dashboard/api/scoutOverviewReports';

vi.mock('dashboard/api/scout');
vi.mock('dashboard/api/scoutOverviewReports');
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));

describe('ScoutOverview', () => {
  const mockReport = {
    summary: {
      total_handled: 10,
      qualification_rate: 40.0,
      disqualification_rate: 30.0,
      abandonment_rate: 10.0,
      avg_messages_per_conversation: 5.2,
    },
    pipeline_stage_distribution: [
      { stage_id: 1, stage_name: 'Lead', stage_position: 0, count: 4 },
    ],
    interest_by_stage: {
      configured: false,
    },
  };

  const mockScouts = [
    { id: 101, name: 'Scout 1' },
    { id: 102, name: 'Scout 2' },
  ];

  const mountComponent = () =>
    mount(ScoutOverview, {
      global: {
        stubs: {
          Policy: true,
        },
      },
    });

  beforeEach(() => {
    vi.clearAllMocks();
    ScoutAPI.get.mockResolvedValue({ data: mockScouts });
    scoutOverviewReportsAPI.get.mockResolvedValue({ data: mockReport });
  });

  it('renders five summary cards, pipeline chart, and interest card on data fetch (U41)', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('10');
    expect(wrapper.text()).toContain('40%');
    expect(wrapper.text()).toContain('30%');
    expect(wrapper.text()).toContain('10%');
    expect(wrapper.text()).toContain('5.2');
    expect(
      wrapper.findComponent({ name: 'PipelineDistributionChart' }).exists()
    ).toBe(true);
    expect(
      wrapper.findComponent({ name: 'InterestByStageCard' }).exists()
    ).toBe(true);
  });

  it('renders EmptyStateLayout when total_handled is 0 (U42)', async () => {
    scoutOverviewReportsAPI.get.mockResolvedValue({
      data: {
        summary: {
          total_handled: 0,
          qualification_rate: null,
          disqualification_rate: null,
          abandonment_rate: null,
          avg_messages_per_conversation: null,
        },
        pipeline_stage_distribution: [],
        interest_by_stage: { configured: false },
      },
    });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.findComponent({ name: 'EmptyStateLayout' }).exists()).toBe(
      true
    );
  });

  it('re-fetches overview report when period changes (U43)', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(scoutOverviewReportsAPI.get).toHaveBeenCalledTimes(1);

    const rangeSelector = wrapper.findComponent({ name: 'RangeSelector' });
    rangeSelector.vm.$emit('update:modelValue', '30');
    await flushPromises();

    expect(scoutOverviewReportsAPI.get).toHaveBeenCalledTimes(2);
    expect(scoutOverviewReportsAPI.get).toHaveBeenLastCalledWith('1', {
      scoutId: 101,
      range: '30',
      timezoneOffset: '0',
    });
  });

  it('re-fetches overview report when scout selector changes (U44)', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(scoutOverviewReportsAPI.get).toHaveBeenCalledTimes(1);

    const scoutSelector = wrapper.findComponent({ name: 'ScoutSelector' });
    scoutSelector.vm.$emit('update:modelValue', 102);
    await flushPromises();

    expect(scoutOverviewReportsAPI.get).toHaveBeenCalledTimes(2);
    expect(scoutOverviewReportsAPI.get).toHaveBeenLastCalledWith('1', {
      scoutId: 102,
      range: '7',
      timezoneOffset: '0',
    });
  });

  it('embeds RecentConversationsSection with scoutId, range, and timezoneOffset props (U44, A1)', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    const section = wrapper.findComponent({
      name: 'RecentConversationsSection',
    });
    expect(section.exists()).toBe(true);
    expect(section.props('scoutId')).toBe(101);
    expect(section.props('range')).toBe('7');
    expect(section.props('timezoneOffset')).toBe(
      String(-(new Date().getTimezoneOffset() / 60))
    );
  });

  it('synchronizes recent conversations when period changes (U45, A4)', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    const rangeSelector = wrapper.findComponent({ name: 'RangeSelector' });
    rangeSelector.vm.$emit('update:modelValue', '30');
    await flushPromises();

    const section = wrapper.findComponent({
      name: 'RecentConversationsSection',
    });
    expect(section.props('range')).toBe('30');
  });

  it('synchronizes recent conversations when scout selector changes (U46, A4)', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    const scoutSelector = wrapper.findComponent({ name: 'ScoutSelector' });
    scoutSelector.vm.$emit('update:modelValue', 102);
    await flushPromises();

    const section = wrapper.findComponent({
      name: 'RecentConversationsSection',
    });
    expect(section.props('scoutId')).toBe(102);
  });
});
