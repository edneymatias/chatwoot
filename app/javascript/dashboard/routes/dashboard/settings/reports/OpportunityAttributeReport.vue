<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import ReportHeader from './components/ReportHeader.vue';
import ReportFilters from './components/ReportFilters.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import CardLayout from 'dashboard/components-next/CardLayout.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import OpportunityAttributeReportTable from './components/OpportunityAttributeReportTable.vue';

const store = useStore();

const attributes = computed(
  () => store.getters['attributes/getOpportunityAttributes'] || []
);
const listAttributes = computed(() =>
  (attributes.value || [])
    .filter(a => a.attributeDisplayType === 'list')
    .sort((a, b) =>
      (a.attributeDisplayName || '').localeCompare(b.attributeDisplayName || '')
    )
);

const selected = ref(null);
const since = ref(0);
const until = ref(0);

const uiFlags = computed(
  () => store.getters['opportunityAttributeReports/getUIFlags'] || {}
);

const selectOptions = computed(() =>
  listAttributes.value.map(a => ({
    value: a.id,
    label: a.attributeDisplayName,
  }))
);

function fetchReport() {
  if (!selected.value) return;
  store.dispatch('opportunityAttributeReports/get', {
    since: since.value,
    until: until.value,
    customAttributeDefinitionId: selected.value,
  });
}

function onFilterChange({ from, to }) {
  since.value = from;
  until.value = to;
  fetchReport();
}

onMounted(async () => {
  store.dispatch('pipelineCurrencySetting/fetch');
  await store.dispatch('attributes/get');

  const now = Math.floor(Date.now() / 1000);
  since.value = now - 7 * 24 * 60 * 60;
  until.value = now;

  if (listAttributes.value.length === 0) return;
  selected.value = listAttributes.value[0].id;
  fetchReport();
});

watch(selected, (newVal, oldVal) => {
  if (newVal && newVal !== oldVal) fetchReport();
});
</script>

<template>
  <ReportHeader
    :header-title="$t('OPPORTUNITY_ATTRIBUTE_REPORTS.HEADER')"
    :header-description="$t('OPPORTUNITY_ATTRIBUTE_REPORTS.DESCRIPTION')"
  />

  <div class="flex flex-col gap-6">
    <div
      class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between"
    >
      <div class="min-w-0 flex-1">
        <ReportFilters
          :show-group-by="false"
          :show-business-hours="false"
          :show-entity-filter="false"
          @filter-change="onFilterChange"
        />
      </div>

      <div class="w-full max-w-xs xl:w-auto">
        <Select
          v-if="selectOptions.length"
          v-model="selected"
          :options="selectOptions"
        />
      </div>
    </div>

    <div v-if="!listAttributes.length">
      <EmptyState
        :title="$t('OPPORTUNITY_ATTRIBUTE_REPORTS.EMPTY.TITLE')"
        :description="$t('OPPORTUNITY_ATTRIBUTE_REPORTS.EMPTY.DESCRIPTION')"
      />
    </div>

    <CardLayout v-else>
      <div
        v-if="uiFlags.fetchingItems"
        class="flex items-center justify-center py-8 text-n-slate-11 w-full"
      >
        {{ $t('OPPORTUNITY_ATTRIBUTE_REPORTS.LOADING') }}
      </div>

      <OpportunityAttributeReportTable v-else />
    </CardLayout>
  </div>
</template>
