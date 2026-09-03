import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  state as initialState,
  getters,
  actions,
  mutations,
} from '../CampaignAttributionSettings';
import types from '../../mutation-types';
import CampaignAttributionSettingsAPI from '../../../api/campaignAttributionSettings';

vi.mock('../../../api/campaignAttributionSettings', () => ({
  default: {
    get: vi.fn(),
  },
}));

describe('CampaignAttributionSettings Module', () => {
  let state;

  beforeEach(() => {
    state = { ...initialState };
    vi.clearAllMocks();
  });

  describe('getters', () => {
    it('returns settings, isEnabled, and hasResolvedData', () => {
      state.settings = {
        enabled: true,
        connected: true,
        resolved_data_present: true,
      };
      expect(getters.getSettings(state)).toEqual({
        enabled: true,
        connected: true,
        resolved_data_present: true,
      });
      expect(getters.isEnabled(state)).toBe(true);
      expect(getters.hasResolvedData(state)).toBe(true);
    });

    it('returns uiFlags', () => {
      state.uiFlags = { isFetching: true };
      expect(getters.getUIFlags(state)).toEqual({ isFetching: true });
    });
  });

  describe('mutations', () => {
    it('sets uiFlags', () => {
      mutations[types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS_UI_FLAG](state, {
        isFetching: true,
      });
      expect(state.uiFlags.isFetching).toBe(true);
    });

    it('sets settings data', () => {
      const payload = { enabled: true, resolved_data_present: true };
      mutations[types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS](state, payload);
      expect(state.settings.enabled).toBe(true);
      expect(state.settings.resolved_data_present).toBe(true);
    });
  });

  describe('actions', () => {
    it('fetches settings successfully', async () => {
      const commit = vi.fn();
      const mockSettings = { enabled: true, resolved_data_present: true };
      CampaignAttributionSettingsAPI.get.mockResolvedValue({
        data: mockSettings,
      });

      await actions.get({ commit });

      expect(commit).toHaveBeenCalledWith(
        types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS_UI_FLAG,
        { isFetching: true }
      );
      expect(CampaignAttributionSettingsAPI.get).toHaveBeenCalled();
      expect(commit).toHaveBeenCalledWith(
        types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS,
        mockSettings
      );
      expect(commit).toHaveBeenCalledWith(
        types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS_UI_FLAG,
        { isFetching: false }
      );
    });
  });
});
