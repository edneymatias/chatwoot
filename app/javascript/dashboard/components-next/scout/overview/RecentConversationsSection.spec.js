import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import RecentConversationsSection from './RecentConversationsSection.vue';
import scoutOverviewReportsAPI from 'dashboard/api/scoutOverviewReports';

withFullI18n();

const { mockUseAlert } = vi.hoisted(() => ({
  mockUseAlert: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mockUseAlert,
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: { value: 1 } }),
}));

vi.mock('dashboard/api/scoutOverviewReports');

describe('RecentConversationsSection', () => {
  const mockConversationsResponse = {
    data: {
      conversations: [
        {
          id: 101,
          display_id: 1,
          contact: {
            id: 11,
            name: 'Maria Silva',
            identifier: '+551199999999',
            thumbnail: null,
          },
          inbox: { id: 1, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' },
          start_at: 1773662400,
          duration_seconds: 245,
          messages_count: 6,
          status: 'qualified',
          opportunity: { id: 312, title: 'Deal Maria', stage_id: 5 },
        },
      ],
      status_counts: {
        all: 1,
        qualified: 1,
        disqualified: 0,
        abandoned: 0,
        in_progress: 0,
        transferred_without_opportunity: 0,
      },
      pagination: {
        current_page: 1,
        total_count: 1,
        per_page: 25,
        total_pages: 1,
      },
    },
  };

  beforeEach(() => {
    vi.clearAllMocks();
    window.open = vi.fn(() => ({ focus: vi.fn() }));
    scoutOverviewReportsAPI.getConversations.mockResolvedValue(
      mockConversationsResponse
    );
  });

  const mountSection = (props = {}) =>
    mount(RecentConversationsSection, {
      props: {
        scoutId: 1,
        range: '7',
        timezoneOffset: 0,
        ...props,
      },
      global: {
        stubs: {
          Policy: { template: '<div><slot /></div>' },
        },
      },
    });

  it('renders 5 table headers (U32, A1)', async () => {
    const wrapper = mountSection();
    await flushPromises();

    const headers = wrapper.findAll('th').map(h => h.text());
    expect(headers).toEqual([
      'Contact',
      'Start Time',
      'Duration',
      'Messages',
      'Status',
    ]);
  });

  it('renders 6 filter pills with counts (U33)', async () => {
    const wrapper = mountSection();
    await flushPromises();

    const pills = wrapper.findAll('[data-testid="status-filter-pill"]');
    expect(pills).toHaveLength(6);
    expect(pills[0].text()).toContain('All');
    expect(pills[0].text()).toContain('1');
    expect(pills[1].text()).toContain('Qualified');
    expect(pills[1].text()).toContain('1');
    expect(pills[2].text()).toContain('Disqualified');
    expect(pills[2].text()).toContain('0');
    expect(pills[3].text()).toContain('Abandoned');
    expect(pills[3].text()).toContain('0');
    expect(pills[4].text()).toContain('In Progress');
    expect(pills[4].text()).toContain('0');
    expect(pills[5].text()).toContain('Transferred without opportunity');
    expect(pills[5].text()).toContain('0');
  });

  it('clicking a status filter pill updates active status, resets page to 1, and re-fetches (U34, A2)', async () => {
    const wrapper = mountSection();
    await flushPromises();

    const pills = wrapper.findAll('[data-testid="status-filter-pill"]');
    await pills[1].trigger('click'); // click Qualified
    await flushPromises();

    expect(scoutOverviewReportsAPI.getConversations).toHaveBeenCalledWith(
      1,
      expect.objectContaining({
        status: 'qualified',
        page: 1,
      })
    );
  });

  it('formats positive duration with formatDuration (U35)', async () => {
    const wrapper = mountSection();
    await flushPromises();

    const row = wrapper.find('[data-testid="conversation-row"]');
    expect(row.find('[data-testid="duration-cell"]').text()).toBe('04:05');
  });

  it('displays dash placeholder (" — ") when duration is null or single message (U36)', async () => {
    const responseWithNullDuration = {
      data: {
        ...mockConversationsResponse.data,
        conversations: [
          {
            ...mockConversationsResponse.data.conversations[0],
            duration_seconds: null,
            messages_count: 1,
          },
        ],
      },
    };
    scoutOverviewReportsAPI.getConversations.mockResolvedValueOnce(
      responseWithNullDuration
    );

    const wrapper = mountSection();
    await flushPromises();

    const row = wrapper.find('[data-testid="conversation-row"]');
    expect(row.find('[data-testid="duration-cell"]').text()).toBe('—');
  });

  it('truncates long contact names and handles with Tailwind truncation classes (U37)', async () => {
    const wrapper = mountSection();
    await flushPromises();

    const contactName = wrapper.find('[data-testid="contact-name"]');
    expect(contactName.classes()).toContain('truncate');
  });

  it('renders EmptyStateLayout when conversation list is empty (U38)', async () => {
    const emptyResponse = {
      data: {
        conversations: [],
        status_counts: {
          all: 0,
          qualified: 0,
          disqualified: 0,
          abandoned: 0,
          in_progress: 0,
          transferred_without_opportunity: 0,
        },
        pagination: {
          current_page: 1,
          total_count: 0,
          per_page: 25,
          total_pages: 1,
        },
      },
    };
    scoutOverviewReportsAPI.getConversations.mockResolvedValueOnce(
      emptyResponse
    );

    const wrapper = mountSection();
    await flushPromises();

    expect(wrapper.find('[data-testid="empty-state"]').exists()).toBe(true);
  });

  it('renders PaginationFooter and fetches page on page change event (U39, A3)', async () => {
    const multiPageResponse = {
      data: {
        ...mockConversationsResponse.data,
        pagination: {
          current_page: 1,
          total_count: 48,
          per_page: 25,
          total_pages: 2,
        },
      },
    };
    scoutOverviewReportsAPI.getConversations.mockResolvedValueOnce(
      multiPageResponse
    );

    const wrapper = mountSection();
    await flushPromises();

    const pagination = wrapper.findComponent({ name: 'PaginationFooter' });
    expect(pagination.exists()).toBe(true);

    pagination.vm.$emit('update:currentPage', 2);
    await flushPromises();

    expect(scoutOverviewReportsAPI.getConversations).toHaveBeenCalledWith(
      1,
      expect.objectContaining({
        page: 2,
      })
    );
  });

  it('renders spinner during loading (U40)', async () => {
    scoutOverviewReportsAPI.getConversations.mockImplementation(
      () => new Promise(() => {}) // pending promise
    );

    const wrapper = mountSection();
    expect(wrapper.find('[data-testid="loading-spinner"]').exists()).toBe(true);
  });

  it('invokes window.open on row click with target _blank and noopener,noreferrer (U41, A6)', async () => {
    const wrapper = mountSection();
    await flushPromises();

    const row = wrapper.find('[data-testid="conversation-row"]');
    await row.trigger('click');

    expect(window.open).toHaveBeenCalledWith(
      '/app/accounts/1/conversations/101',
      '_blank',
      'noopener,noreferrer'
    );
  });

  it('displays warning notification when conversation ID is missing (U42, A7)', async () => {
    const missingIdResponse = {
      data: {
        ...mockConversationsResponse.data,
        conversations: [
          {
            ...mockConversationsResponse.data.conversations[0],
            id: null,
          },
        ],
      },
    };
    scoutOverviewReportsAPI.getConversations.mockResolvedValueOnce(
      missingIdResponse
    );

    const wrapper = mountSection();
    await flushPromises();

    const row = wrapper.find('[data-testid="conversation-row"]');
    await row.trigger('click');

    expect(window.open).not.toHaveBeenCalled();
    expect(mockUseAlert).toHaveBeenCalledWith(
      expect.stringContaining('missing or invalid')
    );
  });

  it('displays warning notification when popup is blocked (U43, A7)', async () => {
    window.open = vi.fn(() => null); // popup blocked

    const wrapper = mountSection();
    await flushPromises();

    const row = wrapper.find('[data-testid="conversation-row"]');
    await row.trigger('click');

    expect(mockUseAlert).toHaveBeenCalledWith(
      expect.stringContaining('blocked by your browser')
    );
  });

  it('displays transferred without opportunity with neutral styling (A5)', async () => {
    const handoffResponse = {
      data: {
        ...mockConversationsResponse.data,
        conversations: [
          {
            ...mockConversationsResponse.data.conversations[0],
            id: 102,
            status: 'transferred_without_opportunity',
            opportunity: null,
          },
        ],
      },
    };
    scoutOverviewReportsAPI.getConversations.mockResolvedValueOnce(
      handoffResponse
    );

    const wrapper = mountSection();
    await flushPromises();

    const badge = wrapper.find('[data-testid="conversation-status-badge"]');
    expect(badge.text()).toBe('Transferred without opportunity');
    expect(badge.classes()).toContain('bg-n-slate-3');
    expect(badge.classes()).not.toContain('bg-n-ruby-3');
  });
});
