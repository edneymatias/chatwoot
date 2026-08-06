import { getters } from './getters';
import { actions } from './actions';
import { mutations } from './mutations';

const state = {
  byId: {},
  idsByStage: {},
  idsByContact: {},
  allIds: [],
  pagination: {
    byStage: {},
  },
  uiFlags: {
    isFetchingByStage: {},
    isCreating: false,
    isMoving: {},
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
