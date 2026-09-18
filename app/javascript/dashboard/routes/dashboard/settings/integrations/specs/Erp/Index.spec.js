import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import ErpIndex from '../../Erp/Index.vue';

const mockAppIntegrations = ref([
  {
    id: 'younus',
    name: 'Younus',
    description:
      'Connect Younus ERP to view customer and financial information.',
    enabled: false,
    logo: 'younus.png',
    category: 'erp',
  },
  {
    id: 'slack',
    name: 'Slack',
    description: 'Slack integration',
    enabled: true,
    logo: 'slack.png',
    category: 'communication',
  },
]);

const mockDispatch = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: mockDispatch,
  }),
  useStoreGetters: () => ({
    'integrations/getAppIntegrations': mockAppIntegrations,
    'integrations/getUIFlags': ref({ isFetching: false }),
    getCurrentAccountId: ref(1),
  }),
}));

describe('Erp/Index.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders only ERP category integrations (U38 / A5)', () => {
    const wrapper = mount(ErpIndex, {
      global: {
        stubs: {
          SettingsLayout: {
            template: '<div><slot name="header" /><slot name="body" /></div>',
          },
          BaseSettingsHeader: true,
          IntegrationItem: {
            props: ['id', 'name', 'description', 'enabled', 'logo'],
            template:
              '<div class="integration-item" :data-id="id">{{ name }}</div>',
          },
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    const items = wrapper.findAll('.integration-item');
    expect(items.length).toBe(1);
    expect(items[0].attributes('data-id')).toBe('younus');
    expect(items[0].text()).toContain('Younus');
  });

  it('renders BaseSettingsHeader with back button and erp title (U39)', () => {
    const wrapper = mount(ErpIndex, {
      global: {
        stubs: {
          SettingsLayout: {
            template: '<div><slot name="header" /><slot name="body" /></div>',
          },
          BaseSettingsHeader: {
            props: ['title', 'backButtonLabel', 'featureName'],
            template:
              '<div class="header" :data-title="title" :data-back="backButtonLabel" />',
          },
          IntegrationItem: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    const header = wrapper.find('.header');
    expect(header.exists()).toBe(true);
    expect(header.attributes('data-title')).toBe(
      'INTEGRATION_SETTINGS.ERP.HEADER'
    );
    expect(header.attributes('data-back')).toBe('INTEGRATION_SETTINGS.HEADER');
  });

  it('dispatches integrations/get on mounted', () => {
    mount(ErpIndex, {
      global: {
        stubs: {
          SettingsLayout: true,
          BaseSettingsHeader: true,
          IntegrationItem: true,
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });

    expect(mockDispatch).toHaveBeenCalledWith('integrations/get');
  });
});
