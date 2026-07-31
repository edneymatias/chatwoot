import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import Sidebar from '../Sidebar.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: { value: 1 },
    accountScopedRoute: vi.fn(route => route),
    isOnChatwootCloud: { value: false },
  }),
}));

vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({
    isEnterprise: false,
  }),
}));

vi.mock('dashboard/composables/utils/useKbd', () => ({
  useKbd: () => 'Ctrl+K',
}));

vi.mock(
  'dashboard/components-next/sidebar/useSidebarKeyboardShortcuts',
  () => ({
    useSidebarKeyboardShortcuts: vi.fn(),
  })
);

vi.mock('@vueuse/core', () => ({
  useWindowSize: () => ({ width: { value: 1024 } }),
  useEventListener: vi.fn(),
}));

describe('Sidebar.vue', () => {
  let store;
  let i18n;

  const createWrapper = (featureFlags = []) => {
    store = createStore({
      getters: {
        getCurrentAccountId: () => 1,
        getCurrentUserID: () => 1,
        'accounts/isFeatureEnabledonAccount': () => (accountId, flag) =>
          featureFlags.includes(flag),
        'globalConfig/isACustomBrandedInstance': () => false,
        'accounts/isRTL': () => false,
        getUISettings: () => ({}),
        'inboxes/getInboxes': () => [],
        'labels/getLabelsOnSidebar': () => [],
        'conversationUnreadCounts/getAllUnreadCount': () => 0,
        'conversationUnreadCounts/getInboxUnreadCount': () => () => 0,
        'conversationUnreadCounts/getLabelUnreadCount': () => () => 0,
        'conversationUnreadCounts/getTeamUnreadCount': () => () => 0,
        'conversationUnreadCounts/getMentionsUnreadCount': () => 0,
        'conversationUnreadCounts/getParticipatingUnreadCount': () => 0,
        'conversationUnreadCounts/getUnattendedUnreadCount': () => 0,
        'conversationUnreadCounts/getFolderUnreadCount': () => () => 0,
        'teams/getMyTeams': () => [],
        'customViews/getContactCustomViews': () => [],
        'customViews/getConversationCustomViews': () => [],
        'sidebarSortPreferences/getSectionSort': () => () => 'name',
      },
      actions: {
        'labels/get': vi.fn(),
        'inboxes/get': vi.fn(),
        'notifications/unReadCount': vi.fn(),
        'teams/get': vi.fn(),
        'attributes/get': vi.fn(),
        'customViews/get': vi.fn(),
        'conversationUnreadCounts/clear': vi.fn(),
        'conversationUnreadCounts/get': vi.fn(),
        'sidebarSortPreferences/initialize': vi.fn(),
      },
    });

    i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: {
        en: {
          SIDEBAR: {
            OPPORTUNITIES: 'Opportunities',
          },
        },
      },
      fallbackWarn: false,
      missingWarn: false,
    });

    return mount(Sidebar, {
      global: {
        plugins: [store, i18n],
        stubs: {
          RouterLink: { template: '<a><slot /></a>' },
          SidebarGroup: {
            template: '<div><slot /></div>',
            props: ['name', 'label'],
          },
          SidebarProfileMenu: true,
          SidebarChangelogCard: true,
          SidebarChangelogButton: true,
          SidebarAccountSwitcher: true,
          ComposeConversation: {
            template: '<div><slot name="trigger" /></div>',
          },
          Button: true,
          Logo: true,
        },
      },
    });
  };

  it('renders Kanban main-nav entry when feature flag is enabled', () => {
    const wrapper = createWrapper([FEATURE_FLAGS.OPPORTUNITIES]);
    const groups = wrapper.findAllComponents({ name: 'SidebarGroup' });
    const group = groups.find(c => c.props('name') === 'Opportunities');
    expect(group).toBeTruthy();
    expect(group.props('label')).toBe('Opportunities');
  });

  it('does not render Kanban main-nav entry when feature flag is disabled', () => {
    const wrapper = createWrapper([]);
    const group = wrapper
      .findAllComponents({ name: 'SidebarGroup' })
      .find(c => c.props('name') === 'Opportunities');
    expect(group).toBeFalsy();
  });
});
