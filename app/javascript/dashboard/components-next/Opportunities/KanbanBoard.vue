<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import KanbanColumn from './KanbanColumn.vue';

defineEmits(['cardClick']);

const store = useStore();

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);

const pendingMove = ref({});

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
</script>

<template>
  <div class="flex h-full w-full overflow-x-auto p-4 gap-4 bg-n-slate-1">
    <KanbanColumn
      v-for="stage in stages"
      :key="stage.id"
      :stage="stage"
      @card-added="onCardAdded"
      @card-removed="onCardRemoved"
      @card-click="$emit('cardClick', $event)"
      @status-changed="onStatusChanged"
    />
  </div>
</template>
