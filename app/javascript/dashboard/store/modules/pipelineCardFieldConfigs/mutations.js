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
  UPDATE_RECORD(state, data) {
    state.records = state.records.map(r => (r.id === data.id ? data : r));
  },
  REMOVE_RECORD(state, id) {
    state.records = state.records.filter(r => r.id !== id);
  },
};
