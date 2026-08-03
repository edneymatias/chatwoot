export const mutations = {
  SET_UI_FLAG(state, uiFlags) {
    state.uiFlags = {
      ...state.uiFlags,
      ...uiFlags,
    };
  },
  ADD_MANY_STAGES(state, stages) {
    const byId = { ...state.byId };
    stages.forEach(stage => {
      byId[stage.id] = stage;
    });
    state.byId = byId;
  },
  ADD_MANY_STAGES_ID(state, stageIds) {
    state.allIds.push(...stageIds);
  },
  ADD_STAGE(state, stage) {
    state.byId[stage.id] = stage;
    if (!state.allIds.includes(stage.id)) {
      state.allIds.push(stage.id);
    }
  },
  UPDATE_STAGE(state, stage) {
    if (state.byId[stage.id]) {
      state.byId[stage.id] = { ...state.byId[stage.id], ...stage };
    }
  },
  REMOVE_STAGE(state, id) {
    if (state.byId[id]) {
      const byId = { ...state.byId };
      delete byId[id];
      state.byId = byId;
      state.allIds = state.allIds.filter(stageId => stageId !== id);
    }
  },
  CLEAR_STAGES(state) {
    state.byId = {};
    state.allIds = [];
  },
  SET_STAGES(state, stages) {
    const byId = {};
    stages.forEach(stage => {
      byId[stage.id] = stage;
    });
    state.byId = byId;
    state.allIds = stages.map(stage => stage.id);
  },
};
