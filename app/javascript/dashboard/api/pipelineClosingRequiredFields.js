import ApiClient from './ApiClient';

class PipelineClosingRequiredFieldsAPI extends ApiClient {
  constructor() {
    super('pipeline_closing_required_fields', { accountScoped: true });
  }
}

export default new PipelineClosingRequiredFieldsAPI();
