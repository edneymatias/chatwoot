<script setup>
import { computed, h, onMounted } from 'vue';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
  getPaginationRowModel,
} from '@tanstack/vue-table';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';

import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Table from 'dashboard/components/table/Table.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import AgentCell from './overview/AgentCell.vue';

const props = defineProps({
  rows: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();

const agents = useMapGetter('agents/getAgents');
const pipelineCurrency = useMapGetter('pipelineCurrencySetting/getCurrency');

const PERFORMANCE_TABLE_PAGE_SIZE_KEY =
  'report_opportunity_funnel_performance_table_page_size';

const getPageSize = () =>
  uiSettings.value[PERFORMANCE_TABLE_PAGE_SIZE_KEY] || 10;

const handlePageSizeChange = pageSize => {
  updateUISettings({ [PERFORMANCE_TABLE_PAGE_SIZE_KEY]: pageSize });
};

const getRow = id => props.rows.find(r => r.assignee_id === Number(id)) || {};

const tableData = computed(() =>
  agents.value
    .map(agent => {
      const row = getRow(agent.id);
      return {
        agent: agent.available_name || agent.name,
        email: agent.email,
        thumbnail: agent.thumbnail,
        status: agent.availability_status,
        openCount: row.open_count || 0,
        openValue: row.open_value || 0,
        convertedCount: row.won_count || 0,
        convertedValue: row.won_value || 0,
      };
    })
    .sort((a, b) => {
      const diff = b.openCount - a.openCount;
      return diff === 0 ? a.agent.localeCompare(b.agent) : diff;
    })
);

const metricCellRender = (countKey, valueKey) => cellProps =>
  h('div', { class: 'flex flex-col' }, [
    h('span', { class: 'text-n-slate-12' }, cellProps.row.original[countKey]),
    h(
      'span',
      { class: 'text-xs text-n-slate-11' },
      formatCurrencyAmount(
        cellProps.row.original[valueKey],
        pipelineCurrency.value
      )
    ),
  ]);

const columnHelper = createColumnHelper();
const columns = [
  columnHelper.accessor('agent', {
    header: t('OPPORTUNITY_FUNNEL_REPORTS.PERFORMANCE_TABLE.AGENT'),
    cell: cellProps => h(AgentCell, cellProps),
    size: 250,
  }),
  columnHelper.accessor('openCount', {
    header: t('OPPORTUNITY_FUNNEL_REPORTS.PERFORMANCE_TABLE.OPEN'),
    cell: metricCellRender('openCount', 'openValue'),
    size: 150,
  }),
  columnHelper.accessor('convertedCount', {
    header: t('OPPORTUNITY_FUNNEL_REPORTS.PERFORMANCE_TABLE.CONVERTED'),
    cell: metricCellRender('convertedCount', 'convertedValue'),
    size: 150,
  }),
];

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  columns,
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
  getPaginationRowModel: getPaginationRowModel(),
  initialState: {
    pagination: {
      pageSize: getPageSize(),
    },
  },
});

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('pipelineCurrencySetting/fetch');
});
</script>

<template>
  <div class="flex flex-col flex-1">
    <Table :table="table" />
    <Pagination
      class="mt-2"
      :table="table"
      show-page-size-selector
      :default-page-size="getPageSize()"
      @page-size-change="handlePageSizeChange"
    />
    <div
      v-if="isLoading"
      class="items-center flex text-base justify-center p-8"
    >
      <Spinner />
      <span>
        {{ $t('OPPORTUNITY_FUNNEL_REPORTS.PERFORMANCE_TABLE.LOADING_MESSAGE') }}
      </span>
    </div>
    <EmptyState
      v-else-if="!isLoading && !agents.length"
      :title="$t('OPPORTUNITY_FUNNEL_REPORTS.PERFORMANCE_TABLE.NO_AGENTS')"
    />
  </div>
</template>
