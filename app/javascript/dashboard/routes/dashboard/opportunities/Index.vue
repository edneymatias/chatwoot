<script setup>
import { ref, watch, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import KanbanBoard from 'dashboard/components-next/Opportunities/KanbanBoard.vue';
import OpportunityListView from './components/OpportunityListView.vue';
import OpportunitiesViewBar from './components/OpportunitiesViewBar.vue';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useEmitter } from 'dashboard/composables/emitter';

const route = useRoute();
const router = useRouter();
const store = useStore();

const fetchInitialData = async () => {
  try {
    await store.dispatch('pipelineStages/fetch');
    store.dispatch('pipelineCardFieldConfigs/fetch');
    store.dispatch('pipelineCurrencySetting/fetch');
    store.dispatch('agents/get');
    store.dispatch('attributes/get');

    const stages = store.getters['pipelineStages/stagesSortedByPosition'];
    if (stages?.length) {
      store.dispatch('pipelineStages/fetchAggregates', {
        stageIds: stages.map(s => s.id),
      });
    }
  } catch (error) {
    // Error is caught so it doesn't break the component
  }
};

onMounted(() => {
  fetchInitialData();
});

const viewMode = ref(
  localStorage.getItem('opportunities_view_mode') || 'kanban'
);

const filters = ref({});

useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, () => {
  const stages = store.getters['pipelineStages/stagesSortedByPosition'];
  if (!stages || stages.length === 0) {
    fetchInitialData();
  }

  if (viewMode.value === 'list') {
    store.dispatch('opportunities/fetchAll', {
      page: 1,
      filters: filters.value,
    });
  } else {
    // For Kanban, we can re-trigger column fetches by notifying the store
    // or just let the columns fetch if they didn't, but columns watch `filters`.
    // Re-fetching stages will trigger columns to render if they were empty.
  }
});

watch(viewMode, newVal => {
  localStorage.setItem('opportunities_view_mode', newVal);
});

const handleRowClick = opportunity => {
  if (!opportunity.origin_conversation_id) return;
  router.push({
    name: 'opportunities_conversation',
    params: {
      conversationId:
        opportunity.origin_conversation_display_id ||
        opportunity.origin_conversation_id,
    },
  });
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
</script>

<template>
  <div
    class="flex flex-col h-full w-full bg-n-background relative overflow-hidden"
  >
    <OpportunitiesViewBar v-model="viewMode" v-model:filters="filters" />

    <div class="flex-grow overflow-hidden relative">
      <KanbanBoard
        v-if="viewMode === 'kanban'"
        key="kanban"
        :filters="filters"
      />
      <OpportunityListView
        v-else
        key="list"
        :filters="filters"
        @row-click="handleRowClick"
      />

      <!-- Backdrop for Drawer -->
      <transition name="fade">
        <div
          v-if="isDrawerOpen"
          class="absolute inset-0 z-[39] bg-black/20 dark:bg-black/40 backdrop-blur-sm transition-all"
          @click="closeDrawer"
        />
      </transition>

      <router-view />
    </div>
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
