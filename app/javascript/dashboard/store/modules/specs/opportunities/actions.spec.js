import { describe, it, expect, vi, beforeEach } from 'vitest';
import { actions } from '../../opportunities/actions';
import opportunitiesAPI from 'dashboard/api/opportunities';

vi.mock('dashboard/api/opportunities', () => ({
  default: {
    get: vi.fn(),
  },
}));

describe('opportunities actions', () => {
  describe('fetchForStage', () => {
    let state;
    let commit;

    beforeEach(() => {
      state = { uiFlags: { latestRequestIdByStage: {} } };
      commit = vi.fn((type, payload) => {
        if (type === 'SET_LATEST_REQUEST_ID') {
          state.uiFlags.latestRequestIdByStage[payload.stageId] =
            payload.requestId;
        }
      });
    });

    it('ignores a stale response that resolves after a newer request for the same stage', async () => {
      // Simulates fast typing: the broad "b" search is dispatched first but its response
      // arrives after the narrower "black" search that was dispatched right after it.
      let resolveFirst;
      let resolveSecond;
      opportunitiesAPI.get
        .mockImplementationOnce(
          () =>
            new Promise(resolve => {
              resolveFirst = resolve;
            })
        )
        .mockImplementationOnce(
          () =>
            new Promise(resolve => {
              resolveSecond = resolve;
            })
        );

      const firstCall = actions.fetchForStage(
        { commit, state },
        { stageId: 1, page: 1, filters: { q: 'b' } }
      );
      const secondCall = actions.fetchForStage(
        { commit, state },
        { stageId: 1, page: 1, filters: { q: 'black' } }
      );

      // The newer ("black") request resolves first, then the older ("b") one resolves
      // after it — the classic out-of-order race.
      resolveSecond({ data: [{ id: 2, title: 'Black Friday Deal' }] });
      await secondCall;
      resolveFirst({
        data: [
          { id: 1, title: 'Some other deal' },
          { id: 2, title: 'Black Friday Deal' },
        ],
      });
      await firstCall;

      const idsByStageCalls = commit.mock.calls.filter(
        ([type]) => type === 'SET_IDS_BY_STAGE'
      );

      // Only the "black" (latest) request's result should have been committed - the
      // stale "b" response must not have overwritten it afterwards.
      expect(idsByStageCalls).toHaveLength(1);
      expect(idsByStageCalls[0][1]).toEqual({
        stageId: 1,
        opportunityIds: [2],
      });
    });

    it('leaves isFetching alone when a stale response finishes after a newer request', async () => {
      let resolveFirst;
      let resolveSecond;
      opportunitiesAPI.get
        .mockImplementationOnce(
          () =>
            new Promise(resolve => {
              resolveFirst = resolve;
            })
        )
        .mockImplementationOnce(
          () =>
            new Promise(resolve => {
              resolveSecond = resolve;
            })
        );

      const firstCall = actions.fetchForStage(
        { commit, state },
        { stageId: 1, page: 1, filters: { q: 'b' } }
      );
      const secondCall = actions.fetchForStage(
        { commit, state },
        { stageId: 1, page: 1, filters: { q: 'black' } }
      );

      resolveSecond({ data: [] });
      await secondCall;
      resolveFirst({ data: [] });
      await firstCall;

      const isFetchingCalls = commit.mock.calls.filter(
        ([type]) => type === 'SET_IS_FETCHING'
      );

      // Set true twice (once per dispatch), then false exactly once - by the newer
      // request's own finally block, not the stale one's.
      expect(isFetchingCalls).toEqual([
        ['SET_IS_FETCHING', { stageId: 1, isFetching: true }],
        ['SET_IS_FETCHING', { stageId: 1, isFetching: true }],
        ['SET_IS_FETCHING', { stageId: 1, isFetching: false }],
      ]);
    });
  });
});
