<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';
import ReportHeader from './components/ReportHeader.vue';
import ReportFilters from './components/ReportFilters.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import DonutChart from 'shared/components/charts/DonutChart.vue';
import LineChart from 'shared/components/charts/LineChart.vue';
import AssigneePerformanceTable from './components/AssigneePerformanceTable.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import { CHART_FONT_FAMILY } from './constants';

const store = useStore();
const { t } = useI18n();
const pipelineCurrency = useMapGetter('pipelineCurrencySetting/getCurrency');

// Won/lost donut colors — Radix teal-9 / ruby-9 light hex equivalents,
// matching KanbanCard.vue's won/lost status badge tokens (n-teal / n-ruby).
// Canvas rendering requires resolved color strings, same pattern as constants.js.
const WIN_COLOR = '#12a594';
const LOST_COLOR = '#e54666';
const DEFAULT_BAR_COLOR = 'rgb(31, 147, 255)';

// Values render in the tooltip on hover, so the y-axis doesn't need labels.
const chartOptions = {
  scales: {
    x: {
      ticks: { fontFamily: CHART_FONT_FAMILY },
      grid: { drawOnChartArea: false },
    },
    y: {
      ticks: { display: false },
      grid: { drawOnChartArea: false },
    },
  },
};

const since = ref(0);
const until = ref(0);
const isFetching = ref(false);
// Default to value: monetary opportunity value is the primary actionable metric.
const showValue = ref(true);

const reportData = computed(
  () => store.getters['opportunityFunnelReports/getData']
);
const pipelineStages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);

// Build a name→accent_color lookup for stage-keyed bar coloring
const stageColorByName = computed(() => {
  const map = {};
  pipelineStages.value.forEach(s => {
    if (s.accent_color) map[s.name] = s.accent_color;
  });
  return map;
});

function stageBackgroundColors(labels) {
  return (labels || []).map(
    label => stageColorByName.value[label] || DEFAULT_BAR_COLOR
  );
}

const compactNumber = amount =>
  new Intl.NumberFormat('en-US', {
    notation: 'compact',
    compactDisplay: 'short',
  }).format(amount || 0);

// Renders a count as-is, or a value formatted in the pipeline's currency.
// `compact` abbreviates large numbers (e.g. 1.2K, 3M) for headline display.
const formatMetric = (amount, compact = false) => {
  if (showValue.value) {
    return formatCurrencyAmount(amount || 0, pipelineCurrency.value, compact);
  }
  return compact ? compactNumber(amount) : `${Math.round(amount || 0)}`;
};

const formatHeadline = amount => formatMetric(amount, true);
const formatTooltipValue = amount => formatMetric(amount, false);

const sumOf = arr => (arr || []).reduce((sum, n) => sum + n, 0);

// Bar/line charts that respect the value/count toggle show full-precision,
// currency-aware values in the tooltip (headline stays abbreviated).
const valueChartOptions = {
  ...chartOptions,
  plugins: {
    tooltip: {
      callbacks: {
        label: ctx => formatTooltipValue(ctx.raw),
      },
    },
  },
};

// Conversion funnel is always a % of count, regardless of the value toggle.
const percentChartOptions = {
  ...chartOptions,
  plugins: {
    tooltip: {
      callbacks: {
        label: ctx => `${ctx.raw}%`,
      },
    },
  },
};

// Conversion funnel chart data — always % of period-created opportunities reaching
// each stage; a percentage-of-count metric, so it ignores the value/quantity toggle.
const conversionFunnelData = computed(() => {
  const d = reportData.value?.conversion_funnel;
  if (!d) return { labels: [], datasets: [] };
  return {
    labels: d.labels,
    datasets: [
      {
        label: t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.CONVERSION_FUNNEL'),
        data: d.count_data,
        backgroundColor: stageBackgroundColors(d.labels),
      },
    ],
  };
});

// Conversion funnel headline — overall conversion rate from the first stage to won
const conversionFunnelHeadline = computed(() => {
  const d = reportData.value?.conversion_funnel;
  if (!d) return '—';
  return `${d.won_rate_pct}%`;
});

// Donut chart's default options nest legend under `plugins`, so the tooltip
// override must carry the legend config along to avoid clobbering it.
const donutChartOptions = {
  plugins: {
    legend: {
      display: true,
      position: 'bottom',
      labels: { fontFamily: CHART_FONT_FAMILY },
    },
    tooltip: {
      callbacks: {
        label: ctx => `${ctx.label}: ${formatTooltipValue(ctx.raw)}`,
      },
    },
  },
};

// Win rate donut chart data
const winRateData = computed(() => {
  const d = reportData.value?.win_rate;
  if (!d) return { labels: [], datasets: [] };
  return {
    labels: [
      t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.WIN_RATE_WON'),
      t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.WIN_RATE_LOST'),
    ],
    datasets: [
      {
        data: showValue.value
          ? [d.won_value, d.lost_value]
          : [d.won_count, d.lost_count],
        backgroundColor: [WIN_COLOR, LOST_COLOR],
      },
    ],
  };
});

