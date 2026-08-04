import pipelineCurrencySettingAPI from 'dashboard/api/pipelineCurrencySetting';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await pipelineCurrencySettingAPI.get();
      commit('SET_CURRENCY', response.data.currency);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  update: async ({ commit }, data) => {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      const response = await pipelineCurrencySettingAPI.update(data);
      commit('SET_CURRENCY', response.data.currency);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isUpdating: false });
    }
  },
};
