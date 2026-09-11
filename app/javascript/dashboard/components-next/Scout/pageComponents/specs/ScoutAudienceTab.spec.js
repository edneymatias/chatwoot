import { computed } from 'vue';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import ScoutAudienceTab from '../ScoutAudienceTab.vue';
import ScoutAPI from 'dashboard/api/scout';

vi.mock('dashboard/api/scout', () => ({
  default: {
    update: vi.fn(),
  },
}));

vi.mock('dashboard/components-next/filter/contactProvider.js', () => ({
  useContactFilterContext: () => ({
    filterTypes: computed(() => []),
    attributeFilterTypes: computed(() => []),
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: () => ({
    showAlert: vi.fn(),
  }),
}));

describe('ScoutAudienceTab.vue', () => {
  const defaultScout = {
    id: 1,
    name: 'Sales Scout',
    enabled: true,
    audience: [],
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders the empty state when audience is empty', () => {
    const wrapper = mount(ScoutAudienceTab, {
      props: {
        scout: defaultScout,
      },
      global: {
        mocks: {
          $t: msg => msg,
        },
        stubs: {
          Button: true,
          ConditionRow: true,
        },
      },
    });

    expect(wrapper.text()).toContain('SCOUT.AUDIENCE.EMPTY_STATE.TITLE');
  });

  it('renders condition rows when audience has items', () => {
    const scoutWithAudience = {
      ...defaultScout,
      audience: [
        {
          attribute_key: 'phone_number',
          filter_operator: 'equal_to',
          values: ['+5511999999999'],
          query_operator: 'and',
        },
      ],
    };

    const wrapper = mount(ScoutAudienceTab, {
      props: {
        scout: scoutWithAudience,
      },
      global: {
        mocks: {
          $t: msg => msg,
        },
        stubs: {
          Button: true,
          ConditionRow: true,
        },
      },
    });

    expect(wrapper.text()).not.toContain('SCOUT.AUDIENCE.EMPTY_STATE.TITLE');
    expect(
      wrapper.findAllComponents({ name: 'ConditionRow' }).length
    ).toBeGreaterThanOrEqual(1);
  });

  it('calls ScoutAPI.update with empty audience when clear audience is triggered', async () => {
    ScoutAPI.update.mockResolvedValue({
      data: { ...defaultScout, audience: [] },
    });

    const scoutWithAudience = {
      ...defaultScout,
      audience: [
        {
          attribute_key: 'phone_number',
          filter_operator: 'equal_to',
          values: ['+5511999999999'],
          query_operator: 'and',
        },
      ],
    };

    const wrapper = mount(ScoutAudienceTab, {
      props: {
        scout: scoutWithAudience,
      },
      global: {
        mocks: {
          $t: msg => msg,
        },
        stubs: {
          Button: false,
          ConditionRow: true,
        },
      },
    });

    await wrapper.vm.clearAudience();
    expect(ScoutAPI.update).toHaveBeenCalledWith(1, {
      scout: {
        audience: [],
      },
    });
  });

  it('grows filters when addCondition is called', () => {
    const wrapper = mount(ScoutAudienceTab, {
      props: {
        scout: defaultScout,
      },
      global: {
        mocks: {
          $t: msg => msg,
        },
        stubs: {
          Button: true,
          ConditionRow: true,
        },
      },
    });

    expect(wrapper.vm.filters.length).toBe(0);
    wrapper.vm.addCondition();
    expect(wrapper.vm.filters.length).toBe(1);
    expect(wrapper.vm.filters[0].attributeKey).toBe('phone_number');
    expect(wrapper.vm.filters[0].filterOperator).toBe('equal_to');
  });

  it('shrinks filters when removeCondition is called', () => {
    const scoutWithAudience = {
      ...defaultScout,
      audience: [
        {
          attribute_key: 'phone_number',
          filter_operator: 'equal_to',
          values: ['+5511999999999'],
          query_operator: 'and',
        },
        {
          attribute_key: 'email',
          filter_operator: 'contains',
          values: ['@test.com'],
          query_operator: 'or',
        },
      ],
    };

    const wrapper = mount(ScoutAudienceTab, {
      props: {
        scout: scoutWithAudience,
      },
      global: {
        mocks: {
          $t: msg => msg,
        },
        stubs: {
          Button: true,
          ConditionRow: true,
        },
      },
    });

    expect(wrapper.vm.filters.length).toBe(2);
    wrapper.vm.removeCondition(0);
    expect(wrapper.vm.filters.length).toBe(1);
    expect(wrapper.vm.filters[0].attributeKey).toBe('email');
  });

  it('calls ScoutAPI.update with correctly-shaped audience payload when saveAudience is called', async () => {
    ScoutAPI.update.mockResolvedValue({
      data: { ...defaultScout },
    });

    const scoutWithAudience = {
      ...defaultScout,
      audience: [
        {
          attribute_key: 'phone_number',
          filter_operator: 'equal_to',
          values: ['+5511999999999'],
          query_operator: 'and',
        },
        {
          attribute_key: 'labels',
          filter_operator: 'contains',
          values: ['vip'],
          query_operator: 'or',
        },
      ],
    };

    const wrapper = mount(ScoutAudienceTab, {
      props: {
        scout: scoutWithAudience,
      },
      global: {
        mocks: {
          $t: msg => msg,
        },
        stubs: {
          Button: true,
          ConditionRow: true,
        },
      },
    });

    await wrapper.vm.saveAudience();
    expect(ScoutAPI.update).toHaveBeenCalledWith(1, {
      scout: {
        audience: [
          {
            attribute_key: 'phone_number',
            filter_operator: 'equal_to',
            query_operator: 'and',
            values: ['+5511999999999'],
          },
          {
            attribute_key: 'labels',
            filter_operator: 'contains',
            query_operator: 'or',
            values: ['vip'],
          },
        ],
      },
    });
  });
});
