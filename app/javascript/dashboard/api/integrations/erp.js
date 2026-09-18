/* global axios */

import ApiClient from '../ApiClient';

class ErpAPI extends ApiClient {
  constructor() {
    super('integrations/erp', { accountScoped: true });
  }

  get(contactId) {
    return axios.get(`${this.url}/data`, {
      params: { contact_id: contactId },
    });
  }
}

export default new ErpAPI();
