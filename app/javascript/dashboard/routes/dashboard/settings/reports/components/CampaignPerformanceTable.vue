<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const props = defineProps({
  reportData: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();
const currentTab = ref('ads');

const tabs = computed(() => [
  { key: 'ads', label: t('CAMPAIGN_PERFORMANCE_REPORTS.TABS.ADS') },
  { key: 'adsets', label: t('CAMPAIGN_PERFORMANCE_REPORTS.TABS.ADSETS') },
  { key: 'campaigns', label: t('CAMPAIGN_PERFORMANCE_REPORTS.TABS.CAMPAIGNS') },
]);

const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.key === currentTab.value)
);

const handleTabChange = tab => {
  if (tab.key === currentTab.value) return;
  currentTab.value = tab.key;
};

const formatMilestoneValue = (count, pct) => `${count} (${pct}%)`;

const hasMilestone = computed(() => {
  return (
    props.reportData?.summary?.milestone_stage_name &&
    props.reportData?.summary?.milestone_count !== undefined
  );
});

const milestoneHeader = computed(() => {
  return (
    props.reportData?.summary?.milestone_stage_name ||
    t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.MILESTONE_RATE')
  );
});

const rows = computed(() => {
  if (!props.reportData) return [];
  if (currentTab.value === 'ads') {
    return props.reportData.by_ad || [];
  }
  if (currentTab.value === 'adsets') {
    return props.reportData.by_adset || [];
  }
  if (currentTab.value === 'campaigns') {
    return props.reportData.by_campaign || [];
  }
  return [];
});

const headers = computed(() => {
  const list = [t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.CAMPAIGN')];

  if (currentTab.value === 'adsets' || currentTab.value === 'ads') {
    list.push(t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.ADSET'));
  }
  if (currentTab.value === 'ads') {
    list.push(t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.AD'));
  }

  list.push(t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.LEADS'));

  if (hasMilestone.value) {
    list.push(milestoneHeader.value);
  }

  list.push(t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.WON'));
  list.push(t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.LOST'));

  return list;
});

const textColumnCount = computed(() => {
  if (currentTab.value === 'ads') return 3;
  if (currentTab.value === 'adsets') return 2;
  return 1;
});

const metricHeaderIndexes = computed(() => {
  const indexes = [];
  for (let i = textColumnCount.value; i < headers.value.length; i += 1) {
    indexes.push(i);
  }
  return indexes;
});

const isEmpty = computed(() => rows.value.length === 0);
</script>

<template>
  <div class="w-full border rounded-xl border-n-weak bg-n-solid-1">
    <div
      class="flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:gap-4"
    >
      <span class="text-heading-2 text-n-slate-12">
        {{ t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.TITLE') }}
      </span>
      <div class="min-w-0 p-1 -m-1 overflow-x-auto no-scrollbar">
        <TabBar
          :tabs="tabs"
          :initial-active-tab="activeTabIndex"
          @tab-changed="handleTabChange"
        />
      </div>
    </div>

    <div
      class="overflow-x-auto [&_th:first-child]:ps-5 [&_td:first-child]:ps-5 [&_th:last-child]:pe-5 [&_td:last-child]:pe-5"
      :class="{ 'border-t border-n-weak': isEmpty }"
    >
      <BaseTable
        :headers="headers"
        :items="rows"
        :no-data-message="t('CAMPAIGN_PERFORMANCE_REPORTS.TABLE.EMPTY')"
      >
        <template
          v-for="index in metricHeaderIndexes"
          :key="index"
          #[`header-${index}`]="{ header }"
        >
          <div class="text-end">
            {{ header }}
          </div>
        </template>
        <template #row="{ items }">
          <BaseTableRow v-for="(row, idx) in items" :key="idx" :item="row">
            <BaseTableCell>
              <span class="font-medium text-n-slate-12">
                {{ row.campaign_name }}
              </span>
            </BaseTableCell>
            <BaseTableCell
              v-if="currentTab === 'adsets' || currentTab === 'ads'"
            >
              <span class="text-n-slate-11">
                {{ row.campaign_adset_name }}
              </span>
            </BaseTableCell>
            <BaseTableCell v-if="currentTab === 'ads'">
              <span class="text-n-slate-11">
                {{ row.campaign_ad_name }}
              </span>
            </BaseTableCell>
            <BaseTableCell align="end">
              <span class="font-medium tabular-nums text-n-slate-12">
                {{ row.leads }}
              </span>
            </BaseTableCell>
            <BaseTableCell v-if="hasMilestone" align="end">
              <span class="tabular-nums text-n-slate-11">
                {{
                  formatMilestoneValue(
                    row.milestone_count,
                    row.milestone_rate_pct
                  )
                }}
              </span>
            </BaseTableCell>
            <BaseTableCell align="end">
              <span class="font-medium text-n-teal-11 tabular-nums">
                {{ row.won_count }}
              </span>
            </BaseTableCell>
            <BaseTableCell align="end">
              <span class="font-medium text-n-ruby-11 tabular-nums">
                {{ row.lost_count }}
              </span>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
  </div>
</template>
