/* global axios */
import ApiClient from './ApiClient';

class PipelineStageAggregatesAPI extends ApiClient {
  constructor() {
    super('pipeline_stage_aggregates', { accountScoped: true });
  }

  get(stageIds = [], filters = {}) {
    const params = new URLSearchParams();
    stageIds.forEach(id => params.append('stage_ids[]', id));

    if (filters) {
      Object.keys(filters).forEach(key => {
        const val = filters[key];
        if (val !== undefined && val !== null && val !== '') {
          params.append(key, val);
        }
      });
    }

    return axios.get(`${this.url}?${params.toString()}`);
  }
}

export default new PipelineStageAggregatesAPI();
