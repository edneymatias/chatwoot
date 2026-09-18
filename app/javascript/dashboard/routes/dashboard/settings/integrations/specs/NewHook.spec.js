import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { plugin as formKitPlugin, defaultConfig } from '@formkit/vue';
import NewHook from '../NewHook.vue';

const { mockYounusIntegration } = vi.hoisted(() => ({
  mockYounusIntegration: {
    id: 'younus',
    name: 'Younus',
    short_description: 'Connect Younus ERP...',
    category: 'erp',
    hook_type: 'account',
    allow_multiple_hooks: false,
    settings_form_schema: [
      {
        label: 'API Token',
        type: 'text',
        name: 'token',
        validation: 'required',
      },
      {
        label: 'Company ID',
        type: 'text',
        name: 'id_empresa',
        validation: 'required',
      },
    ],
    hooks: [],
  },
}));

const mockDispatch = vi.fn();

vi.mock('dashboard/composables/useIntegrationHook', async () => {
  const { ref: vueRef } = await vi.importActual('vue');
  return {
    useIntegrationHook: () => ({
      integration: vueRef(mockYounusIntegration),
      isHookTypeInbox: vueRef(false),
      hasConnectedHooks: vueRef(false),
    }),
  };
});

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    replaceInstallationName: str => str,
  }),
}));

describe('NewHook.vue for Younus (A6, A7)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  const mountComponent = () => {
    return mount(NewHook, {
      props: {
        integrationId: 'younus',
      },
      global: {
        plugins: [[formKitPlugin, defaultConfig]],
        stubs: {
          WootModalHeader: true,
          NextButton: {
            props: ['label', 'type', 'isLoading'],
            template: '<button :type="type">{{ label }}</button>',
          },
        },
        mocks: {
          $t: msg => msg,
          $store: {
            dispatch: mockDispatch,
            getters: {
              'integrations/getUIFlags': { isCreatingHook: false },
              'inboxes/dialogFlowEnabledInboxes': [],
            },
          },
        },
      },
    });
  };

  it('renders required input fields for API Token and Company ID (A6)', () => {
    const wrapper = mountComponent();

    const tokenInput = wrapper.find('input[name="token"]');
    const idEmpresaInput = wrapper.find('input[name="id_empresa"]');

    expect(tokenInput.exists()).toBe(true);
    expect(idEmpresaInput.exists()).toBe(true);
    expect(wrapper.vm.formItems).toEqual(
      mockYounusIntegration.settings_form_schema
    );
  });

  it('submitting with blank inputs blocks submission and does not dispatch network action (A7)', async () => {
    const wrapper = mountComponent();

    await wrapper.find('form').trigger('submit');

    expect(mockDispatch).not.toHaveBeenCalledWith(
      'integrations/createHook',
      expect.anything()
    );
  });
});
