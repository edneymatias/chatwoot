import types from '../mutation-types';
import CampaignAttributionSettingsAPI from '../../api/campaignAttributionSettings';

export const state = {
  settings: {
    enabled: false,
    connected: false,
    pending_count: 0,
    resolved_data_present: false,
  },
  uiFlags: {
    isFetching: false,
  },
};

export const getters = {
  getSettings(_state) {
    return _state.settings;
  },
  isEnabled(_state) {
    return _state.settings.enabled;
  },
  hasResolvedData(_state) {
    return _state.settings.resolved_data_present;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getSettings({ commit }) {
    commit(types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS_UI_FLAG, {
      isFetching: true,
    });
    try {
      const response = await CampaignAttributionSettingsAPI.get();
      commit(types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS, response.data);
    } catch (error) {
      // API error handled silently for sidebar gating
    } finally {
      commit(types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS_UI_FLAG, {
        isFetching: false,
      });
    }
  },
};

export const mutations = {
  [types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_CAMPAIGN_ATTRIBUTION_SETTINGS](_state, data) {
    _state.settings = {
      ..._state.settings,
      ...data,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
