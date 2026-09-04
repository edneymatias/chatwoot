/* global axios */

import ApiClient from './ApiClient';

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  recipientsMetrics(id) {
    return axios.get(`${this.url}/${id}/recipients/metrics`);
  }

  recipientsContacts(id, { status, page } = {}) {
    return axios.get(`${this.url}/${id}/recipients/contacts`, {
      params: { status, page },
    });
  }

  recipientsReplyBreakdown(id) {
    return axios.get(`${this.url}/${id}/recipients/reply_breakdown`);
  }
}

export default new CampaignsAPI();
