import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  state as initialState,
  getters,
  actions,
  mutations,
} from '../CampaignPerformanceReports';
import types from '../../mutation-types';
import CampaignPerformanceReportsAPI from '../../../api/campaignPerformanceReports';

vi.mock('../../../api/campaignPerformanceReports', () => ({
  default: {
    get: vi.fn(),
  },
}));

describe('CampaignPerformanceReports Module', () => {
  let state;

  beforeEach(() => {
    state = { ...initialState };
    vi.clearAllMocks();
  });

  describe('getters', () => {
    it('returns report data', () => {
      state.data = { summary: { leads: 10 } };
      expect(getters.getData(state)).toEqual({ summary: { leads: 10 } });
    });

    it('returns uiFlags', () => {
      state.uiFlags = { fetchingItems: true };
      expect(getters.getUIFlags(state)).toEqual({ fetchingItems: true });
    });
  });

  describe('mutations', () => {
    it('sets uiFlags', () => {
      mutations[types.SET_CAMPAIGN_PERFORMANCE_REPORTS_UI_FLAG](state, {
        fetchingItems: true,
      });
      expect(state.uiFlags.fetchingItems).toBe(true);
    });

    it('sets report data', () => {
      const payload = { summary: { leads: 5 } };
      mutations[types.SET_CAMPAIGN_PERFORMANCE_REPORTS_DATA](state, payload);
      expect(state.data).toEqual(payload);
    });
  });

  describe('actions', () => {
    it('fetches report successfully', async () => {
      const commit = vi.fn();
      const mockData = { summary: { leads: 15 } };
      CampaignPerformanceReportsAPI.get.mockResolvedValue({ data: mockData });

      await actions.get({ commit }, { accountId: 1, since: 100, until: 200 });

      expect(commit).toHaveBeenCalledWith(
        types.SET_CAMPAIGN_PERFORMANCE_REPORTS_UI_FLAG,
        { fetchingItems: true }
      );
      expect(CampaignPerformanceReportsAPI.get).toHaveBeenCalledWith(1, {
        since: 100,
        until: 200,
      });
      expect(commit).toHaveBeenCalledWith(
        types.SET_CAMPAIGN_PERFORMANCE_REPORTS_DATA,
        mockData
      );
      expect(commit).toHaveBeenCalledWith(
        types.SET_CAMPAIGN_PERFORMANCE_REPORTS_UI_FLAG,
        { fetchingItems: false }
      );
    });
  });
});
