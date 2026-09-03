import types from '../mutation-types';
import CampaignPerformanceReportsAPI from '../../api/campaignPerformanceReports';

export const state = {
  data: {},
  uiFlags: {
    fetchingItems: false,
  },
};

export const getters = {
  getData(_state) {
    return _state.data;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getReport({ commit }, { accountId, since, until } = {}) {
    commit(types.SET_CAMPAIGN_PERFORMANCE_REPORTS_UI_FLAG, {
      fetchingItems: true,
    });
    try {
      const response = await CampaignPerformanceReportsAPI.get(accountId, {
        since,
        until,
      });
      commit(types.SET_CAMPAIGN_PERFORMANCE_REPORTS_DATA, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CAMPAIGN_PERFORMANCE_REPORTS_UI_FLAG, {
        fetchingItems: false,
      });
    }
  },
};

export const mutations = {
  [types.SET_CAMPAIGN_PERFORMANCE_REPORTS_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_CAMPAIGN_PERFORMANCE_REPORTS_DATA](_state, data) {
    _state.data = data;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
