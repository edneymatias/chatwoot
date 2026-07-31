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
}

export default new OpportunitiesAPI();
