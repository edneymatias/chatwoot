export const getters = {
  cardsForStage: state => stageId => {
    const ids = state.idsByStage[stageId] || [];
    return ids.map(id => state.byId[id]).filter(card => card !== undefined);
  },
  cardById: state => id => {
    return state.byId[id];
  },
  hasMoreForStage: state => stageId => {
    return state.pagination.byStage[stageId]?.hasMore || false;
  },
  isFetchingForStage: state => stageId => {
    return state.uiFlags.isFetchingByStage[stageId] || false;
  },
};