// Win rate headline % (US3: 0% when both are 0)
const winRatePercent = computed(() => {
  const d = reportData.value?.win_rate;
  if (!d) return t('OPPORTUNITY_FUNNEL_REPORTS.METRICS.WIN_RATE_EMPTY');
  const won = showValue.value ? d.won_value : d.won_count;
  const lost = showValue.value ? d.lost_value : d.lost_count;
  const total = won + lost;
  if (total === 0) return '0%';
  return `${Math.round((won / total) * 100)}%`;
});

// Win rate headline — total won + lost opportunities decided in the period
const winRateHeadline = computed(() => {
  const d = reportData.value?.win_rate;
  if (!d) return '—';
  return formatHeadline(
    showValue.value
      ? (d.won_value || 0) + (d.lost_value || 0)
      : (d.won_count || 0) + (d.lost_count || 0)
  );
});

// Pipeline by stage — value (currently-open value) or count of open opportunities
const pipelineValueData = computed(() => {
  const d = reportData.value?.pipeline_value_by_stage;
  if (!d) return { labels: [], datasets: [] };
  return {
    labels: d.labels,
    datasets: [
      {
        label: t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.PIPELINE_VALUE_BY_STAGE'),
        data: showValue.value ? d.value_data : d.count_data,
        backgroundColor: stageBackgroundColors(d.labels),
      },
    ],
  };
});

// Pipeline by stage headline — total across all stages, currently open
const pipelineHeadline = computed(() => {
  const d = reportData.value?.pipeline_value_by_stage;
  if (!d) return '—';
  return formatHeadline(sumOf(showValue.value ? d.value_data : d.count_data));
});

// Avg time in stage
const avgTimeInStageData = computed(() => {
  const d = reportData.value?.avg_time_in_stage;
  if (!d) return { labels: [], datasets: [] };
  return {
    labels: d.labels,
    datasets: [
      {
        label: t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.AVG_TIME_IN_STAGE'),
        data: d.data,
        backgroundColor: stageBackgroundColors(d.labels),
      },
    ],
  };
});

// Avg time in stage headline — average of the per-stage averages shown in the chart
const avgTimeInStageHeadline = computed(() => {
  const d = reportData.value?.avg_time_in_stage;
  if (!d || !d.data?.length) return '—';
  const avg = sumOf(d.data) / d.data.length;
  return `${avg.toFixed(1)} ${t('OPPORTUNITY_FUNNEL_REPORTS.METRICS.SALES_CYCLE_UNIT')}`;
});

// New opportunities over time — count created per day, or their summed value
const newOpportunitiesData = computed(() => {
  const d = reportData.value?.new_opportunities_over_time;
  if (!d) return { labels: [], datasets: [] };
  return {
    labels: d.labels,
    datasets: [
      {
        label: t(
          'OPPORTUNITY_FUNNEL_REPORTS.CHARTS.NEW_OPPORTUNITIES_OVER_TIME'
        ),
        data: showValue.value ? d.value_data : d.count_data,
        borderColor: '#779BBB',
        backgroundColor: 'rgba(119,155,187,0.15)',
      },
    ],
  };
});

// New opportunities headline — total created in the period
const newOpportunitiesHeadline = computed(() => {
  const d = reportData.value?.new_opportunities_over_time;
  if (!d) return '—';
  return formatHeadline(sumOf(showValue.value ? d.value_data : d.count_data));
});

// Sales cycle time — null means no data (US3: render '—')
const salesCycleValue = computed(() => {
  const d = reportData.value?.sales_cycle_time;
  if (!d || d.average_days === null || d.average_days === undefined) {
    return t('OPPORTUNITY_FUNNEL_REPORTS.METRICS.SALES_CYCLE_EMPTY');
  }
  return `${d.average_days} ${t('OPPORTUNITY_FUNNEL_REPORTS.METRICS.SALES_CYCLE_UNIT')}`;
});

// Performance by assignee — rows joined against agents inside AssigneePerformanceTable
const performanceByAssigneeRows = computed(
  () => reportData.value?.performance_by_assignee || []
);

function fetchReport() {
  isFetching.value = true;
  store
    .dispatch('opportunityFunnelReports/get', {
      since: since.value,
      until: until.value,
    })
    .finally(() => {
      isFetching.value = false;
    });
}

function onFilterChange({ from, to }) {
  since.value = from;
  until.value = to;
  fetchReport();
}

onMounted(() => {
  store.dispatch('pipelineStages/fetch');
  store.dispatch('pipelineCurrencySetting/fetch');
});
</script>

