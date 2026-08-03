import pipelineClosingRequiredFieldsAPI from 'dashboard/api/pipelineClosingRequiredFields';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await pipelineClosingRequiredFieldsAPI.get();
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
      const response = await pipelineClosingRequiredFieldsAPI.create({
        pipeline_closing_required_field: data,
      });
      commit('ADD_RECORD', response.data);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },
  destroy: async ({ commit }, id) => {
    try {
      await pipelineClosingRequiredFieldsAPI.delete(id);
      commit('REMOVE_RECORD', id);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },
};
