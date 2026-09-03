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

  const createWrapper = (
    featureFlags = [],
    attributionSettings = { enabled: false, resolved_data_present: false }
  ) => {
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
        'campaignAttributionSettings/getSettings': () => attributionSettings,
      },
      actions: {
        'labels/get': vi.fn(),
        'inboxes/get': vi.fn(),
        'notifications/unReadCount': vi.fn(),
        'teams/get': vi.fn(),
        'attributes/get': vi.fn(),
        'customViews/get': vi.fn(),
        'campaignAttributionSettings/get': vi.fn(),
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
            REPORTS: 'Reports',
            REPORTS_CAMPAIGN_PERFORMANCE: 'Ad Campaigns',
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
          SidebarGroup: true,
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

  it('renders Campaign Performance report nav entry when opportunities feature is enabled and attribution has resolved data', () => {
    const wrapper = createWrapper([FEATURE_FLAGS.OPPORTUNITIES], {
      enabled: true,
      resolved_data_present: true,
    });
    const reportsGroup = wrapper
      .findAllComponents({ name: 'SidebarGroup' })
      .find(c => c.props('name') === 'Reports');
    expect(reportsGroup).toBeTruthy();
    const children = reportsGroup.props('children') || [];
    const campaignItem = children.find(
      c => c.name === 'Reports Campaign Performance'
    );
    expect(campaignItem).toBeTruthy();
  });

  it('does not render Campaign Performance report nav entry when resolved_data_present is false', () => {
    const wrapper = createWrapper([FEATURE_FLAGS.OPPORTUNITIES], {
      enabled: true,
      resolved_data_present: false,
    });
    const reportsGroup = wrapper
      .findAllComponents({ name: 'SidebarGroup' })
      .find(c => c.props('name') === 'Reports');
    const children = reportsGroup.props('children') || [];
    const campaignItem = children.find(
      c => c.name === 'Reports Campaign Performance'
    );
    expect(campaignItem).toBeFalsy();
  });
});
