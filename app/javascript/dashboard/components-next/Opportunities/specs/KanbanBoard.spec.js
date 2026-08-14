import { vi } from 'vitest';
import { mount } from '@vue/test-utils';
import KanbanBoard from '../KanbanBoard.vue';
import { createStore } from 'vuex';

vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'opportunities_index', params: { accountId: 1 } }),
  useRouter: () => ({ push: vi.fn() }),
}));

const createMockStore = moveCardMock => {
  return createStore({
    modules: {
      opportunities: {
        namespaced: true,
        state: {
          byId: {
            1: { id: 1, pipeline_stage_id: 2, custom_attributes: {} },
          },
          idsByStage: {},
          pagination: {
            byStage: {},
          },
        },
        actions: {
          moveCard: moveCardMock,
          setStatus: vi.fn(),
          fetchForStage: vi.fn(),
        },
        getters: {
          cardsForStage: () => () => [],
          hasMoreForStage: () => () => false,
          isFetchingForStage: () => () => false,
        },
      },
      pipelineStages: {
        namespaced: true,
        actions: {
          fetch: vi.fn(),
        },
        getters: {
          stagesSortedByPosition: () => [
            { id: 1, position: 1 },
            { id: 2, position: 2 },
            { id: 3, position: 3 },
          ],
          stageById: () => id => {
            if (id === 1) return { id: 1, position: 1 };
            if (id === 2) return { id: 2, position: 2 };
            if (id === 3)
              return {
                id: 3,
                position: 3,
                required_custom_attribute_definitions: [
                  { attribute_key: 'company' },
                ],
              };
            return null;
          },
        },
      },
    },
  });
};

describe('KanbanBoard', () => {
  it('only dispatches moveCard once the drag ends, for backward/lateral moves even if missing fields', async () => {
    const moveCardSpy = vi.fn();
    const store = createMockStore(moveCardSpy);

    const wrapper = mount(KanbanBoard, {
      global: {
        plugins: [store],
        stubs: {
          KanbanColumn: true,
          OpportunityCreateModal: true,
          OpportunityBackfillModal: true,
          StageTransitionRequirementsModal: true,
          'router-view': true,
        },
        mocks: {
          $t: msg => msg,
          $route: { name: 'opportunities_index', params: {} },
          $router: { push: vi.fn() },
        },
      },
    });

    // Simulate a drag: onCardRemoved/onCardAdded fire live as SortableJS
    // moves the card across columns, before the user actually drops it.
    wrapper.vm.onDragStart(1);
    wrapper.vm.onCardRemoved({ id: 1, fromStageId: 2 });
    // Simulate adding card to stage 1 (backward move)
    wrapper.vm.onCardAdded({ id: 1, toStageId: 1, toIndex: 0 });

    // Bookkeeping only: the move must not dispatch until the drag ends
    expect(moveCardSpy).not.toHaveBeenCalled();

    wrapper.vm.onDragEnd();

    // dispatchMoveIfComplete runs on drag end
    expect(moveCardSpy).toHaveBeenCalledWith(expect.anything(), {
      id: 1,
      fromStageId: 2,
      toStageId: 1,
      toIndex: 0,
    });

    // Test forward move to a stage with missing fields
    moveCardSpy.mockClear();
    wrapper.vm.onDragStart(1);
    wrapper.vm.onCardRemoved({ id: 1, fromStageId: 2 });
    wrapper.vm.onCardAdded({ id: 1, toStageId: 3, toIndex: 0 });
    wrapper.vm.onDragEnd();

    // Should NOT have dispatched the move (it will open the modal instead)
    expect(moveCardSpy).not.toHaveBeenCalled();
    expect(wrapper.vm.isRequirementsModalOpen).toBe(true);
  });

  it('renders the board container with hidden scrollbar classes and handles mouse panning', async () => {
    const moveCardSpy = vi.fn();
    const store = createMockStore(moveCardSpy);

    const wrapper = mount(KanbanBoard, {
      global: {
        plugins: [store],
        stubs: {
          KanbanColumn: true,
          OpportunityCreateModal: true,
          OpportunityBackfillModal: true,
          StageTransitionRequirementsModal: true,
          'router-view': true,
        },
        mocks: {
          $t: msg => msg,
          $route: { name: 'opportunities_index', params: {} },
          $router: { push: vi.fn() },
        },
      },
    });

    const boardContainer = wrapper.find({ ref: 'boardContainerRef' });
    expect(boardContainer.exists()).toBe(true);
    expect(boardContainer.classes()).toContain('[scrollbar-width:none]');
    expect(boardContainer.classes()).toContain('[&::-webkit-scrollbar]:hidden');

    // Trigger mousedown on board
    await boardContainer.trigger('mousedown', { button: 0, pageX: 100 });
    expect(wrapper.vm.isPanning).toBe(true);

    // Trigger mousemove on window
    const moveEvent = new MouseEvent('mousemove', { pageX: 50 });
    window.dispatchEvent(moveEvent);

    // Trigger mouseup on window
    const upEvent = new MouseEvent('mouseup');
    window.dispatchEvent(upEvent);
    expect(wrapper.vm.isPanning).toBe(false);
  });
});
