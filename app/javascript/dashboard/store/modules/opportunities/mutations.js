export const mutations = {
  SET_UI_FLAG(state, uiFlags) {
    state.uiFlags = {
      ...state.uiFlags,
      ...uiFlags,
    };
  },
  SET_IS_FETCHING(state, { stageId, isFetching }) {
    state.uiFlags.isFetchingByStage = {
      ...state.uiFlags.isFetchingByStage,
      [stageId]: isFetching,
    };
  },
  SET_IS_FETCHING_ALL(state, isFetching) {
    state.uiFlags.isFetchingAll = isFetching;
  },
  ADD_MANY_OPPORTUNITIES(state, opportunities) {
    const byId = { ...state.byId };
    opportunities.forEach(opp => {
      byId[opp.id] = opp;
    });
    state.byId = byId;
  },
  ADD_MANY_OPPORTUNITIES_ID(state, opportunityIds) {
    const newIds = opportunityIds.filter(id => !state.allIds.includes(id));
    state.allIds.push(...newIds);
  },
  SET_ALL_CARDS(state, opportunityIds) {
    state.allIds = opportunityIds;
  },
  SET_PAGINATION_ALL(state, pagination) {
    state.pagination.all = pagination;
  },
  SET_IDS_BY_STAGE(state, { stageId, opportunityIds }) {
    state.idsByStage = {
      ...state.idsByStage,
      [stageId]: opportunityIds,
    };
  },
  SET_IDS_BY_CONTACT(state, { contactId, opportunityIds }) {
    state.idsByContact = {
      ...state.idsByContact,
      [contactId]: opportunityIds,
    };
  },
  APPEND_IDS_BY_STAGE(state, { stageId, opportunityIds }) {
    const existing = state.idsByStage[stageId] || [];
    const newIds = opportunityIds.filter(id => !existing.includes(id));
    state.idsByStage = {
      ...state.idsByStage,
      [stageId]: [...existing, ...newIds],
    };
  },
  SET_PAGINATION(state, { stageId, pagination }) {
    state.pagination.byStage = {
      ...state.pagination.byStage,
      [stageId]: pagination,
    };
  },
  MOVE_CARD_OPTIMISTIC(
    state,
    { id, fromStageId, toStageId, toIndex, custom_attributes, value }
  ) {
    const fromIds = [...(state.idsByStage[fromStageId] || [])];
    const cardIndex = fromIds.indexOf(id);
    if (cardIndex !== -1) fromIds.splice(cardIndex, 1);

    let toIds;
    if (fromStageId === toStageId) {
      toIds = fromIds;
    } else {
      toIds = [...(state.idsByStage[toStageId] || [])];
    }
    toIds.splice(toIndex, 0, id);

    state.idsByStage = {
      ...state.idsByStage,
      [fromStageId]: fromIds,
      [toStageId]: toIds,
    };

    if (state.byId[id]) {
      const updates = { pipeline_stage_id: toStageId };
      if (custom_attributes !== undefined)
        updates.custom_attributes = custom_attributes;
      if (value !== undefined) updates.value = value;
      state.byId[id] = { ...state.byId[id], ...updates };
    }
  },
  REVERT_MOVE_CARD(
    state,
    {
      id,
      previousStageId,
      previousStageIds,
      previousToStageIds,
      toStageId,
      previousCustomAttributes,
      previousValue,
    }
  ) {
    state.idsByStage = {
      ...state.idsByStage,
      [previousStageId]: previousStageIds,
      [toStageId]: previousToStageIds,
    };

    if (state.byId[id]) {
      const updates = { pipeline_stage_id: previousStageId };
      if (previousCustomAttributes !== undefined)
        updates.custom_attributes = previousCustomAttributes;
      if (previousValue !== undefined) updates.value = previousValue;
      state.byId[id] = {
        ...state.byId[id],
        ...updates,
      };
    }
  },
  ADD_OPPORTUNITY(state, opportunity) {
    state.byId[opportunity.id] = opportunity;
    if (!state.allIds.includes(opportunity.id)) {
      state.allIds.push(opportunity.id);
    }
  },
  PREPEND_ID_TO_STAGE(state, { stageId, opportunityId }) {
    const existing = state.idsByStage[stageId] || [];
    if (!existing.includes(opportunityId)) {
      state.idsByStage = {
        ...state.idsByStage,
        [stageId]: [opportunityId, ...existing],
      };
    }
  },
  PREPEND_ID_TO_CONTACT(state, { contactId, opportunityId }) {
    if (state.idsByContact[contactId] === undefined) return;
    const existing = state.idsByContact[contactId];
    if (!existing.includes(opportunityId)) {
      state.idsByContact = {
        ...state.idsByContact,
        [contactId]: [opportunityId, ...existing],
      };
    }
  },
  SET_STATUS(state, { id, status }) {
    if (state.byId[id]) {
      state.byId[id] = { ...state.byId[id], status };
    }
  },
  UPDATE_OPPORTUNITY(state, { id, updates }) {
    if (state.byId[id]) {
      state.byId[id] = { ...state.byId[id], ...updates };
    }
  },
  MOVE_ID_BETWEEN_STAGES(state, { id, fromStageId, toStageId }) {
    if (fromStageId === toStageId) return;

    const fromIds = fromStageId
      ? [...(state.idsByStage[fromStageId] || [])]
      : [];
    const cardIndex = fromIds.indexOf(id);
    if (cardIndex !== -1) fromIds.splice(cardIndex, 1);

    const toIds = [...(state.idsByStage[toStageId] || [])];
    if (!toIds.includes(id)) toIds.push(id);

    state.idsByStage = {
      ...state.idsByStage,
      ...(fromStageId ? { [fromStageId]: fromIds } : {}),
      [toStageId]: toIds,
    };
  },
};
