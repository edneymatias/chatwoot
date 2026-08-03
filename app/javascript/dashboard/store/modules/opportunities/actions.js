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
        pagination: { page, hasMore: payload.length >= 10 },
      });
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_IS_FETCHING', { stageId, isFetching: false });
    }
  },
  moveCard: async (
    { commit, state },
    { id, fromStageId, toStageId, toIndex, custom_attributes, value }
  ) => {
    const previousStageIds = [...(state.idsByStage[fromStageId] || [])];
    const previousToStageIds = [...(state.idsByStage[toStageId] || [])];
    const previousCustomAttributes = state.byId[id]?.custom_attributes;
    const previousValue = state.byId[id]?.value;

    commit('MOVE_CARD_OPTIMISTIC', {
      id,
      fromStageId,
      toStageId,
      toIndex,
      custom_attributes,
      value,
    });

    try {
      const payload = { pipeline_stage_id: toStageId };
      if (custom_attributes !== undefined)
        payload.custom_attributes = custom_attributes;
      if (value !== undefined) payload.value = value;
      await opportunitiesAPI.update(id, payload);
    } catch (error) {
      commit('REVERT_MOVE_CARD', {
        id,
        previousStageId: fromStageId,
        previousStageIds,
        previousToStageIds,
        toStageId,
        previousCustomAttributes,
        previousValue,
      });
      throw error;
    }
  },
  // eslint-disable-next-line consistent-return
  create: async (
    { commit },
    {
      title,
      contactId,
      pipelineStageId,
      originConversationId,
      custom_attributes,
      value,
    }
  ) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await opportunitiesAPI.create({
        opportunity: {
          title,
          contact_id: contactId,
          pipeline_stage_id: pipelineStageId,
          origin_conversation_id: originConversationId,
          custom_attributes,
          value,
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
  setStatus: async ({ commit, state }, { id, status, custom_attributes }) => {
    const previousStatus = state.byId[id]?.status || 'open';
    const previousCustomAttributes = state.byId[id]?.custom_attributes;

    commit('SET_STATUS', { id, status });
    if (custom_attributes !== undefined) {
      commit('UPDATE_OPPORTUNITY', {
        id,
        updates: { custom_attributes },
      });
    }

    try {
      const payload = { status };
      if (custom_attributes !== undefined)
        payload.custom_attributes = custom_attributes;
      await opportunitiesAPI.update(id, payload);
    } catch (error) {
      commit('SET_STATUS', { id, status: previousStatus });
      if (custom_attributes !== undefined) {
        commit('UPDATE_OPPORTUNITY', {
          id,
          updates: { custom_attributes: previousCustomAttributes },
        });
      }
      throw error;
    }
  },
  updateOpportunity: async ({ commit, state }, { id, ...data }) => {
    try {
      const response = await opportunitiesAPI.update(id, data);
      const payload = response.data.payload || response.data;
      if (state.byId[id]) {
        commit('UPDATE_OPPORTUNITY', {
          id,
          updates: {
            custom_attributes: payload.custom_attributes,
            value: payload.value,
          },
        });
      }
      return payload;
    } catch (error) {
      if (error.response?.status === 422) {
        throw error;
      }
      throwErrorMessage(error);
    }
  },
  syncOpportunity: ({ commit, state }, data) => {
    if (state.byId[data.id]) {
      commit('UPDATE_OPPORTUNITY', { id: data.id, updates: data });
    }
  },
};
