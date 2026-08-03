import { actions } from './actions';
import { mutations } from './mutations';
import { getters } from './getters';

const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
