<script setup>
import { computed, ref, onMounted, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import KanbanColumn from './KanbanColumn.vue';
import KanbanStatusBar from './KanbanStatusBar.vue';
import OpportunityCreateModal from './OpportunityCreateModal.vue';
import OpportunityBackfillModal from './OpportunityBackfillModal.vue';
import StageTransitionRequirementsModal from './StageTransitionRequirementsModal.vue';
import ClosingRequirementsModal from './ClosingRequirementsModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  filters: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['cardClick']);

const isCardDragging = ref(false);
const isStatusBarHovered = ref(false);
const draggedCardId = ref(null);
const statusBarHandledId = ref(null);
const statusBarPendingMove = ref(null);

const onDragStart = id => {
  isCardDragging.value = true;
  draggedCardId.value = id;
};

const store = useStore();

const isCreateModalOpen = ref(false);
const modalDefaultStageId = ref(null);

const isBackfillModalOpen = ref(false);
const backfillOpportunityId = ref(null);

const openCreateModal = stageId => {
  modalDefaultStageId.value = stageId;
  isCreateModalOpen.value = true;
};

const closeCreateModal = () => {
  isCreateModalOpen.value = false;
  modalDefaultStageId.value = null;
};

const openBackfillModal = opportunityId => {
  backfillOpportunityId.value = opportunityId;
  isBackfillModalOpen.value = true;
};

const closeBackfillModal = () => {
  isBackfillModalOpen.value = false;
  backfillOpportunityId.value = null;
};

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);

onMounted(async () => {
  // Fetches are handled in Index.vue now to apply to all view modes
});

const pendingMove = ref({});

const isClosingRequirementsModalOpen = ref(false);
const closingRequirementsModalData = ref({});

const closeClosingRequirementsModal = () => {
  isClosingRequirementsModalOpen.value = false;
  closingRequirementsModalData.value = {};
};

const onStatusChanged = async ({ id, status }) => {
  delete pendingMove.value[id];
  try {
    const opp = store.state.opportunities.byId[id];
    const stageId = opp?.pipeline_stage_id;
    await store.dispatch('opportunities/setStatus', { id, status });
    if (stageId) {
      store.dispatch('pipelineStages/fetchAggregates', { stageIds: [stageId] });
    }
  } catch (error) {
    if (
      error.response?.status === 422 &&
      error.response?.data?.missing_required_fields
    ) {
      const missing = error.response.data.missing_required_fields;
      closingRequirementsModalData.value = {
        opportunity: store.state.opportunities.byId[id],
        outcome: status,
        initialMissingFields: missing,
      };
      isClosingRequirementsModalOpen.value = true;
    }
  }
};

const isRequirementsModalOpen = ref(false);
const requirementsModalData = ref({});

const closeRequirementsModal = () => {
  isRequirementsModalOpen.value = false;
  requirementsModalData.value = {};
};

const executeMoveCard = async (id, move) => {
  const { fromStageId, toStageId, toIndex } = move;
  try {
    await store.dispatch('opportunities/moveCard', {
      id,
      fromStageId,
      toStageId,
      toIndex,
    });
    store.dispatch('pipelineStages/fetchAggregates', {
      stageIds: [fromStageId, toStageId],
    });
  } catch (error) {
    if (
      error.response?.status === 422 &&
      error.response?.data?.missing_required_fields
    ) {
      const missing = error.response.data.missing_required_fields;
      requirementsModalData.value = {
        opportunity: store.state.opportunities.byId[id],
        destinationStageId: move.toStageId,
        toIndex: move.toIndex,
        initialMissingFields: missing,
      };
      isRequirementsModalOpen.value = true;
    }
  }
};

// SortableJS mutates the DOM live as the card is dragged over other
// columns, ahead of any Vuex commit. Vue never re-diffs that DOM on its
// own, so once we know the move must NOT happen (or must be replaced by
// a different action), we force a commit-then-revert so Vue's reconciler
// visits the affected lists and wipes out SortableJS's raw DOM mutation.
const forceDomReconcile = (id, move) => {
  const previousStageIds = [
    ...(store.state.opportunities.idsByStage[move.fromStageId] || []),
  ];
  const previousToStageIds = [
    ...(store.state.opportunities.idsByStage[move.toStageId] || []),
  ];

  store.commit('opportunities/MOVE_CARD_OPTIMISTIC', {
    id,
    fromStageId: move.fromStageId,
    toStageId: move.toStageId,
    toIndex: move.toIndex,
  });

  setTimeout(() => {
    store.commit('opportunities/REVERT_MOVE_CARD', {
      id,
      previousStageId: move.fromStageId,
      previousStageIds,
      previousToStageIds,
      toStageId: move.toStageId,
    });
  }, 50);
};

