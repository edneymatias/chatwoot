/* global axios */
import ApiClient from './ApiClient';

class OpportunitiesAPI extends ApiClient {
  constructor() {
    super('opportunities', { accountScoped: true });
  }

  get(params) {
    if (params) {
      return axios.get(this.url, { params });
    }
    return super.get();
  }

  linkConversation(opportunityId, conversationId, forceTransfer = false) {
    return axios.post(`${this.url}/${opportunityId}/link_conversation`, {
      conversation_id: conversationId,
      force_transfer: forceTransfer,
    });
  }

  getActivities(opportunityId) {
    return axios.get(`${this.url}/${opportunityId}/activities`);
  }
}

export default new OpportunitiesAPI();
