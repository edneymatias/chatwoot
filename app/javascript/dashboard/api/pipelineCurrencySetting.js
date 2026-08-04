/* global axios */
import ApiClient from './ApiClient';

class PipelineCurrencySetting extends ApiClient {
  constructor() {
    super('pipeline_currency_setting', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  update(data) {
    return axios.put(this.url, data);
  }
}

export default new PipelineCurrencySetting();
