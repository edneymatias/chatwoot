/* global axios */
import ApiClient from './ApiClient';

class OpportunityAttributeReportsAPI extends ApiClient {
  constructor() {
    super('opportunity_attribute_reports', { accountScoped: true });
  }

  get(accountId, { since, until, customAttributeDefinitionId } = {}) {
    return axios.get(this.url, {
      params: {
        since,
        until,
        custom_attribute_definition_id: customAttributeDefinitionId,
      },
    });
  }
}

export default new OpportunityAttributeReportsAPI();
