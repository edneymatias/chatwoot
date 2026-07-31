import pipelineStagesAPI from 'dashboard/api/pipelineStages';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await pipelineStagesAPI.get();
      const payload = response.data;
      commit('CLEAR_STAGES');
      commit('ADD_MANY_STAGES', payload);
      commit(
        'ADD_MANY_STAGES_ID',
        payload.map(stage => stage.id)
      );
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  // eslint-disable-next-line consistent-return
  create: async ({ commit }, data) => {
    try {
      const response = await pipelineStagesAPI.create(data);
      const payload = response.data.payload || response.data;
      commit('ADD_STAGE', payload);
      return payload;
    } catch (error) {
      throwErrorMessage(error);
    }
  },
  // eslint-disable-next-line consistent-return
  update: async ({ commit }, { id, ...data }) => {
    try {
      const response = await pipelineStagesAPI.update(id, data);
      const payload = response.data.payload || response.data;
      commit('UPDATE_STAGE', payload);
      return payload;
    } catch (error) {
      throwErrorMessage(error);
    }
  },
  delete: async ({ commit }, id) => {
    try {
      await pipelineStagesAPI.delete(id);
      commit('REMOVE_STAGE', id);
    } catch (error) {
      if (error.response && error.response.status === 422) {
        throw error;
      }
      throwErrorMessage(error);
    }
  },
};
