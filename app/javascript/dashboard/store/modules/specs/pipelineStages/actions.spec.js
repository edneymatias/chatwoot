import { describe, it, expect, vi } from 'vitest';
import { actions } from '../../pipelineStages/actions';
import pipelineStageAggregatesAPI from 'dashboard/api/pipelineStageAggregates';

vi.mock('dashboard/api/pipelineStageAggregates', () => ({
  default: {
    get: vi.fn(),
  },
}));

describe('pipelineStages actions', () => {
  describe('fetchAggregates', () => {
    it('fetches aggregates and commits SET_STAGE_AGGREGATES for each stage', async () => {
      const commit = vi.fn();
      pipelineStageAggregatesAPI.get.mockResolvedValue({
        data: [
          { pipeline_stage_id: 1, count: 3, value_sum: 1500 },
          { pipeline_stage_id: 2, count: 0, value_sum: 0 },
        ],
      });

      await actions.fetchAggregates(
        { commit },
        { stageIds: [1, 2], filters: { q: 'test', status: 'won' } }
      );

      expect(pipelineStageAggregatesAPI.get).toHaveBeenCalledWith([1, 2], {
        q: 'test',
        status: 'won',
      });
      expect(commit).toHaveBeenCalledWith('SET_STAGE_AGGREGATES', {
        stageId: 1,
        count: 3,
        valueSum: 1500,
      });
      expect(commit).toHaveBeenCalledWith('SET_STAGE_AGGREGATES', {
        stageId: 2,
        count: 0,
        valueSum: 0,
      });
    });

    it('returns early if stageIds is empty', async () => {
      const commit = vi.fn();
      await actions.fetchAggregates({ commit }, { stageIds: [] });
      expect(pipelineStageAggregatesAPI.get).not.toHaveBeenCalled();
      expect(commit).not.toHaveBeenCalled();
    });
  });
});
