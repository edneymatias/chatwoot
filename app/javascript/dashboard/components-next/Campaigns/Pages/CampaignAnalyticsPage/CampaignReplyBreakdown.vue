<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

defineProps({
  breakdown: {
    type: Array,
    default: () => [],
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const headers = computed(() => [
  t('CAMPAIGN.WHATSAPP.ANALYTICS.REPLY_BREAKDOWN.BUTTON_LABEL'),
  t('CAMPAIGN.WHATSAPP.ANALYTICS.REPLY_BREAKDOWN.TOTAL_CLICKS'),
  t('CAMPAIGN.WHATSAPP.ANALYTICS.REPLY_BREAKDOWN.CLICK_RATE'),
]);

const displayLabel = label => {
  if (label === 'other') {
    return t('CAMPAIGN.WHATSAPP.ANALYTICS.REPLY_BREAKDOWN.OTHER_REPLIES');
  }
  return label;
};

const formatRate = rate => `${Math.round((rate || 0) * 100)}%`;
</script>

<template>
  <div class="w-full border rounded-xl border-n-weak bg-n-solid-1">
    <div class="flex flex-col gap-1 px-5 py-4">
      <span class="text-heading-2 text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.ANALYTICS.REPLY_BREAKDOWN.TITLE') }}
      </span>
      <span class="text-subheading text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.ANALYTICS.REPLY_BREAKDOWN.DESCRIPTION') }}
      </span>
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center py-12 border-t text-n-slate-11 border-n-weak"
    >
      <Spinner />
    </div>
    <div
      v-else-if="breakdown.length"
      class="overflow-x-auto [&_th:first-child]:ps-5 [&_td:first-child]:ps-5 [&_th:last-child]:pe-5 [&_td:last-child]:pe-5"
    >
      <BaseTable :headers="headers" :items="breakdown">
        <template #row="{ items }">
          <BaseTableRow v-for="row in items" :key="row.label" :item="row">
            <template #default>
              <BaseTableCell class="font-medium text-n-slate-12">
                {{ displayLabel(row.label) }}
              </BaseTableCell>
              <BaseTableCell class="tabular-nums text-n-slate-11">
                {{ row.total_clicks }}
              </BaseTableCell>
              <BaseTableCell class="tabular-nums text-n-slate-11">
                {{ formatRate(row.click_rate) }}
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
  </div>
</template>
