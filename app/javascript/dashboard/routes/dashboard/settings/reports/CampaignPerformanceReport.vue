<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ReportHeader from './components/ReportHeader.vue';
import ReportFilters from './components/ReportFilters.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import CampaignPerformanceTable from './components/CampaignPerformanceTable.vue';

const store = useStore();

const since = ref(0);
const until = ref(0);

const uiFlags = useMapGetter('campaignPerformanceReports/getUIFlags');
const reportData = useMapGetter('campaignPerformanceReports/getData');

const summary = computed(() => reportData.value?.summary || {});

const hasMilestone = computed(() => {
  return (
    Boolean(summary.value.milestone_stage_name) &&
    summary.value.milestone_count !== undefined
  );
});

const milestoneValue = computed(() => {
  if (!hasMilestone.value) return '0 (0.0%)';
  return `${summary.value.milestone_count} (${summary.value.milestone_rate_pct}%)`;
});

const wonValue = computed(() => {
  const count = summary.value.won_count ?? 0;
  const rate = summary.value.won_rate_pct ?? 0.0;
  return `${count} (${rate}%)`;
});

const lostValue = computed(() => {
  const count = summary.value.lost_count ?? 0;
  const rate = summary.value.lost_rate_pct ?? 0.0;
  return `${count} (${rate}%)`;
});

function fetchReport() {
  store.dispatch('campaignPerformanceReports/get', {
    since: since.value,
    until: until.value,
  });
}

function onFilterChange({ from, to }) {
  since.value = from;
  until.value = to;
  fetchReport();
}

onMounted(() => {
  const now = Math.floor(Date.now() / 1000);
  since.value = now - 7 * 24 * 60 * 60;
  until.value = now;
  fetchReport();
});
</script>

<template>
  <ReportHeader :header-title="$t('CAMPAIGN_PERFORMANCE_REPORTS.HEADER')" />

  <div class="flex flex-col gap-6">
    <div class="min-w-0 flex-1">
      <ReportFilters
        :show-group-by="false"
        :show-business-hours="false"
        :show-entity-filter="false"
        @filter-change="onFilterChange"
      />
    </div>

    <!-- Loading State -->
    <div
      v-if="uiFlags.fetchingItems"
      class="flex items-center justify-center py-12 text-n-slate-11 w-full"
    >
      {{ $t('CAMPAIGN_PERFORMANCE_REPORTS.LOADING') }}
    </div>

    <!-- Loaded State -->
    <div v-else class="flex flex-col gap-6">
      <!-- Summary Metric Cards -->
      <div
        class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-4"
      >
        <div
          class="p-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <ReportMetricCard
            :label="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.LEADS')"
            :value="(summary.leads ?? 0).toString()"
            :info-text="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.LEADS_INFO')"
          />
        </div>

        <div
          v-if="hasMilestone"
          class="p-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <ReportMetricCard
            :label="summary.milestone_stage_name"
            :value="milestoneValue"
            :info-text="
              $t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.MILESTONE_INFO')
            "
          />
        </div>

        <div
          class="p-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <ReportMetricCard
            :label="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.WON')"
            :value="wonValue"
            :info-text="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.WON_INFO')"
          />
        </div>

        <div
          class="p-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <ReportMetricCard
            :label="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.LOST')"
            :value="lostValue"
            :info-text="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.LOST_INFO')"
          />
        </div>

        <div
          class="p-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <ReportMetricCard
            :label="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.CAMPAIGNS')"
            :value="(summary.distinct_campaigns ?? 0).toString()"
            :info-text="
              $t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.CAMPAIGNS_INFO')
            "
          />
        </div>

        <div
          class="p-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <ReportMetricCard
            :label="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.ADSETS')"
            :value="(summary.distinct_adsets ?? 0).toString()"
            :info-text="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.ADSETS_INFO')"
          />
        </div>

        <div
          class="p-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <ReportMetricCard
            :label="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.ADS')"
            :value="(summary.distinct_ads ?? 0).toString()"
            :info-text="$t('CAMPAIGN_PERFORMANCE_REPORTS.METRICS.ADS_INFO')"
          />
        </div>
      </div>

      <!-- Breakdown Table -->
      <CampaignPerformanceTable :report-data="reportData" />
    </div>
  </div>
</template>
