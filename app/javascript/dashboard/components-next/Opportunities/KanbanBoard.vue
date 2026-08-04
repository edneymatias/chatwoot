<script setup>
import { computed, ref, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import KanbanColumn from './KanbanColumn.vue';
import KanbanStatusBar from './KanbanStatusBar.vue';
import OpportunityCreateModal from './OpportunityCreateModal.vue';
import OpportunityBackfillModal from './OpportunityBackfillModal.vue';
import StageTransitionRequirementsModal from './StageTransitionRequirementsModal.vue';
import ClosingRequirementsModal from './ClosingRequirementsModal.vue';

const emit = defineEmits(['cardClick']);

const isCardDragging = ref(false);

const onDragStart = () => {
  isCardDragging.value = true;
};

const onDragEnd = () => {
  isCardDragging.value = false;
};

const store = useStore();
const route = useRoute();
const router = useRouter();

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
  store.dispatch('pipelineCardFieldConfigs/fetch');
  store.dispatch('pipelineCurrencySetting/fetch');
});

const pendingMove = ref({});

const isClosingRequirementsModalOpen = ref(false);
const closingRequirementsModalData = ref({});

const closeClosingRequirementsModal = () => {
  isClosingRequirementsModalOpen.value = false;
  closingRequirementsModalData.value = {};
};

const onStatusChanged = async ({ id, status }) => {
  try {
    await store.dispatch('opportunities/setStatus', { id, status });
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
  try {
    await store.dispatch('opportunities/moveCard', {
      id,
      fromStageId: move.fromStageId,
      toStageId: move.toStageId,
      toIndex: move.toIndex,
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
        @drag-start="onDragStart"
        @drag-end="onDragEnd"
        @add-card="openCreateModal"
        @complete-fields="openBackfillModal"
        @edit-card="openBackfillModal"
      />
    </div>

    <KanbanStatusBar
      v-show="isCardDragging"
      :is-dragging="isCardDragging"
      @status-changed="onStatusChanged"
    />

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

    <OpportunityBackfillModal
      v-if="isBackfillModalOpen"
      :opportunity-id="backfillOpportunityId"
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

    <router-view v-slot="{ Component }">
      <transition name="slide-right">
        <component :is="Component" v-if="Component" />
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
