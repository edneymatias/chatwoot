<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { formatDuration, messageTimestamp } from 'shared/helpers/timeHelper';
import scoutOverviewReportsAPI from 'dashboard/api/scoutOverviewReports';

import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationStatusBadge from './ConversationStatusBadge.vue';

const props = defineProps({
  scoutId: {
    type: [Number, String],
    required: true,
  },
  range: {
    type: String,
    required: true,
  },
  timezoneOffset: {
    type: [Number, String],
    default: 0,
  },
});

const { t } = useI18n();
const { accountId } = useAccount();
const loading = ref(true);

const conversations = ref([]);
const statusCounts = ref({
  all: 0,
  qualified: 0,
  disqualified: 0,
  abandoned: 0,
  in_progress: 0,
  transferred_without_opportunity: 0,
});
const pagination = ref({
  current_page: 1,
  total_count: 0,
  per_page: 25,
  total_pages: 1,
});
const activeStatus = ref('all');

const FILTER_KEYS = [
  'all',
  'qualified',
  'disqualified',
  'abandoned',
  'in_progress',
  'transferred_without_opportunity',
];

const filterPills = computed(() => {
  return FILTER_KEYS.map(key => {
    const i18nKey = `SCOUT.OVERVIEW.RECENT_CONVERSATIONS.FILTERS.${key.toUpperCase()}`;
    return {
      key,
      label: t(i18nKey),
      count: statusCounts.value[key] || 0,
    };
  });
});

const tableHeaders = computed(() => [
  t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.COLUMNS.CONTACT'),
  t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.COLUMNS.START_TIME'),
  t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.COLUMNS.DURATION'),
  t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.COLUMNS.MESSAGES'),
  t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.COLUMNS.STATUS'),
]);

const fetchConversations = async () => {
  if (!props.scoutId) return;
  loading.value = true;
  try {
    const response = await scoutOverviewReportsAPI.getConversations(
      accountId.value,
      {
        scoutId: props.scoutId,
        range: props.range,
        timezoneOffset: props.timezoneOffset,
        status: activeStatus.value,
        page: pagination.value.current_page,
        perPage: pagination.value.per_page,
      }
    );

    const data = response?.data || {};
    conversations.value = data.conversations || [];
    if (data.status_counts) {
      statusCounts.value = { ...data.status_counts };
    }
    if (data.pagination) {
      pagination.value = { ...data.pagination };
    }
  } catch (error) {
    conversations.value = [];
  } finally {
    loading.value = false;
  }
};

const onFilterSelect = key => {
  activeStatus.value = key;
  pagination.value.current_page = 1;
  fetchConversations();
};

const onPageChange = page => {
  pagination.value.current_page = page;
  fetchConversations();
};

