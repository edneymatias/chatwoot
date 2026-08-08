<script setup>
import { ref, watch, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import KanbanBoard from 'dashboard/components-next/Opportunities/KanbanBoard.vue';
import OpportunityListView from './components/OpportunityListView.vue';
import OpportunitiesViewBar from './components/OpportunitiesViewBar.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();

onMounted(async () => {
  await store.dispatch('pipelineStages/fetch');
  store.dispatch('pipelineCardFieldConfigs/fetch');
  store.dispatch('pipelineCurrencySetting/fetch');

  const stages = store.getters['pipelineStages/stagesSortedByPosition'];
  if (stages?.length) {
    store.dispatch('pipelineStages/fetchAggregates', {
      stageIds: stages.map(s => s.id),
    });
  }
});

const viewMode = ref(
  localStorage.getItem('opportunities_view_mode') || 'kanban'
);

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
    class="flex flex-col h-full w-full bg-n-slate-1 relative overflow-hidden"
  >
    <OpportunitiesViewBar v-model="viewMode" />

    <div class="flex-grow overflow-hidden relative">
      <KanbanBoard v-if="viewMode === 'kanban'" key="kanban" />
      <OpportunityListView v-else key="list" @row-click="handleRowClick" />

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
