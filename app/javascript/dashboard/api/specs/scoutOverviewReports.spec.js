import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import scoutOverviewReportsAPI from '../scoutOverviewReports';
import ApiClient from '../ApiClient';

describe('#scoutOverviewReportsAPI', () => {
  it('creates correct instance', () => {
    expect(scoutOverviewReportsAPI).toBeInstanceOf(ApiClient);
    expect(scoutOverviewReportsAPI).toHaveProperty('get');
    expect(scoutOverviewReportsAPI).toHaveProperty('getConversations');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve({ data: {} })),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#getConversations sends GET request to conversations endpoint with serialized params (U26)', () => {
      const params = {
        scoutId: 10,
        range: '7',
        timezoneOffset: -3,
        status: 'qualified',
        page: 2,
        perPage: 25,
      };

      scoutOverviewReportsAPI.getConversations(1, params);

      expect(axiosMock.get).toHaveBeenCalledWith(
        `${scoutOverviewReportsAPI.url}/conversations`,
        {
          params: {
            scout_id: 10,
            range: '7',
            timezone_offset: -3,
            status: 'qualified',
            page: 2,
            per_page: 25,
          },
        }
      );
    });
  });
});
