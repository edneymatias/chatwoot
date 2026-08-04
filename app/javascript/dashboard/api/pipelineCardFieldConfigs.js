import ApiClient from './ApiClient';

class PipelineCardFieldConfigs extends ApiClient {
  constructor() {
    super('pipeline_card_field_configs', { accountScoped: true });
  }
}

export default new PipelineCardFieldConfigs();
