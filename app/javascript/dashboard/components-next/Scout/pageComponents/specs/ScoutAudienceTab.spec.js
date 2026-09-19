import { ref, computed } from 'vue';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import ScoutAudienceTab from '../ScoutAudienceTab.vue';
import ScoutAPI from 'dashboard/api/scout';

vi.mock('dashboard/api/scout', () => ({
  default: {
    update: vi.fn(),
  },
}));

const mockFilterTypes = ref([
  {
    attributeKey: 'labels',
    inputType: 'multiSelect',
    options: [
      { id: 'vip', name: 'vip' },
      { id: 'lead', name: 'lead' },
    ],
  },
  {
    attributeKey: 'country_code',
    inputType: 'searchSelect',
    options: [
      { id: 'US', name: 'United States' },
      { id: 'BR', name: 'Brazil' },
    ],
  },
  {
    attributeKey: 'phone_number',
    inputType: 'plainText',
  },
  {
    attributeKey: 'email',
    inputType: 'plainText',
  },
]);

vi.mock('dashboard/components-next/filter/contactProvider.js', () => ({
  useContactFilterContext: () => ({
    filterTypes: computed(() => mockFilterTypes.value),
    attributeFilterTypes: computed(() => mockFilterTypes.value),
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

  it('hydrates audience conditions from backend with correct object values for multiSelect and searchSelect', () => {
    const scoutWithAudience = {
      ...defaultScout,
      audience: [
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: ['vip'],
          query_operator: 'and',
        },
        {
          attribute_key: 'country_code',
          filter_operator: 'equal_to',
          values: ['US'],
          query_operator: 'and',
        },
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

    expect(wrapper.vm.filters.length).toBe(3);
    expect(wrapper.vm.filters[0].values).toEqual([{ id: 'vip', name: 'vip' }]);
    expect(wrapper.vm.filters[1].values).toEqual({
      id: 'US',
      name: 'United States',
    });
    expect(wrapper.vm.filters[2].values).toBe('+5511999999999');
  });

  it('serializes multiSelect (labels) array of objects and searchSelect objects into array of IDs on saveAudience', async () => {
    ScoutAPI.update.mockResolvedValue({
      data: { ...defaultScout },
    });

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

    wrapper.vm.filters = [
      {
        id: 1,
        attributeKey: 'labels',
        filterOperator: 'equal_to',
        values: [
          { id: 'vip', name: 'vip' },
          { id: 'lead', name: 'lead' },
        ],
        queryOperator: 'and',
      },
      {
        id: 2,
        attributeKey: 'country_code',
        filterOperator: 'equal_to',
        values: { id: 'US', name: 'United States' },
        queryOperator: 'or',
      },
      {
        id: 3,
        attributeKey: 'phone_number',
        filterOperator: 'equal_to',
        values: '+5511999999999',
        queryOperator: 'and',
      },
    ];

    await wrapper.vm.saveAudience();
    expect(ScoutAPI.update).toHaveBeenCalledWith(1, {
      scout: {
        audience: [
          {
            attribute_key: 'labels',
            filter_operator: 'equal_to',
            query_operator: 'and',
            values: ['vip', 'lead'],
          },
          {
            attribute_key: 'country_code',
            filter_operator: 'equal_to',
            query_operator: 'or',
            values: ['US'],
          },
          {
            attribute_key: 'phone_number',
            filter_operator: 'equal_to',
            query_operator: 'and',
            values: ['+5511999999999'],
          },
        ],
      },
    });
  });
});
