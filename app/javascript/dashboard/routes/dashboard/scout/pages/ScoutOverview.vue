<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import scoutOverviewReportsAPI from 'dashboard/api/scoutOverviewReports';
import RangeSelector from 'dashboard/components-next/captain/pageComponents/overview/RangeSelector.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignMetricCard from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignMetricCard.vue';
import ScoutSelector from 'dashboard/components-next/scout/overview/ScoutSelector.vue';
import PipelineDistributionChart from 'dashboard/components-next/scout/overview/PipelineDistributionChart.vue';
import InterestByStageCard from 'dashboard/components-next/scout/overview/InterestByStageCard.vue';
import RecentConversationsSection from 'dashboard/components-next/scout/overview/RecentConversationsSection.vue';

const route = useRoute();
const { t } = useI18n();

const accountId = computed(() => route.params.accountId);

const scouts = ref([]);
const selectedScoutId = ref(null);
const selectedRange = ref('7');
const isLoading = ref(true);
const report = ref(null);

const timezoneOffset = computed(() => {
  const offset = -(new Date().getTimezoneOffset() / 60);
  return String(offset);
});

const summary = computed(() => report.value?.summary || {});
const pipelineStages = computed(
  () => report.value?.pipeline_stage_distribution || []
);
const interestData = computed(
  () => report.value?.interest_by_stage || { configured: false }
);
const isEmptyState = computed(() => summary.value.total_handled === 0);

const metrics = computed(() => [
  {
    key: 'total_handled',
    label: t('SCOUT.OVERVIEW.METRICS.TOTAL_HANDLED') || 'Total Handled',
    value: summary.value.total_handled ?? 0,
  },
  {
    key: 'qualification_rate',
    label:
      t('SCOUT.OVERVIEW.METRICS.QUALIFICATION_RATE') || 'Qualification Rate',
    value:
      summary.value.qualification_rate !== null &&
      summary.value.qualification_rate !== undefined
        ? `${summary.value.qualification_rate}%`
        : '—',
  },
  {
    key: 'disqualification_rate',
    label:
      t('SCOUT.OVERVIEW.METRICS.DISQUALIFICATION_RATE') ||
      'Disqualification Rate',
    value:
      summary.value.disqualification_rate !== null &&
      summary.value.disqualification_rate !== undefined
        ? `${summary.value.disqualification_rate}%`
        : '—',
  },
  {
    key: 'abandonment_rate',
    label: t('SCOUT.OVERVIEW.METRICS.ABANDONMENT_RATE') || 'Abandonment Rate',
    value:
      summary.value.abandonment_rate !== null &&
      summary.value.abandonment_rate !== undefined
        ? `${summary.value.abandonment_rate}%`
        : '—',
  },
  {
    key: 'avg_messages',
    label: t('SCOUT.OVERVIEW.METRICS.AVG_MESSAGES') || 'Avg Messages / Conv',
    value:
      summary.value.avg_messages_per_conversation !== null &&
      summary.value.avg_messages_per_conversation !== undefined
        ? summary.value.avg_messages_per_conversation
        : '—',
  },
]);

const fetchReport = async () => {
  if (!selectedScoutId.value || !accountId.value) return;

  isLoading.value = true;
  try {
    const response = await scoutOverviewReportsAPI.get(accountId.value, {
      scoutId: selectedScoutId.value,
      range: selectedRange.value,
      timezoneOffset: timezoneOffset.value,
    });
    report.value = response.data;
  } catch (error) {
    report.value = null;
  } finally {
    isLoading.value = false;
  }
};
const fetchInitialData = async () => {
  isLoading.value = true;
  try {
    const scoutsRes = await ScoutAPI.get(accountId.value);
    scouts.value = Array.isArray(scoutsRes.data) ? scoutsRes.data : [];

    if (scouts.value.length > 0) {
      selectedScoutId.value = scouts.value[0].id;
    } else {
      isLoading.value = false;
    }
  } catch (error) {
    isLoading.value = false;
  }
};

watch(selectedRange, () => {
  fetchReport();
});

watch(selectedScoutId, () => {
  fetchReport();
});

onMounted(() => {
  fetchInitialData();
});
</script>

<template>
  <div
    class="flex flex-col flex-1 h-full overflow-y-auto p-6 bg-n-surface-1 dark:bg-n-solid-1"
  >
    <div class="w-full max-w-5xl mx-auto flex flex-col gap-6 pb-8">
      <!-- Header with title & selectors -->
      <div
        class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4"
      >
        <div>
          <h1
            class="text-xl font-bold text-n-slate-12 dark:text-n-slate-12 tracking-tight"
          >
            {{ t('SCOUT.OVERVIEW.TITLE') || 'Scout Overview' }}
          </h1>
        </div>

        <div class="flex items-center gap-3">
          <ScoutSelector
            v-if="scouts.length > 1"
            v-model="selectedScoutId"
            :scouts="scouts"
          />
          <RangeSelector v-model="selectedRange" />
        </div>
      </div>

      <!-- Loading state -->
      <div
        v-if="isLoading && !report"
        class="flex flex-1 items-center justify-center py-20"
      >
        <Spinner />
      </div>

      <!-- Content -->
      <div v-else-if="report" class="flex flex-col gap-6">
        <!-- 5 Summary Metric Cards Grid -->
        <!-- Summary Metric Cards Grid (3 per row) -->
        <div
          class="grid grid-cols-1 gap-px overflow-hidden border rounded-xl sm:grid-cols-2 lg:grid-cols-3 bg-n-weak border-n-weak"
        >
          <CampaignMetricCard
            v-for="metric in metrics"
            :key="metric.key"
            :label="metric.label"
            :value="metric.value"
            :hint="metric.hint"
            :rate="metric.rate"
            :loading="isLoading"
          />
        </div>

        <!-- Empty state when no opportunities in period -->
        <div
          v-if="isEmptyState"
          class="flex flex-col items-center justify-center p-8 bg-n-solid-2 dark:bg-n-solid-3 rounded-xl border border-n-weak"
        >
          <EmptyStateLayout
            :title="
              t('SCOUT.OVERVIEW.EMPTY_STATE.TITLE') ||
              'No Handled Opportunities'
            "
            :subtitle="
              t('SCOUT.OVERVIEW.EMPTY_STATE.DESCRIPTION') ||
              'No opportunities were handled by this Scout in the selected period.'
            "
          />
        </div>

        <!-- Charts grid when opportunities exist -->
        <div v-else class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <PipelineDistributionChart
            :stages="pipelineStages"
            :title="
              t('SCOUT.OVERVIEW.PIPELINE_DISTRIBUTION') ||
              'Pipeline Stage Distribution'
            "
          />
          <InterestByStageCard
            :interest-data="interestData"
            :scout-id="selectedScoutId"
            :account-id="accountId"
          />
        </div>

        <!-- Recent Conversations Table Section -->
        <RecentConversationsSection
          v-if="selectedScoutId"
          :scout-id="selectedScoutId"
          :range="selectedRange"
          :timezone-offset="timezoneOffset"
        />
      </div>
    </div>
  </div>
</template>
