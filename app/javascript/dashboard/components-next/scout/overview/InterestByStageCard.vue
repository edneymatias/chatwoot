<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const props = defineProps({
  interestData: {
    type: Object,
    default: () => ({ configured: false }),
  },
  scoutId: {
    type: [Number, String],
    default: null,
  },
  accountId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();

const isConfigured = computed(() => Boolean(props.interestData?.configured));

const cardTitle = computed(() => {
  if (isConfigured.value && props.interestData?.attribute_name) {
    return (
      t('SCOUT.OVERVIEW.INTEREST_BY_STAGE_NAME', {
        name: props.interestData.attribute_name,
      }) || `${props.interestData.attribute_name} by Stage`
    );
  }
  return t('SCOUT.OVERVIEW.INTEREST_BY_STAGE') || 'Interest by Stage';
});

const configureFunnelUrl = computed(() => {
  const acc = props.accountId || '';
  const sc = props.scoutId || '';
  return `/app/accounts/${acc}/scout/${sc}/funnel`;
});

const stagesData = computed(() => props.interestData?.data || []);

const headers = computed(() => [
  t('SCOUT.OVERVIEW.TABLES.STAGE'),
  t('SCOUT.OVERVIEW.TABLES.INTERESTS'),
  t('SCOUT.OVERVIEW.TABLES.TOTAL'),
]);

const stageTotal = breakdown => {
  if (!breakdown) return 0;
  return Object.values(breakdown).reduce((sum, val) => sum + (val || 0), 0);
};

const formatBreakdownEntries = breakdown => {
  if (!breakdown) return [];
  return Object.entries(breakdown).map(([key, count]) => ({
    key:
      key === 'null'
        ? t('SCOUT.OVERVIEW.INTEREST_UNSPECIFIED') || 'Sem interesse'
        : key,
    rawKey: key,
    count,
  }));
};
</script>

<template>
  <div class="w-full border rounded-xl border-n-weak bg-n-solid-1">
    <div class="flex flex-col gap-1 px-5 py-4">
      <span class="text-heading-2 text-n-slate-12">
        {{ cardTitle }}
      </span>
      <span class="text-subheading text-n-slate-11">
        {{ t('SCOUT.OVERVIEW.INTEREST_BY_STAGE_DESCRIPTION') }}
      </span>
    </div>

    <!-- When configured: render breakdown table per stage -->
    <div
      v-if="isConfigured && stagesData.length"
      class="overflow-x-auto border-t border-n-weak [&_th:first-child]:ps-5 [&_td:first-child]:ps-5 [&_th:last-child]:pe-5 [&_td:last-child]:pe-5"
    >
      <BaseTable :headers="headers" :items="stagesData">
        <template #row="{ items }">
          <BaseTableRow
            v-for="stage in items"
            :key="stage.stage_id"
            :item="stage"
          >
            <template #default>
              <!-- Stage Column -->
              <BaseTableCell class="font-medium text-n-slate-12 align-top">
                {{ stage.stage_name }}
              </BaseTableCell>

              <!-- Interests Breakdown Column -->
              <BaseTableCell class="align-top">
                <div
                  v-if="formatBreakdownEntries(stage.breakdown).length"
                  class="flex flex-wrap gap-1.5 py-0.5"
                >
                  <span
                    v-for="entry in formatBreakdownEntries(stage.breakdown)"
                    :key="entry.rawKey"
                    class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium bg-n-alpha-2 text-n-slate-12 border border-n-weak"
                  >
                    {{ entry.key }}: {{ entry.count }}
                  </span>
                </div>
                <span v-else class="text-xs text-n-slate-10">—</span>
              </BaseTableCell>
              <!-- Total Column -->
              <BaseTableCell class="tabular-nums text-n-slate-11 align-top">
                {{ stageTotal(stage.breakdown) }}
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>

    <!-- When unconfigured: explanatory notice and CTA -->
    <div
      v-else
      class="flex flex-col items-center justify-center p-8 text-center border-t border-n-weak"
    >
      <p class="text-sm text-n-slate-11 max-w-sm mb-4">
        {{
          t('SCOUT.OVERVIEW.INTEREST_NOT_CONFIGURED_DESC') ||
          'Configure an interest field to track lead interests across your sales funnel.'
        }}
      </p>
      <a
        data-testid="configure-interest-cta"
        :href="configureFunnelUrl"
        class="inline-flex items-center justify-center px-4 py-2 text-xs font-medium rounded-lg bg-primary-500 hover:bg-primary-600 text-white transition-colors"
      >
        {{
          t('SCOUT.OVERVIEW.CONFIGURE_INTEREST_BTN') ||
          'Configure Interest Field'
        }}
      </a>
    </div>
  </div>
</template>
