export const getters = {
  cardsForStage: state => stageId => {
    const ids = state.idsByStage[stageId] || [];
    return ids.map(id => state.byId[id]).filter(card => card !== undefined);
  },
  cardsForContact: state => contactId => {
    const ids = state.idsByContact[contactId] || [];
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
  allCards: state => {
    return state.allIds
      .map(id => state.byId[id])
      .filter(card => card !== undefined);
  },
  hasMoreAll: state => {
    return state.pagination.all?.hasMore || false;
  },
  isFetchingAll: state => {
    return state.uiFlags.isFetchingAll || false;
  },
  opportunityByConversationId: state => conversationId => {
    if (!conversationId) return null;
    const numId = Number(conversationId);
    const allOpps = Object.values(state.byId);

    // 1. Direct active match on open opportunities first
    const activeOpen = allOpps.find(
      opp =>
        opp.status === 'open' &&
        (opp.active_conversation_id === numId ||
          opp.active_conversation_display_id === numId)
    );
    if (activeOpen) return activeOpen;

    // 2. Active match on any status
    const activeAny = allOpps.find(
      opp =>
        opp.active_conversation_id === numId ||
        opp.active_conversation_display_id === numId
    );
    if (activeAny) return activeAny;

    // 3. Match origin conversation
    const originMatch = allOpps.find(
      opp =>
        opp.origin_conversation_id === numId ||
        opp.origin_conversation_display_id === numId
    );
    if (originMatch) return originMatch;

    // 4. Fallback to associated conversations
    return (
      allOpps.find(
        opp =>
          opp.id === numId ||
          (opp.associated_conversations &&
            opp.associated_conversations.some(
              c => c.id === numId || c.display_id === numId
            ))
      ) || null
    );
  },
};