<template>
  <ReportHeader :header-title="$t('OPPORTUNITY_FUNNEL_REPORTS.HEADER')" />
  <div class="flex flex-col flex-1 gap-6">
    <ReportFilters
      :show-group-by="false"
      :show-business-hours="false"
      :show-entity-filter="false"
      @filter-change="onFilterChange"
    />

    <!-- Loading state -->
    <div
      v-if="isFetching"
      class="flex items-center justify-center py-12 text-n-slate-11"
    >
      {{ $t('OPPORTUNITY_FUNNEL_REPORTS.LOADING') }}
    </div>

    <template v-else>
      <!-- Metric Cards Row: Win Rate + Sales Cycle Time -->
      <div
        class="flex flex-wrap gap-4 px-6 py-5 mx-0 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
      >
        <ReportMetricCard
          :label="$t('OPPORTUNITY_FUNNEL_REPORTS.METRICS.WIN_RATE_LABEL')"
          :value="winRatePercent"
          :info-text="$t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.WIN_RATE')"
          class="flex-1"
        />
        <ReportMetricCard
          :label="$t('OPPORTUNITY_FUNNEL_REPORTS.METRICS.SALES_CYCLE_LABEL')"
          :value="salesCycleValue"
          :info-text="$t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.SALES_CYCLE_TIME')"
          class="flex-1"
        />
      </div>

      <!-- Charts Container -->
      <div
        class="grid grid-cols-1 gap-6 lg:grid-cols-2 px-6 py-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="flex items-center justify-end lg:col-span-2">
          <span class="mx-2 text-sm whitespace-nowrap text-n-slate-11">
            {{ $t('OPPORTUNITY_FUNNEL_REPORTS.SHOW_VALUE_TOGGLE') }}
          </span>
          <ToggleSwitch v-model="showValue" />
        </div>
        <div class="p-4 mb-3 rounded-md">
          <h3 class="m-0 mb-1 text-sm font-medium text-n-slate-11">
            {{ $t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.CONVERSION_FUNNEL') }}
          </h3>
          <p class="m-0 mb-3 text-2xl font-medium text-n-slate-12">
            {{ conversionFunnelHeadline }}
          </p>
          <div class="h-72">
            <BarChart
              :collection="conversionFunnelData"
              :chart-options="percentChartOptions"
            />
          </div>
        </div>
        <div class="p-4 mb-3 rounded-md">
          <h3 class="m-0 mb-1 text-sm font-medium text-n-slate-11">
            {{ $t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.WIN_RATE') }}
          </h3>
          <p class="m-0 mb-3 text-2xl font-medium text-n-slate-12">
            {{ winRateHeadline }}
          </p>
          <div class="h-72">
            <DonutChart
              :collection="winRateData"
              :chart-options="donutChartOptions"
            />
          </div>
        </div>

        <div class="p-4 mb-3 rounded-md">
          <h3 class="m-0 mb-1 text-sm font-medium text-n-slate-11">
            {{
              $t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.PIPELINE_VALUE_BY_STAGE')
            }}
          </h3>
          <p class="m-0 mb-3 text-2xl font-medium text-n-slate-12">
            {{ pipelineHeadline }}
          </p>
          <div class="h-72">
            <BarChart
              :collection="pipelineValueData"
              :chart-options="valueChartOptions"
            />
          </div>
        </div>
        <div class="p-4 mb-3 rounded-md">
          <h3 class="m-0 mb-1 text-sm font-medium text-n-slate-11">
            {{ $t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.AVG_TIME_IN_STAGE') }}
          </h3>
          <p class="m-0 mb-3 text-2xl font-medium text-n-slate-12">
            {{ avgTimeInStageHeadline }}
          </p>
          <div class="h-72">
            <BarChart
              :collection="avgTimeInStageData"
              :chart-options="chartOptions"
            />
          </div>
        </div>

        <div class="p-4 mb-3 rounded-md lg:col-span-2">
          <h3 class="m-0 mb-1 text-sm font-medium text-n-slate-11">
            {{
              $t(
                'OPPORTUNITY_FUNNEL_REPORTS.CHARTS.NEW_OPPORTUNITIES_OVER_TIME'
              )
            }}
          </h3>
          <p class="m-0 mb-3 text-2xl font-medium text-n-slate-12">
            {{ newOpportunitiesHeadline }}
          </p>
          <div class="h-72">
            <LineChart
              :collection="newOpportunitiesData"
              :chart-options="valueChartOptions"
            />
          </div>
        </div>

        <div class="p-4 mb-3 rounded-md lg:col-span-2">
          <h3 class="m-0 mb-4 text-sm font-medium text-n-slate-11">
            {{
              $t('OPPORTUNITY_FUNNEL_REPORTS.CHARTS.PERFORMANCE_BY_ASSIGNEE')
            }}
          </h3>
          <AssigneePerformanceTable
            :rows="performanceByAssigneeRows"
            :is-loading="isFetching"
          />
        </div>
      </div>
    </template>
  </div>
</template>
