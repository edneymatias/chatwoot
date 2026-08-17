<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import Draggable from 'vuedraggable';
import KanbanCard from './KanbanCard.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
  filters: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits([
  'cardRemoved',
  'cardAdded',
  'cardClick',
  'statusChanged',
  'addCard',
  'completeFields',
  'editCard',
  'dragStart',
  'dragEnd',
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
    filters: props.filters,
  });
};

watch(
  () => props.filters,
  () => {
    loadCards(1);
  },
  { deep: true }
);

onMounted(() => {
  loadCards(1);
});

const onObserved = () => {
  if (hasMore.value && !isFetching.value) {
    loadCards(pagination.value.page + 1);
  }
};

const onDragStart = evt => {
  const id = cards.value[evt.oldIndex]?.id;
  emit('dragStart', id);
};

const onChange = event => {
  if (event.removed) {
    emit('cardRemoved', {
      id: event.removed.element.id,
      fromStageId: props.stage.id,
      fromIndex: event.removed.oldIndex,
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

const currencyCode = computed(
  () => store.getters['pipelineCurrencySetting/getCurrency']
);

const isInfoExpanded = ref(false);

const hasDescription = computed(() => {
  if (!props.stage.description) return false;
  const trimmed = props.stage.description.trim();
  return trimmed.length > 0 && trimmed !== '<p></p>';
});

const displayTotal = computed(() => {
  if (
    props.stage.open_count === undefined ||
    props.stage.open_value_sum === undefined
  ) {
    return null;
  }
  if (props.stage.total_display_mode === 'count') {
    return props.stage.open_count || 0;
  }

  return formatCurrencyAmount(
    props.stage.open_value_sum || 0,
    currencyCode.value,
    true
  );
});
</script>

<template>
  <div
    class="flex flex-col w-[300px] min-w-[300px] bg-n-surface-2 border border-n-weak rounded-lg overflow-hidden h-full"
  >
    <div
      class="flex items-center justify-between p-3 border-b-[3px] border-n-weak"
      :style="
        stage.accent_color ? { borderBottomColor: stage.accent_color } : {}
      "
    >
      <div class="flex items-center gap-1.5 min-w-0 flex-1 mr-2">
        <button
          type="button"
          class="flex-shrink-0 flex items-center justify-center size-5 rounded-full text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-3 dark:hover:bg-n-solid-3 transition-colors"
          :class="{
            'text-n-brand-9 bg-n-alpha-2': isInfoExpanded,
          }"
          :title="$t('OPPORTUNITIES.BOARD.STAGE_INFO.INFO_TOOLTIP')"
          :aria-label="$t('OPPORTUNITIES.BOARD.STAGE_INFO.INFO_TOOLTIP')"
          @click="isInfoExpanded = !isInfoExpanded"
        >
          <span class="size-4 shrink-0 i-lucide-info" />
        </button>
        <h2
          class="text-n-slate-12 font-medium text-sm truncate"
          :title="stage.name"
        >
          {{ stage.name }}
        </h2>
      </div>
      <div class="flex items-center gap-2 flex-shrink-0">
        <span
          v-if="displayTotal !== null"
          class="text-xs font-medium text-n-slate-11 bg-n-slate-3 px-2 py-0.5 rounded-full"
        >
          {{ displayTotal }}
        </span>
        <button
          class="flex items-center justify-center p-1 rounded hover:bg-n-slate-3 text-n-slate-11 hover:text-n-slate-12 transition-colors"
          :title="$t('OPPORTUNITIES.CREATE_MODAL.TITLE')"
          @click="$emit('addCard', stage.id)"
        >
          <fluent-icon icon="add" size="14" />
        </button>
      </div>
    </div>

    <div
      v-if="isInfoExpanded"
      class="p-3 border-b border-n-weak bg-n-surface-1 text-xs text-n-slate-12 shrink-0 [&_ul]:list-disc [&_ul]:pl-4 [&_ol]:list-decimal [&_ol]:pl-4 [&_p]:mb-1 [&_p:last-child]:mb-0 [&_s]:line-through [&_u]:underline"
    >
      <div v-if="hasDescription" v-dompurify-html="stage.description" />
      <p v-else class="text-n-slate-11 italic m-0">
        {{ $t('OPPORTUNITIES.BOARD.STAGE_INFO.EMPTY_STATE') }}
      </p>
    </div>

    <Draggable
      :model-value="cards"
      item-key="id"
      group="kanban-cards"
      class="flex-1 overflow-y-auto p-2 min-h-0 flex flex-col gap-2"
      ghost-class="opacity-50"
      filter=".is-closed"
      :sort="false"
      @change="onChange"
      @start="onDragStart"
      @end="$emit('dragEnd', $event)"
    >
      <template #item="{ element }">
        <KanbanCard
          :opportunity="element"
          class="kanban-card"
          :class="{ 'is-closed': element.status !== 'open' }"
          @click="$emit('cardClick', $event)"
          @status-changed="$emit('statusChanged', $event)"
          @complete-fields="$emit('completeFields', $event)"
          @edit-card="$emit('editCard', $event)"
        />
      </template>

      <template #footer>
        <IntersectionObserver v-if="hasMore" @observed="onObserved" />
        <div v-if="isFetching" class="flex justify-center p-4">
          <span class="text-xs text-n-slate-11">{{
            $t('OPPORTUNITIES.BOARD.LOADING')
          }}</span>
        </div>
      </template>
    </Draggable>
  </div>
</template>
