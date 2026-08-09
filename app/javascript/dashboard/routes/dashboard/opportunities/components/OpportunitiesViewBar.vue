<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import OpportunitiesFilter from 'dashboard/components-next/filter/OpportunitiesFilter.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  modelValue: {
    type: String,
    required: true,
  },
  filters: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['update:modelValue', 'update:filters']);

const updateFilter = (key, value) => {
  emit('update:filters', { ...props.filters, [key]: value });
};

const store = useStore();

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition'] || []
);

const currencyCode = computed(
  () => store.getters['pipelineCurrencySetting/getCurrency']
);

const isFilterModalOpen = ref(false);
const activeFilters = ref([
  {
    attributeKey: 'status',
    filterOperator: 'equal_to',
    values: '',
    queryOperator: 'and',
    attributeModel: 'standard',
  },
]);

const onApplyFilter = newFilters => {
  activeFilters.value = newFilters;
  emit('update:filters', {
    ...props.filters,
    payload: JSON.stringify(newFilters),
  });
  isFilterModalOpen.value = false;
};

const onClearFilters = () => {
  activeFilters.value = [
    {
      attributeKey: 'status',
      filterOperator: 'equal_to',
      values: '',
      queryOperator: 'and',
      attributeModel: 'standard',
    },
  ];
  const { payload, ...restFilters } = props.filters;
  emit('update:filters', restFilters);
  isFilterModalOpen.value = false;
};

const sortOptions = [
  { label: 'Sort: Created At', value: 'created_at_desc' },
  { label: 'Sort: Value (High to Low)', value: 'value_desc' },
  { label: 'Sort: Value (Low to High)', value: 'value_asc' },
  { label: 'Sort: Last Activity', value: 'last_activity' },
];

const totalLeadCount = computed(() => {
  return stages.value.reduce((acc, stage) => acc + (stage.open_count || 0), 0);
});

const totalValue = computed(() => {
  const sum = stages.value.reduce((acc, stage) => {
    return acc + (parseFloat(stage.open_value_sum) || 0);
  }, 0);

  return formatCurrencyAmount(sum, currencyCode.value, true);
});

const setViewMode = mode => {
  emit('update:modelValue', mode);
};
</script>

<template>
  <div
    class="flex items-center justify-between p-4 bg-white border-b border-n-slate-3 shadow-sm z-10 shrink-0"
  >
    <div class="flex items-center gap-4">
      <h1 class="text-heading-1 font-medium text-n-slate-12 m-0">
        {{ $t('OPPORTUNITIES.HEADER') }}
      </h1>

      <div class="flex items-center gap-2 text-sm text-n-slate-11">
        <div class="flex items-center gap-1 bg-n-slate-2 px-2 py-1 rounded">
          <span>{{
            $t('OPPORTUNITIES.LEAD_COUNT', { count: totalLeadCount })
          }}</span>
        </div>
        <div class="flex items-center gap-1 bg-n-slate-2 px-2 py-1 rounded">
          <span class="font-medium text-n-slate-12">{{ totalValue }}</span>
        </div>
      </div>
    </div>

    <div class="flex items-center gap-2">
      <!-- Search Input -->
      <div class="w-64 relative mr-2">
        <Input
          :model-value="filters.q || ''"
          size="sm"
          placeholder="Search opportunities..."
          custom-input-class="!pl-8"
          @update:model-value="updateFilter('q', $event)"
        />
        <Icon
          icon="i-lucide-search"
          class="absolute left-2.5 top-2 w-4 h-4 text-n-slate-10 pointer-events-none"
        />
      </div>

      <div class="relative">
        <Button
          id="toggleOpportunitiesFilterButton"
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-list-filter"
          @click="isFilterModalOpen = !isFilterModalOpen"
        />
        <div v-if="isFilterModalOpen" class="absolute right-0 top-10 z-[100]">
          <OpportunitiesFilter
            v-model="activeFilters"
            @apply-filter="onApplyFilter"
            @clear-filters="onClearFilters"
            @close="isFilterModalOpen = false"
          />
        </div>
      </div>

      <Select
        :model-value="filters.sort_by || 'created_at_desc'"
        :options="sortOptions"
        @update:model-value="updateFilter('sort_by', $event)"
      />

      <!-- Toggle buttons -->
      <div
        class="flex items-center bg-n-slate-2 rounded-lg p-0.5 border border-n-slate-3"
      >
        <button
          v-tooltip.bottom="'Kanban'"
          class="flex items-center justify-center p-1.5 rounded-md transition-colors"
          :class="[
            modelValue === 'kanban'
              ? 'bg-white text-n-slate-12 shadow-sm'
              : 'text-n-slate-10 hover:text-n-slate-12',
          ]"
          @click="setViewMode('kanban')"
        >
          <Icon icon="i-lucide-kanban" class="w-4 h-4" />
        </button>
        <button
          v-tooltip.bottom="'Lista'"
          class="flex items-center justify-center p-1.5 rounded-md transition-colors"
          :class="[
            modelValue === 'list'
              ? 'bg-white text-n-slate-12 shadow-sm'
              : 'text-n-slate-10 hover:text-n-slate-12',
          ]"
          @click="setViewMode('list')"
        >
          <Icon icon="i-lucide-menu" class="w-4 h-4" />
        </button>
      </div>

      <div class="w-px h-6 bg-n-slate-3 mx-1" />

      <!-- Create Button -->
      <Button
        v-tooltip.bottom="'Coming soon'"
        variant="solid"
        color="blue"
        size="md"
        icon="i-lucide-plus"
        :label="$t('OPPORTUNITIES.CREATE_MODAL.SUBMIT')"
        disabled
      />
    </div>
  </div>
</template>
