<script setup>
import { computed, ref, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import KanbanColumn from './KanbanColumn.vue';
import OpportunityCreateModal from './OpportunityCreateModal.vue';

const emit = defineEmits(['cardClick']);

const store = useStore();
const route = useRoute();
const router = useRouter();

const isCreateModalOpen = ref(false);
const modalDefaultStageId = ref(null);

const openCreateModal = stageId => {
  modalDefaultStageId.value = stageId;
  isCreateModalOpen.value = true;
};

const closeCreateModal = () => {
  isCreateModalOpen.value = false;
  modalDefaultStageId.value = null;
};

const isDrawerOpen = computed(
  () => route.name === 'opportunities_conversation'
);

const closeDrawer = () => {
  if (isDrawerOpen.value) {
    router.push({
      name: 'opportunities_index',
      params: { accountId: route.params.accountId },
    });
  }
};

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);

onMounted(() => {
  store.dispatch('pipelineStages/fetch');
});

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

const onCardClick = opportunityId => {
  emit('cardClick', opportunityId);
};
</script>

<template>
  <div class="flex h-full w-full overflow-hidden bg-n-slate-1 relative">
    <div class="flex flex-grow overflow-x-auto p-4 gap-4">
      <KanbanColumn
        v-for="stage in stages"
        :key="stage.id"
        :stage="stage"
        @card-added="onCardAdded"
        @card-removed="onCardRemoved"
        @card-click="onCardClick"
        @status-changed="onStatusChanged"
        @add-card="openCreateModal"
      />
    </div>

    <!-- Backdrop for Drawer -->
    <transition name="fade">
      <div
        v-if="isDrawerOpen"
        class="absolute inset-0 z-[39] bg-black/20 dark:bg-black/40 backdrop-blur-sm transition-all"
        @click="closeDrawer"
      />
    </transition>

    <OpportunityCreateModal
      v-if="isCreateModalOpen"
      :default-stage-id="modalDefaultStageId"
      @close="closeCreateModal"
    />

    <router-view v-slot="{ Component }">
      <transition name="slide-right">
        <component :is="Component" />
      </transition>
    </router-view>
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
