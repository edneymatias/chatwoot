import { vi, describe, it, expect, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanCard from '../KanbanCard.vue';

const mockRouter = {
  push: vi.fn(),
};

vi.mock('vue-router', () => ({
  useRouter: () => mockRouter,
  useRoute: () => ({ name: 'opportunities_index', query: {}, params: {} }),
}));

vi.mock('dashboard/composables/useOpportunityCardFields', () => ({
  useOpportunityCardFields: () => ({
    statusBadgeClass: '',
    isStale: false,
    configuredFields: { value: [] },
    timestampLabel: '2 days ago',
    timestampTooltip: 'Created date',
    campaignAttribution: null,
  }),
}));

const createMockStore = () => {
  return createStore({
    modules: {
      opportunities: {
        namespaced: true,
      },
      pipelineStages: {
        namespaced: true,
        getters: {
          stageById: () => () => ({ id: 1, name: 'Lead' }),
        },
      },
    },
  });
};

describe('KanbanCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('navigates to opportunities_conversation with conversationId and opportunityId when active_conversation_id exists', async () => {
    const store = createMockStore();
    const opportunity = {
      id: 12,
      title: 'Deal with conversation',
      status: 'open',
      active_conversation_id: 1001,
      active_conversation_display_id: 55,
    };

    const wrapper = mount(KanbanCard, {
      props: {
        opportunity,
      },
      global: {
        plugins: [store],
        stubs: {
          Avatar: true,
          Button: true,
          StartOpportunityConversationButton: true,
          OpportunityAttributionPopover: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    await wrapper.trigger('click');

    expect(mockRouter.push).toHaveBeenCalledWith({
      name: 'opportunities_conversation',
      params: {
        conversationId: 55,
      },
      query: {
        opportunityId: 12,
      },
    });
  });

  it('navigates to opportunities_conversation without conversationId when active_conversation_id is absent', async () => {
    const store = createMockStore();
    const opportunity = {
      id: 13,
      title: 'Deal without conversation',
      status: 'open',
      active_conversation_id: null,
    };

    const wrapper = mount(KanbanCard, {
      props: {
        opportunity,
      },
      global: {
        plugins: [store],
        stubs: {
          Avatar: true,
          Button: true,
          StartOpportunityConversationButton: true,
          OpportunityAttributionPopover: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    // Card should not have grayscale or border-dashed
    expect(wrapper.classes()).toContain('cursor-pointer');
    expect(wrapper.classes()).not.toContain('grayscale');
    expect(wrapper.classes()).not.toContain('border-dashed');

    await wrapper.trigger('click');

    expect(mockRouter.push).toHaveBeenCalledWith({
      name: 'opportunities_conversation',
      params: {},
      query: {
        opportunityId: 13,
      },
    });
  });
});
