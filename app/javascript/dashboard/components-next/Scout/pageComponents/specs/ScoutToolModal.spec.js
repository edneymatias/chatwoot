import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import ScoutAPI from 'dashboard/api/scout';
import ScoutToolModal from '../ScoutToolModal.vue';

vi.mock('dashboard/api/scout', () => ({
  default: {
    createTool: vi.fn(),
    updateTool: vi.fn(),
    testTool: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const DialogStub = {
  name: 'Dialog',
  props: {
    disableConfirmButton: { type: Boolean, default: false },
    isLoading: { type: Boolean, default: false },
  },
  emits: ['close', 'confirm'],
  methods: {
    open() {},
    close() {},
  },
  template: `
    <div data-test="dialog-stub">
      <slot />
    </div>
  `,
};

describe('ScoutToolModal.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('scaffold initializes properly', () => {
    const wrapper = mount(ScoutToolModal, {
      props: { tool: null },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    expect(wrapper.exists()).toBe(true);
  });

  it('includes id in testPayload when editing an existing tool (User Story 1)', async () => {
    ScoutAPI.testTool.mockResolvedValue({ data: { success: true } });

    const existingTool = {
      id: 42,
      name: 'Existing Tool',
      description: 'Tool description',
      endpoint_url: 'https://api.example.com/test',
      http_method: 'POST',
      auth_type: 'bearer',
      auth_headers: { token: '••••••••' },
      parameter_schema: {},
      response_template: '',
    };

    const wrapper = mount(ScoutToolModal, {
      props: { tool: existingTool },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    const buttons = wrapper.findAll('button');
    const testButton = buttons.find(
      b =>
        b.text().includes('SCOUT.TOOLS.MODAL.TEST_BUTTON') ||
        b.html().includes('i-lucide-play')
    );
    expect(testButton).toBeDefined();

    await testButton.trigger('click');

    expect(ScoutAPI.testTool).toHaveBeenCalledWith(
      expect.objectContaining({
        id: 42,
        endpoint_url: 'https://api.example.com/test',
        auth_type: 'bearer',
      })
    );
  });

  it('omits id from testPayload when creating a brand-new tool (User Story 2)', async () => {
    ScoutAPI.testTool.mockResolvedValue({ data: { success: true } });

    const wrapper = mount(ScoutToolModal, {
      props: { tool: null },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    const input = wrapper.find('input[placeholder*="https://api.example.com"]');
    expect(input.exists()).toBe(true);
    await input.setValue('https://api.example.com/draft');

    const buttons = wrapper.findAll('button');
    const testButton = buttons.find(
      b =>
        b.text().includes('SCOUT.TOOLS.MODAL.TEST_BUTTON') ||
        b.html().includes('i-lucide-play')
    );
    expect(testButton).toBeDefined();

    await testButton.trigger('click');

    expect(ScoutAPI.testTool).toHaveBeenCalledTimes(1);
    const payload = ScoutAPI.testTool.mock.calls[0][0];
    expect(payload.id).toBeUndefined();
    expect(payload.endpoint_url).toBe('https://api.example.com/draft');
  });
});