const openConversation = conv => {
  if (!conv?.id) {
    useAlert(t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.ERRORS.INVALID_ID'));
    return;
  }

  const url = `/app/accounts/${accountId.value}/conversations/${conv.id}`;
  const win = window.open(url, '_blank', 'noopener,noreferrer');
  if (!win) {
    useAlert(t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.ERRORS.POPUP_BLOCKED'));
  }
};

const formatConversationDuration = conv => {
  if (
    conv.duration_seconds !== null &&
    conv.duration_seconds !== undefined &&
    conv.messages_count > 1
  ) {
    return formatDuration(conv.duration_seconds);
  }
  return '—';
};

const formatStartTime = timestamp => {
  if (!timestamp) return '—';
  return messageTimestamp(timestamp);
};

watch(
  () => [props.scoutId, props.range, props.timezoneOffset],
  () => {
    pagination.value.current_page = 1;
    fetchConversations();
  }
);

onMounted(() => {
  fetchConversations();
});
</script>

<template>
  <div
    data-testid="recent-conversations-section"
    class="w-full border rounded-xl border-n-weak bg-n-solid-1"
  >
    <div
      class="flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:gap-4"
    >
      <div class="flex flex-col gap-0.5">
        <span class="text-heading-2 text-n-slate-12">
          {{ t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.TITLE') }}
        </span>
        <span class="text-body-sub text-xs text-n-slate-11">
          {{ t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.SUBTITLE') }}
        </span>
      </div>

      <!-- Status filter pills -->
      <div class="min-w-0 p-1 -m-1 overflow-x-auto no-scrollbar">
        <div class="flex items-center gap-1.5">
          <button
            v-for="pill in filterPills"
            :key="pill.key"
            data-testid="status-filter-pill"
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors cursor-pointer whitespace-nowrap"
            :class="
              activeStatus === pill.key
                ? 'bg-n-brand text-white border-n-brand dark:bg-n-brand dark:border-n-brand'
                : 'bg-n-alpha-2 text-n-slate-11 border-n-weak hover:bg-n-alpha-3'
            "
            @click="onFilterSelect(pill.key)"
          >
            <span>{{ pill.label }}</span>
            <span
              class="inline-flex items-center justify-center px-1.5 py-0.5 rounded-full text-[10px]"
              :class="
                activeStatus === pill.key
                  ? 'bg-white/20 text-white'
                  : 'bg-n-alpha-3 text-n-slate-11'
              "
            >
              {{ pill.count }}
            </span>
          </button>
        </div>
      </div>
    </div>

    <!-- Loading spinner -->
    <div
      v-if="loading"
      data-testid="loading-spinner"
      class="flex items-center justify-center py-20 border-t text-n-slate-11 border-n-weak"
    >
      <Spinner />
    </div>

    <!-- Table content -->
    <div
      v-else-if="conversations.length > 0"
      class="overflow-x-auto border-t border-n-weak [&_th:first-child]:ps-5 [&_td:first-child]:ps-5 [&_th:last-child]:pe-5 [&_td:last-child]:pe-5"
    >
      <BaseTable :headers="tableHeaders" :items="conversations">
        <template #row="{ items }">
          <BaseTableRow
            v-for="conv in items"
            :key="conv.id"
            :item="conv"
            data-testid="conversation-row"
            class="hover:bg-n-alpha-1 cursor-pointer transition-colors"
            @click="openConversation(conv)"
          >
            <!-- Contact Cell -->
            <BaseTableCell>
              <div class="flex flex-col gap-0.5 py-1 max-w-[200px]">
                <span
                  data-testid="contact-name"
                  class="truncate text-heading-3 text-n-slate-12 font-medium"
                  :title="conv.contact?.name || '—'"
                >
                  {{ conv.contact?.name || '—' }}
                </span>
                <span
                  v-if="conv.contact?.identifier || conv.contact?.phone_number"
                  class="truncate tabular-nums text-label-small text-n-slate-11"
                  :title="
                    conv.contact?.identifier || conv.contact?.phone_number
                  "
                >
                  {{ conv.contact?.identifier || conv.contact?.phone_number }}
                </span>
              </div>
            </BaseTableCell>

            <!-- Start Time Cell -->
            <BaseTableCell>
              <span class="text-body-sub text-xs text-n-slate-11">
                {{ formatStartTime(conv.start_at) }}
              </span>
            </BaseTableCell>

            <!-- Duration Cell -->
            <BaseTableCell>
              <span
                data-testid="duration-cell"
                class="text-body-sub text-xs text-n-slate-11"
              >
                {{ formatConversationDuration(conv) }}
              </span>
            </BaseTableCell>

            <!-- Messages Count Cell -->
            <BaseTableCell>
              <span class="text-body-sub text-xs text-n-slate-11">
                {{ conv.messages_count }}
              </span>
            </BaseTableCell>

            <!-- Status Cell -->
            <BaseTableCell>
              <ConversationStatusBadge :status="conv.status" />
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>

      <!-- Pagination Footer -->
      <div v-if="pagination.total_pages > 1" class="border-t border-n-weak">
        <PaginationFooter
          :current-page="pagination.current_page"
          :total-items="pagination.total_count"
          :items-per-page="pagination.per_page"
          class="!bg-transparent !px-5 rounded-b-xl before:hidden"
          @update:current-page="onPageChange"
        />
      </div>
    </div>

    <!-- Empty state -->
    <div v-else data-testid="empty-state" class="py-12 border-t border-n-weak">
      <EmptyStateLayout
        :title="t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.EMPTY_STATE.TITLE')"
        :subtitle="
          t('SCOUT.OVERVIEW.RECENT_CONVERSATIONS.EMPTY_STATE.DESCRIPTION')
        "
        :show-backdrop="false"
      />
    </div>
  </div>
</template>
