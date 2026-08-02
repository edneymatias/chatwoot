/* global axios */
import ApiClient from './ApiClient';

class PipelineStagesAPI extends ApiClient {
  constructor() {
    super('pipeline_stages', { accountScoped: true });
  }

  addRequiredField(stageId, customAttributeDefinitionId) {
    return axios.post(`${this.url}/${stageId}/required_fields`, {
      pipeline_stage_required_field: {
        custom_attribute_definition_id: customAttributeDefinitionId,
      },
    });
  }

  removeRequiredField(stageId, customAttributeDefinitionId) {
    return axios.delete(
      `${this.url}/${stageId}/required_fields/${customAttributeDefinitionId}`
    );
  }
}

export default new PipelineStagesAPI();
