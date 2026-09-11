import { describe, it, expect, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import ScoutFunnelTab from '../ScoutFunnelTab.vue';

vi.mock('dashboard/api/scout', () => ({
  default: {
    update: vi.fn(),
  },
}));

vi.mock('dashboard/api/attributes', () => ({
  default: {
    getAttributesByModel: vi.fn().mockResolvedValue({ data: [] }),
  },
}));

const mockStore = {
  getters: {
    'pipelineStages/stagesSortedByPosition': [],
    'teams/getTeams': [],
    'attributes/getAttributes': [],
    'attributes/getOpportunityAttributes': [],
    'attributes/getAttributesByModel': () => [],
  },
  dispatch: vi.fn().mockResolvedValue([]),
};

vi.mock('dashboard/composables/store', () => ({
  useStore: () => mockStore,
  useMapGetter: key => ({
    value: mockStore.getters[key] ?? [],
  }),
}));

describe('ScoutFunnelTab.vue', () => {
  const defaultScout = {
    id: 1,
    name: 'Sales Scout',
    default_pipeline_stage_id: 1,
    qualified_stage_id: 2,
    unqualified_stage_id: 3,
    interest_attribute_definition_id: null,
    interest_attribute_definition: null,
    value_by_interest: {},
  };

  const sampleAttributes = [
    {
      id: 1,
      attribute_display_name: 'Interesse',
      attribute_display_type: 'list',
      attribute_key: 'interesse',
      attribute_model: 'opportunity_attribute',
      attribute_values: ['Implantes', 'Próteses'],
    },
    {
      id: 2,
      attribute_display_name: 'Data do agendamento',
      attribute_display_type: 'date',
      attribute_key: 'data_do_agendamento',
      attribute_model: 'opportunity_attribute',
      attribute_values: [],
    },
    {
      id: 3,
      attribute_display_name: 'Urgência',
      attribute_display_type: 'list',
      attribute_key: 'urgencia',
      attribute_model: 'opportunity_attribute',
      attribute_values: ['Alta', 'Baixa'],
    },
  ];

  it('renders opportunity list attributes as selectable chips', () => {
    mockStore.getters['attributes/getAttributes'] = sampleAttributes;
    mockStore.getters['attributes/getOpportunityAttributes'] = [
      {
        id: 1,
        attributeDisplayName: 'Interesse',
        attributeDisplayType: 'list',
        attributeKey: 'interesse',
        attributeModel: 'opportunity_attribute',
        attributeValues: ['Implantes', 'Próteses'],
      },
      {
        id: 3,
        attributeDisplayName: 'Urgência',
        attributeDisplayType: 'list',
        attributeKey: 'urgencia',
        attributeModel: 'opportunity_attribute',
        attributeValues: ['Alta', 'Baixa'],
      },
    ];

    const wrapper = mount(ScoutFunnelTab, {
      props: {
        scout: defaultScout,
      },
      global: {
        mocks: {
          $t: msg => msg,
          $store: mockStore,
        },
        provide: {
          store: mockStore,
        },
      },
    });

    const buttons = wrapper.findAll('button').map(b => b.text());
    expect(buttons).toContain('Interesse');
    expect(buttons).toContain('Urgência');
  });

  it('renders opportunity list attributes from direct API fetch when store is empty', async () => {
    mockStore.getters['attributes/getAttributes'] = [];
    mockStore.getters['attributes/getOpportunityAttributes'] = [];

    const AttributeAPI = (await import('dashboard/api/attributes')).default;
    vi.mocked(AttributeAPI.getAttributesByModel).mockResolvedValueOnce({
      data: sampleAttributes,
    });

    const wrapper = mount(ScoutFunnelTab, {
      props: {
        scout: defaultScout,
      },
      global: {
        mocks: {
          $t: msg => msg,
          $store: mockStore,
        },
        provide: {
          store: mockStore,
        },
      },
    });

    await flushPromises();

    const buttons = wrapper.findAll('button').map(b => b.text());
    expect(buttons).toContain('Interesse');
    expect(buttons).toContain('Urgência');
  });

  it('renders interactive chips for list opportunity attributes and displays value table when selected', async () => {
    mockStore.getters['attributes/getAttributes'] = sampleAttributes;

    const wrapper = mount(ScoutFunnelTab, {
      props: {
        scout: defaultScout,
      },
      global: {
        mocks: {
          $t: msg => msg,
          $store: mockStore,
        },
        provide: {
          store: mockStore,
        },
      },
    });

    await flushPromises();

    const buttons = wrapper.findAll('button').map(b => b.text());
    expect(buttons).toContain('Interesse');
    expect(buttons).toContain('Urgência');
    expect(buttons).not.toContain('Data do agendamento');

    // Click on the 'Interesse' chip button (exact text, not '(Opportunity)' qualification button)
    const interesseChip = wrapper
      .findAll('button')
      .find(b => b.text().trim() === 'Interesse');
    await interesseChip.trigger('click');
    await flushPromises();

    // Verify the value estimation table for options appears
    expect(wrapper.text()).toContain('Implantes');
    expect(wrapper.text()).toContain('Próteses');
  });
});
