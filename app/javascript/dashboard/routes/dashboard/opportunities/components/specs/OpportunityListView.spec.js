import { ref } from 'vue';
import { vi, describe, it, expect, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import OpportunityListView from '../OpportunityListView.vue';
import CardLayout from 'dashboard/components-next/CardLayout.vue';

vi.mock('dashboard/composables/useOpportunityCardFields', () => ({
  useOpportunityCardFields: () => ({
    statusBadgeClass: '',
    isStale: false,
    timestampLabel: '1 day ago',
    campaignAttribution: ref(null),
  }),
}));

const createMockStore = (cards = []) => {
  return createStore({
    modules: {
      opportunities: {
        namespaced: true,
        state: {
          pagination: {
            all: { totalCount: cards.length, page: 1 },
          },
        },
        getters: {
          allCards: () => cards,
          isFetching: () => false,
        },
        actions: {
          fetchAll: vi.fn(),
        },
      },
      pipelineStages: {
        namespaced: true,
        getters: {
          stageById: () => () => ({ id: 1, name: 'Lead' }),
        },
      },
      pipelineCurrencySetting: {
        namespaced: true,
        getters: {
          getCurrency: () => 'USD',
        },
      },
    },
  });
};

describe('OpportunityListView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders all rows with interactive pointer styling and emits rowClick on click regardless of active_conversation_id', async () => {
    const cards = [
      { id: 1, title: 'Opp With Conv', active_conversation_id: 10, value: 100 },
      {
        id: 2,
        title: 'Opp Without Conv',
        active_conversation_id: null,
        value: 200,
      },
    ];

    const store = createMockStore(cards);
    const wrapper = mount(OpportunityListView, {
      props: {
        filters: {},
      },
      global: {
        plugins: [store],
        stubs: {
          StartOpportunityConversationButton: true,
          Avatar: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    const cardLayouts = wrapper.findAllComponents(CardLayout);
    expect(cardLayouts).toHaveLength(2);

    expect(cardLayouts[0].classes()).toContain('cursor-pointer');
    expect(cardLayouts[1].classes()).toContain('cursor-pointer');
    expect(cardLayouts[1].classes()).not.toContain('grayscale');
    expect(cardLayouts[1].classes()).not.toContain('border-dashed');

    // Click first row (with active conversation)
    await cardLayouts[0].vm.$emit('click');
    expect(wrapper.emitted('rowClick')).toBeTruthy();
    expect(wrapper.emitted('rowClick')[0]).toEqual([cards[0]]);

    // Click second row (without active conversation)
    await cardLayouts[1].vm.$emit('click');
    expect(wrapper.emitted('rowClick')[1]).toEqual([cards[1]]);
  });
});
