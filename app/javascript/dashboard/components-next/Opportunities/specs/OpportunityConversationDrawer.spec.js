import { vi, describe, it, expect, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { ref, reactive } from 'vue';
import OpportunityConversationDrawer from '../OpportunityConversationDrawer.vue';
import { createStore } from 'vuex';

const mockRoute = reactive({
  name: 'opportunities_conversation',
  params: {},
  query: { opportunityId: '42' },
});

const mockRouter = {
  push: vi.fn(),
};

vi.mock(import('vue-router'), async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    useRoute: () => mockRoute,
    useRouter: () => mockRouter,
  };
});

vi.mock('dashboard/composables/useConversationDrawer', () => ({
  useConversationDrawer: () => ({
    loading: ref(false),
    ready: ref(true),
    error: ref(false),
    processConversation: vi.fn(),
  }),
}));

vi.mock('../../composables/useConversationDrawer', () => ({
  useConversationDrawer: () => ({
    loading: ref(false),
    ready: ref(true),
    error: ref(false),
    processConversation: vi.fn(),
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: () => true,
  }),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: ref({ is_contact_sidebar_open: false }),
  }),
}));

const createMockStore = (opportunity = { id: 42, title: 'Deal 42' }) => {
  return createStore({
    modules: {
      opportunities: {
        namespaced: true,
        getters: {
          cardById: () => id => (id === 42 ? opportunity : null),
          opportunityByConversationId: () => () => opportunity,
        },
        actions: {
          fetchForContact: vi.fn(),
        },
      },
    },
    getters: {
      getSelectedChat: () => ({ id: 101, inbox_id: 1, display_id: 101 }),
      getConversationById: () => () => ({
        id: 101,
        inbox_id: 1,
        display_id: 101,
      }),
      getCurrentAccountId: () => 1,
    },
  });
};

describe('OpportunityConversationDrawer', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.params = {};
    mockRoute.query = { opportunityId: '42' };
  });

  it('defaults activeTab to activity when route.params.conversationId is absent', () => {
    const store = createMockStore();
    const wrapper = mount(OpportunityConversationDrawer, {
      global: {
        plugins: [store],
        stubs: {
          ConversationBox: true,
          ConversationSidebar: true,
          SidepanelSwitch: true,
          Button: true,
          ButtonGroup: true,
          OpportunityActivityLog: true,
          Spinner: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    expect(
      wrapper.findComponent({ name: 'OpportunityActivityLog' }).exists()
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'ConversationBox' }).exists()).toBe(
      false
    );
  });

  it('defaults activeTab to conversation when route.params.conversationId is present', () => {
    mockRoute.params = { conversationId: '101' };
    const store = createMockStore();
    const wrapper = mount(OpportunityConversationDrawer, {
      global: {
        plugins: [store],
        stubs: {
          ConversationBox: true,
          ConversationSidebar: true,
          SidepanelSwitch: true,
          Button: true,
          ButtonGroup: true,
          OpportunityActivityLog: true,
          Spinner: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    expect(wrapper.findComponent({ name: 'ConversationBox' }).exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'OpportunityActivityLog' }).exists()
    ).toBe(false);
  });

  it('switches activeTab to conversation when route.params.conversationId transitions from absent to present', async () => {
    mockRoute.params = {};
    const store = createMockStore();
    const wrapper = mount(OpportunityConversationDrawer, {
      global: {
        plugins: [store],
        stubs: {
          ConversationBox: true,
          ConversationSidebar: true,
          SidepanelSwitch: true,
          Button: true,
          ButtonGroup: true,
          OpportunityActivityLog: true,
          Spinner: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    expect(
      wrapper.findComponent({ name: 'OpportunityActivityLog' }).exists()
    ).toBe(true);

    mockRoute.params = { conversationId: '202' };
    await wrapper.vm.$nextTick();

    expect(wrapper.findComponent({ name: 'ConversationBox' }).exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'OpportunityActivityLog' }).exists()
    ).toBe(false);
  });

  it('switches activeTab to conversation when OpportunityActivityLog emits select-conversation', async () => {
    mockRoute.params = { conversationId: '101' };
    const store = createMockStore();
    const wrapper = mount(OpportunityConversationDrawer, {
      global: {
        plugins: [store],
        stubs: {
          ConversationBox: true,
          ConversationSidebar: true,
          SidepanelSwitch: true,
          Button: true,
          ButtonGroup: true,
          OpportunityActivityLog: {
            name: 'OpportunityActivityLog',
            template: '<div class="activity-log-stub" />',
            emits: ['selectConversation'],
          },
          Spinner: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    // Initially on conversation tab, switch to activity tab manually
    wrapper.vm.activeTab = 'activity';
    await wrapper.vm.$nextTick();

    expect(
      wrapper.findComponent({ name: 'OpportunityActivityLog' }).exists()
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'ConversationBox' }).exists()).toBe(
      false
    );

    // Emit selectConversation (even with the same conversationId)
    wrapper
      .findComponent({ name: 'OpportunityActivityLog' })
      .vm.$emit('selectConversation', 101);
    await wrapper.vm.$nextTick();

    expect(wrapper.findComponent({ name: 'ConversationBox' }).exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'OpportunityActivityLog' }).exists()
    ).toBe(false);
  });
});
