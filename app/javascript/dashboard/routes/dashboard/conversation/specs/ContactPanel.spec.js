import { vi, describe, it, expect, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { ref, h, nextTick } from 'vue';
import ContactPanel from '../ContactPanel.vue';

const mockEnabledErpIntegration = ref(null);
const mockSelectedChat = ref({
  id: 1,
  inbox_id: 1,
  meta: {
    sender: { id: 101, name: 'John Doe', phone_number: '+5511987654321' },
  },
});

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: vi.fn(),
    getters: {},
  }),
  useStoreGetters: () => ({}),
  useMapGetter: key => {
    if (key === 'integrations/getEnabledErpIntegration') {
      return mockEnabledErpIntegration;
    }
    if (key === 'getSelectedChat') {
      return mockSelectedChat;
    }
    if (key === 'contacts/getContact') {
      return ref(() => ({
        id: 101,
        name: 'John Doe',
        phone_number: '+5511987654321',
      }));
    }
    return ref({});
  },
  useFunctionGetter: () => ref({}),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: () => false,
  }),
}));

const mockIsOpen = ref(true);
const mockToggleSidebar = vi.fn();

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    updateUISettings: vi.fn(),
    isContactSidebarItemOpen: vi.fn((key, def) =>
      key === 'is_erp_data_open' ? mockIsOpen.value : def
    ),
    conversationSidebarItemsOrder: ref([
      { name: 'contact_attributes' },
      { name: 'erp_data' },
    ]),
    toggleSidebarUIState: mockToggleSidebar,
  }),
}));

const commonStubs = {
  SidebarActionsHeader: true,
  ContactInfo: true,
  CustomAttributes: true,
  WootButton: true,
  WootFeatureToggle: true,
  Draggable: {
    props: ['modelValue', 'list'],
    render() {
      const items = this.list || this.modelValue || [];
      return h(
        'div',
        items.map(element => this.$slots.item?.({ element }))
      );
    },
  },
  AccordionItem: {
    template:
      '<div class="accordion-item" :data-title="title" :data-is-open="isOpen"><slot name="button" /><slot /></div>',
    props: ['title', 'isOpen'],
  },
  ErpDataCard: true,
};

describe('ContactPanel - ERP Data integration', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockEnabledErpIntegration.value = null;
    mockIsOpen.value = true;
  });

  it('does not render erp_data accordion when erp integration is disabled (A2)', async () => {
    mockEnabledErpIntegration.value = null;

    const wrapper = mount(ContactPanel, {
      props: {
        conversationId: 1,
        inboxId: 1,
      },
      global: {
        stubs: commonStubs,
      },
    });

    expect(
      wrapper
        .find('[data-title="CONVERSATION_SIDEBAR.ACCORDION.ERP_DATA"]')
        .exists()
    ).toBe(false);
  });

  it('renders erp_data accordion section when erp integration is enabled, expanded by default (A1, U47, U48)', async () => {
    mockEnabledErpIntegration.value = {
      id: 'younus',
      name: 'Younus',
      category: 'erp',
      enabled: true,
    };

    const wrapper = mount(ContactPanel, {
      props: {
        conversationId: 1,
        inboxId: 1,
      },
      global: {
        stubs: commonStubs,
      },
    });
    await nextTick();

    const erpAccordion = wrapper.find(
      '[data-title="CONVERSATION_SIDEBAR.ACCORDION.ERP_DATA"]'
    );
    expect(erpAccordion.exists()).toBe(true);
    expect(erpAccordion.attributes('data-is-open')).toBe('true');
  });

  it('header refresh button triggers fetchErpData on the card ref (U49, A5)', async () => {
    mockEnabledErpIntegration.value = {
      id: 'younus',
      name: 'Younus',
      category: 'erp',
      enabled: true,
    };

    const fetchErpDataMock = vi.fn();

    const wrapper = mount(ContactPanel, {
      props: {
        conversationId: 1,
        inboxId: 1,
      },
      global: {
        stubs: {
          ...commonStubs,
          ErpDataCard: {
            template: '<div class="erp-data-card" />',
            methods: {
              fetchErpData: fetchErpDataMock,
            },
          },
          WootButton: {
            template:
              '<button class="woot-button" @click="$emit(\'click\', $event)"><slot /></button>',
          },
        },
      },
    });
    await nextTick();

    const refreshButton = wrapper.find('.woot-button');
    expect(refreshButton.exists()).toBe(true);
    await refreshButton.trigger('click');

    expect(fetchErpDataMock).toHaveBeenCalled();
  });
});
