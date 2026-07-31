<script setup>
import { computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import Draggable from 'vuedraggable';
import KanbanCard from './KanbanCard.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits([
  'cardRemoved',
  'cardAdded',
  'cardClick',
  'statusChanged',
]);

const store = useStore();

const cards = computed(() =>
  store.getters['opportunities/cardsForStage'](props.stage.id)
);
const hasMore = computed(() =>
  store.getters['opportunities/hasMoreForStage'](props.stage.id)
);
const isFetching = computed(() =>
  store.getters['opportunities/isFetchingForStage'](props.stage.id)
);
const pagination = computed(
  () =>
    store.state.opportunities.pagination.byStage[props.stage.id] || { page: 1 }
);

const loadCards = (page = 1) => {
  if (isFetching.value) return;
  store.dispatch('opportunities/fetchForStage', {
    stageId: props.stage.id,
    page,
  });
};

onMounted(() => {
  loadCards(1);
});

const onObserved = () => {
  if (hasMore.value && !isFetching.value) {
    loadCards(pagination.value.page + 1);
  }
};

const onChange = event => {
  if (event.removed) {
    emit('cardRemoved', {
      id: event.removed.element.id,
      fromStageId: props.stage.id,
    });
  }
  if (event.added) {
    emit('cardAdded', {
      id: event.added.element.id,
      toStageId: props.stage.id,
      toIndex: event.added.newIndex,
    });
  }
};
</script>

<template>
  <div
    class="flex flex-col w-[300px] min-w-[300px] bg-n-surface-2 border border-n-weak rounded-lg overflow-hidden h-full"
  >
    <div class="flex items-center justify-between p-3 border-b border-n-weak">
      <h2
        class="text-n-slate-12 font-medium text-sm truncate"
        :title="stage.name"
      >
        {{ stage.name }}
      </h2>
      <span
        class="text-xs font-medium text-n-slate-11 bg-n-slate-3 px-2 py-0.5 rounded-full"
      >
        {{ cards.length }}
      </span>
    </div>

    <div class="flex-1 overflow-y-auto p-2 min-h-0">
      <Draggable
        :model-value="cards"
        item-key="id"
        group="kanban-cards"
        class="min-h-[50px] h-full flex flex-col gap-2"
        ghost-class="opacity-50"
        @change="onChange"
      >
        <template #item="{ element }">
          <KanbanCard
            :opportunity="element"
            @click="$emit('cardClick', $event)"
            @status-changed="$emit('statusChanged', $event)"
          />
        </template>
      </Draggable>

      <IntersectionObserver v-if="hasMore" @observed="onObserved" />
      <div v-if="isFetching" class="flex justify-center p-4">
        <span class="text-xs text-n-slate-11">{{
          $t('OPPORTUNITIES.BOARD.LOADING')
        }}</span>
      </div>
    </div>
  </div>
</template>
