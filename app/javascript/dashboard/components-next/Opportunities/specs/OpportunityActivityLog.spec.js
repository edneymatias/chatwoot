import { vi, describe, it, expect, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import OpportunityActivityLog from '../OpportunityActivityLog.vue';

const mockRouter = {
  push: vi.fn(),
};

const mockRoute = {
  query: { opportunityId: '42' },
};

vi.mock('vue-router', () => ({
  useRouter: () => mockRouter,
  useRoute: () => mockRoute,
}));

vi.mock('shared/helpers/timeHelper', () => ({
  messageTimestamp: () => 'Aug 30, 2026 12:00 PM',
  dynamicTime: () => '2 hours ago',
  shortTimestamp: str => str,
}));

const createMockStore = activities => {
  return createStore({
    modules: {
      opportunities: {
        namespaced: true,
        actions: {
          fetchActivities: vi.fn().mockResolvedValue(activities),
        },
      },
      pipelineStages: {
        namespaced: true,
        getters: {
          stageById: () => () => null,
        },
      },
    },
  });
};

describe('OpportunityActivityLog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders conversation event as a clickable button with status badge when conversation_viewable is true', async () => {
    const activities = [
      {
        id: 1,
        event_type: 'conversation_opened',
        occurred_at: 1000000,
        actor: { id: 1, name: 'Alice', type: 'user' },
        metadata: {
          conversation_id: 101,
          conversation_display_id: 101,
          is_origin: true,
        },
        conversation_status: 'open',
        conversation_viewable: true,
      },
    ];

    const store = createMockStore(activities);
    const wrapper = mount(OpportunityActivityLog, {
      props: {
        opportunityId: 42,
      },
      global: {
        plugins: [store],
        stubs: {
          Spinner: true,
          BaseTable: {
            template: '<div><slot name="row" :items="$attrs.items" /></div>',
          },
          BaseTableRow: {
            template: '<div><slot /></div>',
          },
          BaseTableCell: {
            template: '<div><slot /></div>',
          },
          PaginationFooter: true,
        },
        mocks: {
          $t: (msg, params) => {
            if (typeof params === 'object') {
              let result = msg;
              Object.entries(params).forEach(([k, v]) => {
                result = result.replace(`{${k}}`, v);
              });
              return result;
            }
            return msg;
          },
        },
        directives: {
          tooltip: () => {},
        },
      },
    });

    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    const linkButton = wrapper.find('button.text-n-brand');
    expect(linkButton.exists()).toBe(true);

    await linkButton.trigger('click');

    expect(wrapper.emitted('selectConversation')).toBeTruthy();
    expect(wrapper.emitted('selectConversation')[0]).toEqual([101]);

    expect(mockRouter.push).toHaveBeenCalledWith({
      name: 'opportunities_conversation',
      params: { conversationId: 101 },
      query: { opportunityId: '42' },
    });
  });

  it('renders conversation event as plain text without button or status badge when conversation_viewable is false', async () => {
    const activities = [
      {
        id: 2,
        event_type: 'conversation_opened',
        occurred_at: 1000000,
        actor: { id: 1, name: 'Alice', type: 'user' },
        metadata: {
          conversation_id: 102,
          conversation_display_id: 102,
          is_origin: true,
        },
        conversation_status: null,
        conversation_viewable: false,
      },
    ];

    const store = createMockStore(activities);
    const wrapper = mount(OpportunityActivityLog, {
      props: {
        opportunityId: 42,
      },
      global: {
        plugins: [store],
        stubs: {
          Spinner: true,
          BaseTable: {
            template: '<div><slot name="row" :items="$attrs.items" /></div>',
          },
          BaseTableRow: {
            template: '<div><slot /></div>',
          },
          BaseTableCell: {
            template: '<div><slot /></div>',
          },
          PaginationFooter: true,
        },
        mocks: {
          $t: (msg, params) => {
            if (typeof params === 'object') {
              let result = msg;
              Object.entries(params).forEach(([k, v]) => {
                result = result.replace(`{${k}}`, v);
              });
              return result;
            }
            return msg;
          },
        },
        directives: {
          tooltip: () => {},
        },
      },
    });

    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(wrapper.find('button.text-n-brand').exists()).toBe(false);
  });
});
