/* eslint-disable consistent-return */
import opportunitiesAPI from 'dashboard/api/opportunities';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const actions = {
  fetchForStage: async ({ commit }, { stageId, page = 1 }) => {
    commit('SET_IS_FETCHING', { stageId, isFetching: true });
    try {
      const response = await opportunitiesAPI.get({
        pipeline_stage_id: stageId,
        page,
      });
      const payload = response.data.payload || response.data;

      commit('ADD_MANY_OPPORTUNITIES', payload);
      commit(
        'ADD_MANY_OPPORTUNITIES_ID',
        payload.map(o => o.id)
      );

      if (page === 1) {
        commit('SET_IDS_BY_STAGE', {
          stageId,
          opportunityIds: payload.map(o => o.id),
        });
      } else {
        commit('APPEND_IDS_BY_STAGE', {
          stageId,
          opportunityIds: payload.map(o => o.id),
        });
      }

      commit('SET_PAGINATION', {
        stageId,
        pagination: { page, hasMore: payload.length >= 15 },
      });
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_IS_FETCHING', { stageId, isFetching: false });
    }
  },
  moveCard: async (
    { commit, state },
    { id, fromStageId, toStageId, toIndex }
  ) => {
    const previousStageIds = [...(state.idsByStage[fromStageId] || [])];
    const previousToStageIds = [...(state.idsByStage[toStageId] || [])];

    commit('MOVE_CARD_OPTIMISTIC', { id, fromStageId, toStageId, toIndex });

    try {
      await opportunitiesAPI.update(id, { pipeline_stage_id: toStageId });
    } catch (error) {
      commit('REVERT_MOVE_CARD', {
        id,
        previousStageId: fromStageId,
        previousStageIds,
        previousToStageIds,
        toStageId,
      });
      throwErrorMessage(error);
    }
  },
  // eslint-disable-next-line consistent-return
  create: async (
    { commit },
    { title, contactId, pipelineStageId, originConversationId }
  ) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await opportunitiesAPI.create({
        opportunity: {
          title,
          contact_id: contactId,
          pipeline_stage_id: pipelineStageId,
          origin_conversation_id: originConversationId,
        },
      });
      const payload = response.data.payload || response.data;
      commit('ADD_OPPORTUNITY', payload);
      commit('PREPEND_ID_TO_STAGE', {
        stageId: payload.pipeline_stage_id,
        opportunityId: payload.id,
      });
      return payload;
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },
  // eslint-disable-next-line consistent-return
  setStatus: async ({ commit, state }, { id, status }) => {
    const previousStatus = state.byId[id]?.status || 'open';
    commit('SET_STATUS', { id, status });

    try {
      await opportunitiesAPI.update(id, { status });
    } catch (error) {
      commit('SET_STATUS', { id, status: previousStatus });
      throwErrorMessage(error);
    }
  },
};
