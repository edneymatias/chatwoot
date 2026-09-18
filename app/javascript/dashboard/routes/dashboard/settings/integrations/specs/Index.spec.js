import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import Index from '../Index.vue';
import enIntegrationApps from '../../../../../i18n/locale/en/integrationApps.json';
import ptIntegrationApps from '../../../../../i18n/locale/pt_BR/integrationApps.json';
import enIntegrations from '../../../../../i18n/locale/en/integrations.json';
import ptIntegrations from '../../../../../i18n/locale/pt_BR/integrations.json';

const mockAppIntegrations = ref([]);
const mockDispatch = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: mockDispatch,
  }),
  useStoreGetters: () => ({
    'integrations/getAppIntegrations': mockAppIntegrations,
    'integrations/getUIFlags': ref({ isFetching: false }),
  }),
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    replaceInstallationName: str => str,
  }),
}));

describe('Index.vue', () => {
  beforeEach(() => {
    mockAppIntegrations.value = [];
    vi.clearAllMocks();
  });

  const mountComponent = () => {
    return mount(Index, {
      global: {
        stubs: {
          SettingsLayout: {
            template: '<div><slot name="header" /><slot name="body" /></div>',
          },
          BaseSettingsHeader: true,
          IntegrationItem: {
            props: ['id', 'name', 'description', 'enabled', 'logo'],
            template:
              '<div class="integration-item" :data-id="id" :data-enabled="enabled">{{ name }}</div>',
          },
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });
  };

  describe('synthesized ERP card (U35, U36, U37, A1, A3, A4)', () => {
    it('renders without ERP card when category erp is absent (A1)', () => {
      mockAppIntegrations.value = [
        {
          id: 'slack',
          name: 'Slack',
          description: 'Slack app',
          enabled: true,
          category: 'communication',
        },
      ];

      const wrapper = mountComponent();
      const items = wrapper.findAll('.integration-item');

      expect(items.length).toBe(1);
      expect(items[0].attributes('data-id')).toBe('slack');
      expect(wrapper.find('[data-id="erp"]').exists()).toBe(false);
    });

    it('synthesizes unified ERP card when category erp is present and hides raw erp apps (U35 / A3)', () => {
      mockAppIntegrations.value = [
        {
          id: 'slack',
          name: 'Slack',
          category: 'communication',
          enabled: true,
        },
        {
          id: 'younus',
          name: 'Younus',
          category: 'erp',
          enabled: false,
          hooks: [],
        },
      ];

      const wrapper = mountComponent();
      const items = wrapper.findAll('.integration-item');

      // Should render Slack and ERP, NOT Younus directly
      expect(items.length).toBe(2);
      expect(wrapper.find('[data-id="younus"]').exists()).toBe(false);
      const erpCard = wrapper.find('[data-id="erp"]');
      expect(erpCard.exists()).toBe(true);
    });

    it('synthesized ERP card is enabled if any erp app has connected hooks (U36)', () => {
      mockAppIntegrations.value = [
        {
          id: 'younus',
          name: 'Younus',
          category: 'erp',
          enabled: true,
          hooks: [{ id: 1 }],
        },
      ];

      const wrapper = mountComponent();
      const erpCard = wrapper.find('[data-id="erp"]');

      expect(erpCard.attributes('data-enabled')).toBe('true');
    });

    it('synthesized ERP card is disabled if no erp app has hooks (U36)', () => {
      mockAppIntegrations.value = [
        {
          id: 'younus',
          name: 'Younus',
          category: 'erp',
          enabled: false,
          hooks: [],
        },
      ];

      const wrapper = mountComponent();
      const erpCard = wrapper.find('[data-id="erp"]');

      expect(erpCard.attributes('data-enabled')).toBe('false');
    });
  });

  describe('frontend translations (U43)', () => {
    it('defines ERP translations in en and pt_BR', () => {
      expect(enIntegrationApps.INTEGRATION_APPS.ERP.NAME).toBe('ERP');
      expect(enIntegrationApps.INTEGRATION_APPS.ERP.DESCRIPTION).toBeDefined();
      expect(ptIntegrationApps.INTEGRATION_APPS.ERP.NAME).toBe('ERP');
      expect(ptIntegrationApps.INTEGRATION_APPS.ERP.DESCRIPTION).toBeDefined();

      expect(enIntegrations.INTEGRATION_SETTINGS.ERP.HEADER).toBe(
        'ERP Integrations'
      );
      expect(ptIntegrations.INTEGRATION_SETTINGS.ERP.HEADER).toBe(
        'Integrações de ERP'
      );
    });
  });
});
