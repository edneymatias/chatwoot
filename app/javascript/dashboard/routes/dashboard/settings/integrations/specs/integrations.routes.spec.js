import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../SettingsWrapper.vue', () => ({
  default: { name: 'SettingsWrapper' },
}));
vi.mock('../Index.vue', () => ({ default: { name: 'Index' } }));
vi.mock('../IntegrationHooks.vue', () => ({
  default: { name: 'IntegrationHooks' },
}));
vi.mock('../Webhooks/Index.vue', () => ({ default: { name: 'Webhook' } }));
vi.mock('../DashboardApps/Index.vue', () => ({
  default: { name: 'DashboardApps' },
}));
vi.mock('../Slack.vue', () => ({ default: { name: 'Slack' } }));
vi.mock('../Linear.vue', () => ({ default: { name: 'Linear' } }));
vi.mock('../Notion.vue', () => ({ default: { name: 'Notion' } }));
vi.mock('../Shopify.vue', () => ({ default: { name: 'Shopify' } }));
vi.mock('../Erp/Index.vue', () => ({ default: { name: 'ErpIndex' } }));

vi.mock('../../../../../store', () => ({
  default: {
    getters: {
      'accounts/isFeatureEnabledonAccount': vi.fn(),
    },
  },
}));

import integrationsRoutes from '../integrations.routes';
import { FEATURE_FLAGS } from '../../../../../featureFlags';
import store from '../../../../../store';

describe('integrations.routes', () => {
  const getErpRoute = () => {
    const secondWrapper = integrationsRoutes.routes[1];
    return secondWrapper.children.find(r => r.path === 'erp');
  };

  describe('route configuration (U33)', () => {
    it('registers child route erp before :integration_id', () => {
      const secondWrapper = integrationsRoutes.routes[1];
      const erpIndex = secondWrapper.children.findIndex(r => r.path === 'erp');
      const catchAllIndex = secondWrapper.children.findIndex(
        r => r.path === ':integration_id'
      );

      expect(erpIndex).toBeGreaterThan(-1);
      expect(catchAllIndex).toBeGreaterThan(erpIndex);
    });

    it('registers erp route with correct name and admin permissions', () => {
      const erpRoute = getErpRoute();

      expect(erpRoute).toBeDefined();
      expect(erpRoute.name).toBe('settings_integrations_erp');
      expect(erpRoute.meta.permissions).toEqual(['administrator']);
      expect(erpRoute.meta.featureFlag).toBe(FEATURE_FLAGS.ERP_INTEGRATION);
      expect(FEATURE_FLAGS.ERP_INTEGRATION).toBe('erp_integration');
    });
  });

  describe('beforeEnter guard (U34 / A2)', () => {
    let next;
    let to;

    beforeEach(() => {
      next = vi.fn();
      to = { params: { accountId: '123' } };
      vi.clearAllMocks();
    });

    it('allows navigation when erp_integration is enabled on account', () => {
      store.getters['accounts/isFeatureEnabledonAccount'].mockReturnValue(true);
      const erpRoute = getErpRoute();

      erpRoute.beforeEnter(to, {}, next);

      expect(
        store.getters['accounts/isFeatureEnabledonAccount']
      ).toHaveBeenCalledWith('123', FEATURE_FLAGS.ERP_INTEGRATION);
      expect(next).toHaveBeenCalledWith();
    });

    it('redirects to dashboard (home) when erp_integration is disabled', () => {
      store.getters['accounts/isFeatureEnabledonAccount'].mockReturnValue(
        false
      );
      const erpRoute = getErpRoute();

      erpRoute.beforeEnter(to, {}, next);

      expect(
        store.getters['accounts/isFeatureEnabledonAccount']
      ).toHaveBeenCalledWith('123', FEATURE_FLAGS.ERP_INTEGRATION);
      expect(next).toHaveBeenCalledWith({
        name: 'home',
        params: { accountId: '123' },
      });
    });
  });
});
