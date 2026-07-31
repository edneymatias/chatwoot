<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import KanbanColumn from './KanbanColumn.vue';
import OpportunityDetailView from './OpportunityDetailView.vue';

const emit = defineEmits(['cardClick']);

const store = useStore();

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);

const pendingMove = ref({});
const selectedOpportunityId = ref(null);

const onStatusChanged = ({ id, status }) => {
  store.dispatch('opportunities/setStatus', { id, status });
};

const dispatchMoveIfComplete = id => {
  const move = pendingMove.value[id];
  if (
    move &&
    move.fromStageId !== undefined &&
    move.toStageId !== undefined &&
    move.toIndex !== undefined
  ) {
    store.dispatch('opportunities/moveCard', {
      id,
      fromStageId: move.fromStageId,
      toStageId: move.toStageId,
      toIndex: move.toIndex,
    });
    delete pendingMove.value[id];
  }
};

const onCardRemoved = ({ id, fromStageId }) => {
  if (!pendingMove.value[id]) pendingMove.value[id] = {};
  pendingMove.value[id].fromStageId = fromStageId;
  dispatchMoveIfComplete(id);
};

const onCardAdded = ({ id, toStageId, toIndex }) => {
  if (!pendingMove.value[id]) pendingMove.value[id] = {};
  pendingMove.value[id].toStageId = toStageId;
  pendingMove.value[id].toIndex = toIndex;
  dispatchMoveIfComplete(id);
};

const onCardClick = opportunityId => {
  selectedOpportunityId.value = opportunityId;
  emit('cardClick', opportunityId);
};
</script>

<template>
  <div class="flex h-full w-full overflow-hidden bg-n-slate-1">
    <div class="flex flex-grow overflow-x-auto p-4 gap-4">
      <KanbanColumn
        v-for="stage in stages"
        :key="stage.id"
        :stage="stage"
        @card-added="onCardAdded"
        @card-removed="onCardRemoved"
        @card-click="onCardClick"
        @status-changed="onStatusChanged"
      />
    </div>
    <OpportunityDetailView
      v-if="selectedOpportunityId"
      :opportunity-id="selectedOpportunityId"
      @close="selectedOpportunityId = null"
      @status-changed="onStatusChanged"
    />
  </div>
</template>
