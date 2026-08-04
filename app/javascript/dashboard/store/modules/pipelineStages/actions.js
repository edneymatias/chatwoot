import pipelineStagesAPI from 'dashboard/api/pipelineStages';
import pipelineStageAggregatesAPI from 'dashboard/api/pipelineStageAggregates';
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
  create: async ({ commit }, data) => {
    try {
      const response = await pipelineStagesAPI.create(data);
      const payload = response.data.payload || response.data;
      commit('ADD_STAGE', payload);
      return payload;
    } catch (error) {
      throwErrorMessage(error);
      return undefined;
    }
  },
  update: async ({ commit }, { id, ...data }) => {
    const response = await pipelineStagesAPI.update(id, data);
    const payload = response.data.payload || response.data;
    if (Array.isArray(payload)) {
      commit('SET_STAGES', payload);
    } else {
      commit('UPDATE_STAGE', payload);
    }
    return payload;
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
  addRequiredField: async (
    { commit },
    { stageId, customAttributeDefinitionId }
  ) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await pipelineStagesAPI.addRequiredField(
        stageId,
        customAttributeDefinitionId
      );
      // Wait, we need to update the stage in the store with the new required field?
      // Or maybe the easiest is to fetch the stages again, or we can just fetch the stage again, or update it manually.
      // The API currently returns the pipeline_stage_required_field object, not the full stage.
      // For now, let's just return the response and let the component handle re-fetching if needed,
      // or we can just dispatch fetch. Let's dispatch fetch for simplicity.
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      return undefined;
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  removeRequiredField: async (
    { commit },
    { stageId, customAttributeDefinitionId }
  ) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      await pipelineStagesAPI.removeRequiredField(
        stageId,
        customAttributeDefinitionId
      );
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },
  fetchAggregates: async ({ commit }, { stageIds }) => {
    if (!stageIds || stageIds.length === 0) return;

    const response = await pipelineStageAggregatesAPI.get(stageIds);
    const aggregates = response.data;

    const responseByStageId = {};
    aggregates.forEach(agg => {
      responseByStageId[agg.pipeline_stage_id] = agg;
    });

    stageIds.forEach(stageId => {
      const agg = responseByStageId[stageId];
      if (agg) {
        commit('SET_STAGE_AGGREGATES', {
          stageId,
          openCount: agg.open_count,
          openValueSum: agg.open_value_sum,
        });
      } else {
        commit('SET_STAGE_AGGREGATES', {
          stageId,
          openCount: 0,
          openValueSum: 0,
        });
      }
    });
  },
};
