/* global axios */
import ApiClient from './ApiClient';

class OpportunityFunnelReportsAPI extends ApiClient {
  constructor() {
    super('opportunity_funnel_reports', { accountScoped: true });
  }

  get(accountId, { since, until } = {}) {
    return axios.get(this.url, {
      params: { since, until },
    });
  }
}

export default new OpportunityFunnelReportsAPI();
