import pipelineCardFieldConfigsAPI from 'dashboard/api/pipelineCardFieldConfigs';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await pipelineCardFieldConfigsAPI.get();
      commit('SET_RECORDS', response.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  create: async ({ commit }, data) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await pipelineCardFieldConfigsAPI.create({
        pipeline_card_field_config: data,
      });
      commit('ADD_RECORD', response.data);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...data }) => {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      const response = await pipelineCardFieldConfigsAPI.update(id, {
        pipeline_card_field_config: data,
      });
      commit('UPDATE_RECORD', response.data);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isUpdating: false });
    }
  },
  destroy: async ({ commit }, id) => {
    try {
      await pipelineCardFieldConfigsAPI.delete(id);
      commit('REMOVE_RECORD', id);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },
};
