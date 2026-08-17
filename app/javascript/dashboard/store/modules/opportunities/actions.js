/* eslint-disable consistent-return */
import opportunitiesAPI from 'dashboard/api/opportunities';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const actions = {
  fetchForStage: async ({ commit }, { stageId, page = 1, filters = {} }) => {
    commit('SET_IS_FETCHING', { stageId, isFetching: true });
    try {
      const response = await opportunitiesAPI.get({
        pipeline_stage_id: stageId,
        page,
        ...filters,
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
  fetchAll: async ({ commit }, { page = 1, filters = {} } = {}) => {
    commit('SET_IS_FETCHING_ALL', true);
    try {
      const response = await opportunitiesAPI.get({ page, ...filters });
      const payload = response.data.payload || response.data;
      const meta = response.data.meta || {};

      commit('ADD_MANY_OPPORTUNITIES', payload);
      commit(
        'SET_ALL_CARDS',
        payload.map(o => o.id)
      );

      commit('SET_PAGINATION_ALL', {
        page,
        hasMore: payload.length >= 15,
        totalCount: meta.count || 0,
      });
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit('SET_IS_FETCHING_ALL', false);
    }
  },
  fetchForContact: async ({ commit }, { contactId }) => {
    try {
      const response = await opportunitiesAPI.get({
        contact_id: contactId,
        status: 'all',
      });
      const payload = response.data.payload || response.data;

      commit('ADD_MANY_OPPORTUNITIES', payload);
      commit(
        'ADD_MANY_OPPORTUNITIES_ID',
        payload.map(o => o.id)
      );
      commit('SET_IDS_BY_CONTACT', {
        contactId,
        opportunityIds: payload.map(o => o.id),
      });
    } catch (error) {
      throwErrorMessage(error);
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
      const response = await opportunitiesAPI.update(id, payload);
      const responsePayload = response.data.payload || response.data;
      if (responsePayload.current_stage_entered_at) {
        commit('UPDATE_OPPORTUNITY', {
          id,
          updates: {
            current_stage_entered_at: responsePayload.current_stage_entered_at,
          },
        });
      }
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
      assigneeId,
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
          assignee_id: assigneeId || null,
        },
      });
      const payload = response.data.payload || response.data;
      commit('ADD_OPPORTUNITY', payload);
      commit('PREPEND_ID_TO_STAGE', {
        stageId: payload.pipeline_stage_id,
        opportunityId: payload.id,
      });
      commit('PREPEND_ID_TO_CONTACT', {
        contactId: payload.contact_id,
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
    const stageId = state.byId[id]?.pipeline_stage_id;

    commit('SET_STATUS', { id, status });
    if (custom_attributes !== undefined) {
      commit('UPDATE_OPPORTUNITY', {
        id,
        updates: { custom_attributes },
      });
    }
    if (stageId && previousStatus === 'open' && status !== 'open') {
      commit('REMOVE_ID_FROM_STAGE', { stageId, id });
    } else if (stageId && previousStatus !== 'open' && status === 'open') {
      commit('PREPEND_ID_TO_STAGE', { stageId, opportunityId: id });
    }

    try {
      const payload = { status };
      if (custom_attributes !== undefined)
        payload.custom_attributes = custom_attributes;
      const response = await opportunitiesAPI.update(id, payload);
      const responsePayload = response.data.payload || response.data;
      commit('UPDATE_OPPORTUNITY', {
        id,
        updates: {
          status: responsePayload.status,
          custom_attributes: responsePayload.custom_attributes,
          value: responsePayload.value,
          updated_at: responsePayload.updated_at,
        },
      });
    } catch (error) {
      commit('SET_STATUS', { id, status: previousStatus });
      if (stageId && previousStatus === 'open' && status !== 'open') {
        commit('PREPEND_ID_TO_STAGE', { stageId, opportunityId: id });
      } else if (stageId && previousStatus !== 'open' && status === 'open') {
        commit('REMOVE_ID_FROM_STAGE', { stageId, id });
      }
      if (custom_attributes !== undefined) {
        commit('UPDATE_OPPORTUNITY', {
          id,
          updates: { custom_attributes: previousCustomAttributes },
        });
      }
      throw error;
    }
  },
  updateOpportunity: async ({ commit, state, dispatch }, { id, ...data }) => {
    try {
      const response = await opportunitiesAPI.update(id, data);
      const payload = response.data.payload || response.data;
      if (state.byId[id]) {
        const previousStageId = state.byId[id].pipeline_stage_id;
        const previousStatus = state.byId[id].status;
        commit('UPDATE_OPPORTUNITY', {
          id,
          updates: {
            title: payload.title,
            status: payload.status,
            assignee_id: payload.assignee_id,
            assignee: payload.assignee,
            custom_attributes: payload.custom_attributes,
            value: payload.value,
            pipeline_stage_id: payload.pipeline_stage_id,
            current_stage_entered_at: payload.current_stage_entered_at,
            origin_conversation_id: payload.origin_conversation_id,
            origin_conversation_display_id:
              payload.origin_conversation_display_id,
            updated_at: payload.updated_at,
          },
        });
        if (
          payload.pipeline_stage_id &&
          payload.pipeline_stage_id !== previousStageId
        ) {
          commit('MOVE_ID_BETWEEN_STAGES', {
            id,
            fromStageId: previousStageId,
            toStageId: payload.pipeline_stage_id,
          });
        }
        const currentStageId = payload.pipeline_stage_id || previousStageId;
        if (
          currentStageId &&
          previousStatus === 'open' &&
          payload.status !== 'open'
        ) {
          commit('REMOVE_ID_FROM_STAGE', { stageId: currentStageId, id });
        } else if (
          currentStageId &&
          previousStatus !== 'open' &&
          payload.status === 'open'
        ) {
          commit('PREPEND_ID_TO_STAGE', {
            stageId: currentStageId,
            opportunityId: id,
          });
        }
        if (payload.pipeline_stage_id) {
          dispatch(
            'pipelineStages/fetchAggregates',
            {
              stageIds: [payload.pipeline_stage_id, previousStageId].filter(
                Boolean
              ),
            },
            { root: true }
          );
        }
      }
      return payload;
    } catch (error) {
      if (error.response?.status === 422) {
        throw error;
      }
      throwErrorMessage(error);
    }
  },
  syncOpportunity: ({ commit, state, dispatch }, data) => {
    const existing = state.byId[data.id];
    if (!existing) return;

    // Broadcasts are delivered via a background job and are not guaranteed
    // to arrive in the order they were triggered — dropping an out-of-date
    // broadcast prevents it from clobbering a more recent local update.
    if (
      existing.updated_at &&
      data.updated_at &&
      new Date(data.updated_at) < new Date(existing.updated_at)
    ) {
      return;
    }

    const previousStageId = existing.pipeline_stage_id;
    const previousStatus = existing.status;

    commit('UPDATE_OPPORTUNITY', { id: data.id, updates: data });

    if (data.pipeline_stage_id && data.pipeline_stage_id !== previousStageId) {
      commit('MOVE_ID_BETWEEN_STAGES', {
        id: data.id,
        fromStageId: previousStageId,
        toStageId: data.pipeline_stage_id,
      });
    }
    const currentStageId = data.pipeline_stage_id || previousStageId;
    if (currentStageId && previousStatus === 'open' && data.status !== 'open') {
      commit('REMOVE_ID_FROM_STAGE', { stageId: currentStageId, id: data.id });
    } else if (
      currentStageId &&
      previousStatus !== 'open' &&
      data.status === 'open'
    ) {
      commit('PREPEND_ID_TO_STAGE', {
        stageId: currentStageId,
        opportunityId: data.id,
      });
    }

    if (data.pipeline_stage_id) {
      dispatch(
        'pipelineStages/fetchAggregates',
        { stageIds: [data.pipeline_stage_id, previousStageId].filter(Boolean) },
        { root: true }
      );
    }
  },
  linkConversation: async (
    { commit },
    { id, conversationId, forceTransfer = false }
  ) => {
    const response = await opportunitiesAPI.linkConversation(
      id,
      conversationId,
      forceTransfer
    );
    const payload = response.data.payload || response.data;
    commit('UPDATE_OPPORTUNITY', {
      id,
      updates: payload,
    });
    return payload;
  },
};
