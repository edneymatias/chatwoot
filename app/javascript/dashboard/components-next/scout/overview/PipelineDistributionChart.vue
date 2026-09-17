<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const props = defineProps({
  stages: {
    type: Array,
    default: () => [],
  },
  title: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();

const sortedStages = computed(() => {
  return [...(props.stages || [])].sort(
    (a, b) => (a.stage_position ?? 0) - (b.stage_position ?? 0)
  );
});

const totalOpportunities = computed(() => {
  return sortedStages.value.reduce((sum, s) => sum + (s.count || 0), 0);
});

const formatRate = count => {
  if (!totalOpportunities.value) return '0%';
  const rate = Math.round(((count || 0) / totalOpportunities.value) * 100);
  return `${rate}%`;
};

const headers = computed(() => [
  t('SCOUT.OVERVIEW.TABLES.STAGE'),
  t('SCOUT.OVERVIEW.TABLES.COUNT'),
  t('SCOUT.OVERVIEW.TABLES.PERCENTAGE'),
]);
</script>

<template>
  <div class="w-full border rounded-xl border-n-weak bg-n-solid-1">
    <div class="flex flex-col gap-1 px-5 py-4">
      <span class="text-heading-2 text-n-slate-12">
        {{ title || t('SCOUT.OVERVIEW.PIPELINE_DISTRIBUTION') }}
      </span>
      <span class="text-subheading text-n-slate-11">
        {{ t('SCOUT.OVERVIEW.PIPELINE_DISTRIBUTION_DESCRIPTION') }}
      </span>
    </div>

    <div
      v-if="sortedStages.length"
      class="overflow-x-auto border-t border-n-weak [&_th:first-child]:ps-5 [&_td:first-child]:ps-5 [&_th:last-child]:pe-5 [&_td:last-child]:pe-5"
    >
      <BaseTable :headers="headers" :items="sortedStages">
        <template #row="{ items }">
          <BaseTableRow
            v-for="stage in items"
            :key="stage.stage_id"
            :item="stage"
          >
            <template #default>
              <BaseTableCell class="font-medium text-n-slate-12">
                <span data-testid="stage-label">{{ stage.stage_name }}</span>
              </BaseTableCell>
              <BaseTableCell class="tabular-nums text-n-slate-11">
                <span data-testid="stage-count">{{ stage.count ?? 0 }}</span>
              </BaseTableCell>
              <BaseTableCell class="tabular-nums text-n-slate-11">
                {{ formatRate(stage.count) }}
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
  </div>
</template>
