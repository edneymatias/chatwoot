import { describe, it, expect } from 'vitest';
import { mutations } from '../../pipelineStages/mutations';

describe('pipelineStages mutations', () => {
  describe('SET_STAGE_AGGREGATES', () => {
    it('updates count and value_sum on the target stage', () => {
      const state = {
        byId: {
          1: { id: 1, name: 'Stage 1' },
          2: { id: 2, name: 'Stage 2', count: 5, value_sum: 200 },
        },
      };

      mutations.SET_STAGE_AGGREGATES(state, {
        stageId: 1,
        count: 10,
        valueSum: 5000,
      });

      expect(state.byId[1]).toEqual({
        id: 1,
        name: 'Stage 1',
        count: 10,
        value_sum: 5000,
      });
    });

    it('does nothing if stageId is not found', () => {
      const state = {
        byId: {
          1: { id: 1, name: 'Stage 1' },
        },
      };

      mutations.SET_STAGE_AGGREGATES(state, {
        stageId: 999,
        count: 10,
        valueSum: 5000,
      });

      expect(state.byId[999]).toBeUndefined();
    });
  });
});
