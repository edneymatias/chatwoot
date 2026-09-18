import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SingleIntegrationHooks from '../SingleIntegrationHooks.vue';

const mockIntegration = ref({
  id: 'younus',
  name: 'Younus',
  description: 'Connect Younus ERP...',
  hooks: [
    {
      id: 1,
      settings: {
        id_empresa: '42',
        token: '••••••••',
      },
    },
  ],
});

const mockHasConnectedHooks = ref(true);

vi.mock('dashboard/composables/useIntegrationHook', () => ({
  useIntegrationHook: () => ({
    integration: mockIntegration,
    hasConnectedHooks: mockHasConnectedHooks,
  }),
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    replaceInstallationName: str => str,
  }),
}));

describe('SingleIntegrationHooks.vue for ERP (U40, A10)', () => {
  beforeEach(() => {
    mockHasConnectedHooks.value = true;
    vi.clearAllMocks();
  });

  const mountComponent = () => {
    return mount(SingleIntegrationHooks, {
      props: {
        integrationId: 'younus',
      },
      global: {
        stubs: {
          Button: {
            props: ['label'],
            template: '<button class="button-stub">{{ label }}</button>',
          },
        },
        mocks: {
          $t: msg => msg,
        },
      },
    });
  };

  it('renders cleartext company id and masked token when connected (U40, A10)', () => {
    const wrapper = mountComponent();

    const companyIdRow = wrapper.find('[data-property="id_empresa"]');
    const tokenRow = wrapper.find('[data-property="token"]');

    expect(companyIdRow.exists()).toBe(true);
    expect(companyIdRow.text()).toContain('Company ID:');
    expect(companyIdRow.text()).toContain('42');

    expect(tokenRow.exists()).toBe(true);
    expect(tokenRow.text()).toContain('API Token:');
    expect(tokenRow.text()).toContain('••••••••');
  });

  it('does not render configuration details when not connected', () => {
    mockHasConnectedHooks.value = false;
    const wrapper = mountComponent();

    expect(wrapper.find('[data-property="id_empresa"]').exists()).toBe(false);
    expect(wrapper.find('[data-property="token"]').exists()).toBe(false);
  });
});
