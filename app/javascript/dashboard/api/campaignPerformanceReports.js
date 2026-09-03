/* global axios */
import ApiClient from './ApiClient';

class CampaignPerformanceReportsAPI extends ApiClient {
  constructor() {
    super('campaign_performance_reports', { accountScoped: true });
  }

  get(accountId, { since, until } = {}) {
    return axios.get(this.url, {
      params: { since, until },
    });
  }
}

export default new CampaignPerformanceReportsAPI();