const dispatchMoveIfComplete = id => {
  const move = pendingMove.value[id];
  if (
    move &&
    move.fromStageId !== undefined &&
    move.toStageId !== undefined &&
    move.toIndex !== undefined
  ) {
    const fromStage = store.getters['pipelineStages/stageById'](
      move.fromStageId
    );
    const toStage = store.getters['pipelineStages/stageById'](move.toStageId);
    const opportunity = store.state.opportunities.byId[id];

    const isForwardMove =
      (toStage?.position ?? Infinity) > (fromStage?.position ?? Infinity);

    if (!isForwardMove) {
      executeMoveCard(id, move);
      delete pendingMove.value[id];
      return;
    }

    let isMissingFields = false;
    const requiredDefs = toStage?.required_custom_attribute_definitions || [];
    const requiresDealValue = toStage?.requires_deal_value || false;
    const attrs = opportunity.custom_attributes || {};

    requiredDefs.forEach(def => {
      if (
        attrs[def.attribute_key] === undefined ||
        attrs[def.attribute_key] === null ||
        attrs[def.attribute_key] === ''
      ) {
        isMissingFields = true;
      }
    });

    if (
      requiresDealValue &&
      (opportunity.value === undefined ||
        opportunity.value === null ||
        opportunity.value === '')
    ) {
      isMissingFields = true;
    }

    if (isMissingFields) {
      forceDomReconcile(id, move);

      requirementsModalData.value = {
        opportunity,
        destinationStageId: move.toStageId,
        toIndex: move.toIndex,
      };
      isRequirementsModalOpen.value = true;
    } else {
      executeMoveCard(id, move);
    }

    delete pendingMove.value[id];
  }
};

// Only bookkeeping here: SortableJS fires these live as the card transits
// over other columns during the drag, well before the user actually drops
// it. Committing here would apply a move the user never intended (e.g. when
// they continue on to drop on the status bar instead). The real decision
// happens once the drag actually ends, in onDragEnd.
const onCardRemoved = ({ id, fromStageId }) => {
  if (!pendingMove.value[id]) pendingMove.value[id] = {};
  if (pendingMove.value[id].fromStageId === undefined) {
    pendingMove.value[id].fromStageId = fromStageId;
  }
};

const onCardAdded = ({ id, toStageId, toIndex }) => {
  if (!pendingMove.value[id]) pendingMove.value[id] = {};
  pendingMove.value[id].toStageId = toStageId;
  pendingMove.value[id].toIndex = toIndex;
};

const onStatusBarDrop = status => {
  const id = draggedCardId.value;
  if (!id) return;
  statusBarHandledId.value = id;
  // onStatusChanged deletes pendingMove.value[id] synchronously, and the
  // native `drop` event fires before `dragend`, so onDragEnd would find it
  // already gone. Snapshot it now while it's still there.
  statusBarPendingMove.value = pendingMove.value[id];
  onStatusChanged({ id, status });
};

const onDragEnd = () => {
  const id = draggedCardId.value;
  isCardDragging.value = false;
  draggedCardId.value = null;

  if (!id) return;

  if (statusBarHandledId.value === id) {
    statusBarHandledId.value = null;
    const move = statusBarPendingMove.value;
    statusBarPendingMove.value = null;
    if (
      move &&
      move.fromStageId !== undefined &&
      move.toStageId !== undefined
    ) {
      forceDomReconcile(id, move);
    }
    delete pendingMove.value[id];
    return;
  }

  dispatchMoveIfComplete(id);
};

const onCardClick = opportunityId => {
  emit('cardClick', opportunityId);
};

const boardContainerRef = ref(null);
const isPanning = ref(false);
let startX = 0;
let initialScrollLeft = 0;

const onGlobalMouseMove = e => {
  if (!isPanning.value || !boardContainerRef.value) return;
  const x = e.pageX - boardContainerRef.value.offsetLeft;
  const walk = x - startX;
  boardContainerRef.value.scrollLeft = initialScrollLeft - walk;
};

