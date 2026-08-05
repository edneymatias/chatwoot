<script setup>
import { computed, h } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
  getPaginationRowModel,
} from '@tanstack/vue-table';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';
import Table from 'dashboard/components/table/Table.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';

const store = useStore();
const { t } = useI18n();

const rows = computed(
  () => store.getters['opportunityAttributeReports/getData']?.rows || []
);
const pipelineCurrency = useMapGetter('pipelineCurrencySetting/getCurrency');

const formatValue = amount =>
  formatCurrencyAmount(amount || 0, pipelineCurrency.value, true);

const countAndValueCell = (count, value) =>
  h('div', { class: 'flex flex-col' }, [
    h('span', { class: 'text-n-slate-12' }, count),
    h('span', { class: 'text-xs text-n-slate-11' }, formatValue(value)),
  ]);

const columnHelper = createColumnHelper();
const columns = [
  columnHelper.accessor('value', {
    header: t('OPPORTUNITY_ATTRIBUTE_REPORTS.TABLE.VALUE'),
    cell: info =>
      info.getValue() === null
        ? t('OPPORTUNITY_ATTRIBUTE_REPORTS.TABLE.NO_VALUE')
        : info.getValue(),
    size: 220,
  }),
  columnHelper.accessor('opportunities_count', {
    header: t('OPPORTUNITY_ATTRIBUTE_REPORTS.TABLE.OPPORTUNITIES'),
    cell: info =>
      countAndValueCell(info.getValue(), info.row.original.total_value),
    size: 180,
  }),
  columnHelper.accessor('won_count', {
    header: t('OPPORTUNITY_ATTRIBUTE_REPORTS.TABLE.WON'),
    cell: info =>
      countAndValueCell(info.getValue(), info.row.original.won_value),
    size: 150,
  }),
  columnHelper.accessor('lost_count', {
    header: t('OPPORTUNITY_ATTRIBUTE_REPORTS.TABLE.LOST'),
    cell: info =>
      countAndValueCell(info.getValue(), info.row.original.lost_value),
    size: 150,
  }),
  columnHelper.accessor('avg_time_to_close', {
    header: t('OPPORTUNITY_ATTRIBUTE_REPORTS.TABLE.AVG_TIME_TO_CLOSE'),
    cell: info => (info.getValue() === null ? '—' : `${info.getValue()}d`),
    size: 160,
  }),
];

const table = useVueTable({
  get data() {
    return rows.value;
  },
  columns,
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
  getPaginationRowModel: getPaginationRowModel(),
  initialState: {
    pagination: {
      pageSize: 10,
    },
  },
});
</script>

<template>
  <div class="flex flex-col gap-4 w-full">
    <EmptyState
      v-if="!rows.length"
      :title="$t('OPPORTUNITY_ATTRIBUTE_REPORTS.NO_DATA.TITLE')"
      :description="$t('OPPORTUNITY_ATTRIBUTE_REPORTS.NO_DATA.DESCRIPTION')"
    />

    <div v-else class="w-full overflow-x-auto">
      <Table :table="table" />
      <Pagination class="mt-3" :table="table" />
    </div>
  </div>
</template>
