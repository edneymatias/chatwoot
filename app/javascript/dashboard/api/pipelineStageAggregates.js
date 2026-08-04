/* global axios */
import ApiClient from './ApiClient';

class PipelineStageAggregatesAPI extends ApiClient {
  constructor() {
    super('pipeline_stage_aggregates', { accountScoped: true });
  }

  get(stageIds = []) {
    const params = new URLSearchParams();
    stageIds.forEach(id => params.append('stage_ids[]', id));

    return axios.get(`${this.url}?${params.toString()}`);
  }
}

export default new PipelineStageAggregatesAPI();
