export const mutations = {
  SET_UI_FLAG(state, data) {
    state.uiFlags = {
      ...state.uiFlags,
      ...data,
    };
  },
  SET_RECORDS(state, data) {
    state.records = data;
  },
  ADD_RECORD(state, data) {
    state.records.push(data);
  },
  REMOVE_RECORD(state, id) {
    state.records = state.records.filter(r => r.id !== id);
  },
};
