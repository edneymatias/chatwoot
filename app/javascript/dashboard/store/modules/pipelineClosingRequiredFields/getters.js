export const getters = {
  getRecords: state => state.records,
  getUIFlags: state => state.uiFlags,
  requiredForWon: state => state.records.filter(r => r.outcome === 'won'),
  requiredForLost: state => state.records.filter(r => r.outcome === 'lost'),
};