const onGlobalMouseUp = () => {
  if (isPanning.value) {
    isPanning.value = false;
    window.removeEventListener('mousemove', onGlobalMouseMove);
    window.removeEventListener('mouseup', onGlobalMouseUp);
  }
};

const onBoardMouseDown = e => {
  if (e.button !== 0 || isCardDragging.value || !boardContainerRef.value)
    return;

  const target = e.target;
  const interactiveTarget = target.closest(
    'button, a, input, textarea, select, [role="button"], .kanban-card, [data-draggable="true"]'
  );
  if (interactiveTarget) return;

  isPanning.value = true;
  startX = e.pageX - boardContainerRef.value.offsetLeft;
  initialScrollLeft = boardContainerRef.value.scrollLeft;

  window.addEventListener('mousemove', onGlobalMouseMove);
  window.addEventListener('mouseup', onGlobalMouseUp);
};

onUnmounted(() => {
  window.removeEventListener('mousemove', onGlobalMouseMove);
  window.removeEventListener('mouseup', onGlobalMouseUp);
});
</script>

<template>
  <div
    class="flex flex-col h-full w-full overflow-hidden bg-n-slate-1 relative"
  >
    <div
      ref="boardContainerRef"
      class="flex flex-grow overflow-x-auto p-4 gap-4 [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden"
      :class="{
        'cursor-grab': !isPanning && !isCardDragging,
        'cursor-grabbing select-none': isPanning,
      }"
      @mousedown="onBoardMouseDown"
    >
      <KanbanColumn
        v-for="stage in stages"
        :key="stage.id"
        :stage="stage"
        :filters="filters"
        :is-status-bar-hovered="isStatusBarHovered"
        @card-added="onCardAdded"
        @card-removed="onCardRemoved"
        @card-click="onCardClick"
        @status-changed="onStatusChanged"
        @drag-start="onDragStart"
        @drag-end="onDragEnd"
        @add-card="openCreateModal"
        @complete-fields="openBackfillModal"
        @edit-card="openBackfillModal"
      />

      <!-- Empty State for Board -->
      <div
        v-if="stages.length === 0"
        class="flex flex-col items-center justify-center py-12 w-full h-full"
      >
        <p class="text-n-slate-11 text-base mb-4">
          {{ $t('OPPORTUNITIES.LIST.EMPTY_STATE') }}
        </p>
        <Button
          size="small"
          color-scheme="primary"
          @click="store.dispatch('pipelineStages/fetch')"
        >
          {{ $t('OPPORTUNITIES.LIST.RETRY') }}
        </Button>
      </div>
    </div>

    <KanbanStatusBar
      v-show="isCardDragging"
      :is-dragging="isCardDragging"
      @drop="onStatusBarDrop"
      @hover-state="isStatusBarHovered = $event"
    />

    <OpportunityCreateModal
      v-if="isCreateModalOpen"
      :default-stage-id="modalDefaultStageId"
      @created="
        opp =>
          store.dispatch('pipelineStages/fetchAggregates', {
            stageIds: [opp.pipeline_stage_id],
          })
      "
      @close="closeCreateModal"
    />

    <OpportunityBackfillModal
      v-if="isBackfillModalOpen"
      :opportunity-id="backfillOpportunityId"
      @updated="
        opp =>
          store.dispatch('pipelineStages/fetchAggregates', {
            stageIds: [opp.pipeline_stage_id],
          })
      "
      @close="closeBackfillModal"
    />

    <StageTransitionRequirementsModal
      v-if="isRequirementsModalOpen"
      :opportunity="requirementsModalData.opportunity"
      :destination-stage-id="requirementsModalData.destinationStageId"
      :to-index="requirementsModalData.toIndex"
      :initial-missing-fields="requirementsModalData.initialMissingFields"
      @close="closeRequirementsModal"
    />

    <ClosingRequirementsModal
      v-if="isClosingRequirementsModalOpen"
      :opportunity="closingRequirementsModalData.opportunity"
      :outcome="closingRequirementsModalData.outcome"
      :initial-missing-fields="
        closingRequirementsModalData.initialMissingFields
      "
      @close="closeClosingRequirementsModal"
    />
  </div>
</template>

<style scoped>
.slide-right-enter-active,
.slide-right-leave-active {
  transition: transform 0.3s ease-out;
}

.slide-right-enter-from,
.slide-right-leave-to {
  transform: translateX(100%);
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
