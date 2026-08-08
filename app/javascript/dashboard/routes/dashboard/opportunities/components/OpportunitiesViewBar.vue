<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  modelValue: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);

const store = useStore();

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition'] || []
);

const currencyCode = computed(
  () => store.getters['pipelineCurrencySetting/getCurrency']
);

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
