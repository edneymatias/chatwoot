export const mutations = {
  SET_UI_FLAG(state, data) {
    state.uiFlags = {
      ...state.uiFlags,
      ...data,
    };
  },
  SET_CURRENCY(state, currency) {
    state.currency = currency;
  },
};
