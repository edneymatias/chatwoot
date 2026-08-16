/* global axios */
import ApiClient from './ApiClient';

class CampaignAttributionSettingsAPI extends ApiClient {
  constructor() {
    super('campaign_attribution_setting', { accountScoped: true });
  }

  // get is inherited from ApiClient
  update(data) {
    return axios.patch(this.url, data);
  }

  connect(access_token) {
    return axios.post(`${this.url}/connect`, { access_token });
  }

  reprocessPending() {
    return axios.post(`${this.url}/reprocess_pending`);
  }
}

export default new CampaignAttributionSettingsAPI();
