export const getters = {
  stagesSortedByPosition: state => {
    const stages = state.allIds
      .map(id => state.byId[id])
      .filter(stage => stage !== undefined);
    return stages.sort(
      (a, b) => (a.position ?? Infinity) - (b.position ?? Infinity)
    );
  },
  stageById: state => id => {
    return state.byId[id];
  },
  getUIFlags: state => {
    return state.uiFlags;
  },
};
