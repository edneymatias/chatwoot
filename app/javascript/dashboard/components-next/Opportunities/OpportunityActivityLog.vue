<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import Spinner from 'shared/components/Spinner.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import {
  messageTimestamp,
  dynamicTime,
  shortTimestamp,
} from 'shared/helpers/timeHelper';

const props = defineProps({
  opportunityId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['selectConversation']);

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const loading = ref(true);
const error = ref(false);
const activities = ref([]);
const currentPage = ref(1);
const itemsPerPage = ref(10);

const fetchActivities = async () => {
  if (!props.opportunityId) return;
  loading.value = true;
  error.value = false;
  try {
    const data = await store.dispatch(
      'opportunities/fetchActivities',
      props.opportunityId
    );
    activities.value = Array.isArray(data) ? data : [];
    currentPage.value = 1;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

watch(
  () => props.opportunityId,
  () => {
    fetchActivities();
  },
  { immediate: true }
);

const getStageName = stageId => {
  if (!stageId) return '';
  const stage = store.getters['pipelineStages/stageById'](stageId);
  return stage ? stage.name : `#${stageId}`;
};

const getEventDisplay = activity => {
  const meta = activity.metadata || {};
  switch (activity.event_type) {
    case 'opportunity_created':
      return {
        icon: 'i-ph-plus-circle-bold',
        colorClass: 'text-n-blue-9 bg-n-blue-3 dark:bg-n-blue-3/20',
        title: t('OPPORTUNITIES.ACTIVITY_LOG.EVENTS.OPPORTUNITY_CREATED'),
      };
    case 'opportunity_stage_changed':
      if (meta.from_stage_id) {
        return {
          icon: 'i-ph-arrows-left-right-bold',
          colorClass: 'text-n-violet-9 bg-n-violet-3 dark:bg-n-violet-3/20',
          title: t(
            'OPPORTUNITIES.ACTIVITY_LOG.EVENTS.OPPORTUNITY_STAGE_CHANGED',
            {
              from: getStageName(meta.from_stage_id),
              to: getStageName(meta.to_stage_id),
            }
          ),
        };
      }
      return {
        icon: 'i-ph-arrows-left-right-bold',
        colorClass: 'text-n-violet-9 bg-n-violet-3 dark:bg-n-violet-3/20',
        title: t(
          'OPPORTUNITIES.ACTIVITY_LOG.EVENTS.OPPORTUNITY_STAGE_CHANGED_INITIAL',
          {
            to: getStageName(meta.to_stage_id),
          }
        ),
      };
    case 'opportunity_won':
      return {
        icon: 'i-ph-trophy-bold',
        colorClass: 'text-n-teal-9 bg-n-teal-3 dark:bg-n-teal-3/20',
        title: t('OPPORTUNITIES.ACTIVITY_LOG.EVENTS.OPPORTUNITY_WON'),
      };
    case 'opportunity_lost':
      if (meta.lost_reason) {
        return {
          icon: 'i-ph-x-circle-bold',
          colorClass: 'text-n-ruby-9 bg-n-ruby-3 dark:bg-n-ruby-3/20',
          title: t(
            'OPPORTUNITIES.ACTIVITY_LOG.EVENTS.OPPORTUNITY_LOST_WITH_REASON',
            {
              reason: meta.lost_reason,
            }
          ),
        };
      }
      return {
        icon: 'i-ph-x-circle-bold',
        colorClass: 'text-n-ruby-9 bg-n-ruby-3 dark:bg-n-ruby-3/20',
        title: t('OPPORTUNITIES.ACTIVITY_LOG.EVENTS.OPPORTUNITY_LOST'),
      };
    case 'opportunity_reopened':
      return {
        icon: 'i-ph-arrow-counter-clockwise-bold',
        colorClass: 'text-n-amber-9 bg-n-amber-3 dark:bg-n-amber-3/20',
        title: t('OPPORTUNITIES.ACTIVITY_LOG.EVENTS.OPPORTUNITY_REOPENED'),
      };
    case 'conversation_opened': {
      const displayId =
        meta.conversation_display_id || meta.conversation_id || '';
      const key = meta.is_origin
        ? 'OPPORTUNITIES.ACTIVITY_LOG.EVENTS.CONVERSATION_OPENED'
        : 'OPPORTUNITIES.ACTIVITY_LOG.EVENTS.CONVERSATION_LINKED';
      return {
        icon: 'i-ph-chat-circle-dots-bold',
        colorClass: 'text-n-sky-9 bg-n-sky-3 dark:bg-n-sky-3/20',
        title: t(key, { displayId }),
      };
    }
    case 'conversation_transferred_out': {
      const displayId =
        meta.conversation_display_id || meta.conversation_id || '';
      const targetTitle =
        meta.transferred_to_opportunity_title ||
        `#${meta.transferred_to_opportunity_id}` ||
        '';
      return {
        icon: 'i-ph-arrow-up-right-bold',
        colorClass: 'text-n-ruby-9 bg-n-ruby-3 dark:bg-n-ruby-3/20',
        title: t(
          'OPPORTUNITIES.ACTIVITY_LOG.EVENTS.CONVERSATION_TRANSFERRED_OUT',
          {
            displayId,
            targetTitle,
          }
        ),
      };
    }
    case 'conversation_transferred_in': {
      const displayId =
        meta.conversation_display_id || meta.conversation_id || '';
      const sourceTitle =
        meta.transferred_from_opportunity_title ||
        `#${meta.transferred_from_opportunity_id}` ||
        '';
      return {
        icon: 'i-ph-arrow-down-left-bold',
        colorClass: 'text-n-teal-9 bg-n-teal-3 dark:bg-n-teal-3/20',
        title: t(
          'OPPORTUNITIES.ACTIVITY_LOG.EVENTS.CONVERSATION_TRANSFERRED_IN',
          {
            displayId,
            sourceTitle,
          }
        ),
      };
    }
    case 'conversation_detached': {
      const displayId =
        meta.conversation_display_id || meta.conversation_id || '';
      return {
        icon: 'i-ph-link-break-bold',
        colorClass: 'text-n-slate-9 bg-n-slate-3 dark:bg-n-slate-3/20',
        title: t('OPPORTUNITIES.ACTIVITY_LOG.EVENTS.CONVERSATION_DETACHED', {
          displayId,
        }),
      };
    }
    default:
      return {
        icon: 'i-ph-clock-counter-clockwise-bold',
        colorClass: 'text-n-slate-9 bg-n-slate-3 dark:bg-n-slate-3/20',
        title: activity.event_type,
      };
  }
};

const getActorName = actor => {
  if (actor && actor.name && actor.type !== 'system') return actor.name;
  return t('OPPORTUNITIES.ACTIVITY_LOG.SYSTEM_ACTOR');
};

const formatEventTime = timestamp => {
  if (!timestamp) return '';
  return messageTimestamp(timestamp, 'MMM dd, yyyy hh:mm a');
};

const getRelativeTime = timestamp => {
  if (!timestamp) return '';
  return shortTimestamp(dynamicTime(timestamp));
};

const sortedActivities = computed(() => {
  return [...activities.value].sort(
    (a, b) => (b.occurred_at || 0) - (a.occurred_at || 0)
  );
});

const totalItems = computed(() => sortedActivities.value.length);
const paginatedActivities = computed(() => {
  const start = (currentPage.value - 1) * itemsPerPage.value;
  return sortedActivities.value.slice(start, start + itemsPerPage.value);
});

const onPageChange = page => {
  currentPage.value = page;
};

const getConversationStatusBadge = status => {
  if (!status) return null;
  const statusUpper = status.toUpperCase();
  const label = t(
    `OPPORTUNITIES.ACTIVITY_LOG.CONVERSATION_STATUS.${statusUpper}`,
    status
  );

  let colorClass = 'bg-n-slate-3 text-n-slate-11 border-n-slate-5';
  switch (status.toLowerCase()) {
    case 'open':
      colorClass = 'bg-n-teal-3 text-n-teal-11 border-n-teal-6';
      break;
    case 'resolved':
      colorClass = 'bg-n-slate-3 text-n-slate-11 border-n-slate-5';
      break;
    case 'pending':
      colorClass = 'bg-n-amber-3 text-n-amber-11 border-n-amber-6';
      break;
    case 'snoozed':
      colorClass = 'bg-n-blue-3 text-n-blue-11 border-n-blue-6';
      break;
    default:
      break;
  }

  return { label, colorClass };
};

const handleConversationClick = activity => {
  const meta = activity.metadata || {};
  const conversationId = meta.conversation_display_id || meta.conversation_id;
  if (!conversationId) return;

  emit('selectConversation', conversationId);

  router.push({
    name: 'opportunities_conversation',
    params: { conversationId },
    query: {
      opportunityId: route.query?.opportunityId || props.opportunityId,
    },
  });
};

const tableHeaders = computed(() => {
  return [
    t('OPPORTUNITIES.ACTIVITY_LOG.TABLE_HEADER.ACTIVITY'),
    t('OPPORTUNITIES.ACTIVITY_LOG.TABLE_HEADER.ACTOR'),
    t('OPPORTUNITIES.ACTIVITY_LOG.TABLE_HEADER.TIME'),
  ];
});
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-surface-1 overflow-hidden">
    <!-- Header -->
    <div
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak bg-n-surface-1 shrink-0"
    >
      <div class="flex items-center gap-2">
        <span
          class="i-ph-clock-counter-clockwise-bold text-n-slate-11 text-lg"
        />
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ $t('OPPORTUNITIES.ACTIVITY_LOG.TITLE') }}
        </h2>
      </div>
      <span class="text-xs font-medium text-n-slate-11">
        {{ totalItems }}
      </span>
    </div>

    <!-- Loading State -->
    <div v-if="loading" class="flex flex-1 items-center justify-center">
      <Spinner size="md" />
    </div>

    <!-- Error State -->
    <div
      v-else-if="error"
      class="flex flex-1 flex-col items-center justify-center p-6 text-center gap-3"
    >
      <span class="i-ph-warning-circle-bold text-3xl text-n-ruby-9" />
      <span class="text-sm text-n-slate-11">
        {{ $t('OPPORTUNITIES.ACTIVITY_LOG.FETCH_ERROR') }}
      </span>
      <button
        class="px-3 py-1.5 rounded-md bg-n-surface-2 text-xs font-medium text-n-slate-12 hover:bg-n-surface-3 transition-colors"
        @click="fetchActivities"
      >
        {{ $t('OPPORTUNITIES.LIST.RETRY') }}
      </button>
    </div>

    <!-- Empty State -->
    <div
      v-else-if="sortedActivities.length === 0"
      class="flex flex-1 flex-col items-center justify-center p-6 text-center gap-2"
    >
      <span class="i-ph-clock-counter-clockwise-bold text-3xl text-n-slate-9" />
      <span class="text-sm text-n-slate-11">
        {{ $t('OPPORTUNITIES.ACTIVITY_LOG.EMPTY_STATE') }}
      </span>
    </div>

    <!-- Table + Pagination -->
    <div v-else class="flex flex-col flex-1 min-h-0 justify-between">
      <div class="flex-1 overflow-y-auto px-6">
        <BaseTable :headers="tableHeaders" :items="paginatedActivities">
          <template #row="{ items }">
            <BaseTableRow
              v-for="activity in items"
              :key="activity.id"
              :item="activity"
            >
              <template #default>
                <!-- Activity Column -->
                <BaseTableCell>
                  <div class="flex items-center gap-3 py-1">
                    <div
                      class="flex items-center justify-center w-7 h-7 rounded-full shrink-0 border border-n-surface-1 shadow-sm"
                      :class="getEventDisplay(activity).colorClass"
                    >
                      <span
                        :class="getEventDisplay(activity).icon"
                        class="text-sm"
                      />
                    </div>
                    <div class="flex items-center gap-2 flex-wrap">
                      <button
                        v-if="activity.conversation_viewable"
                        type="button"
                        class="text-body-main font-medium text-n-brand hover:underline cursor-pointer text-left inline-flex items-center gap-1.5 focus:outline-none"
                        @click="handleConversationClick(activity)"
                      >
                        {{ getEventDisplay(activity).title }}
                      </button>
                      <span
                        v-else
                        class="text-body-main text-n-slate-12 font-medium"
                      >
                        {{ getEventDisplay(activity).title }}
                      </span>
                      <span
                        v-if="
                          activity.conversation_viewable &&
                          getConversationStatusBadge(
                            activity.conversation_status
                          )
                        "
                        class="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium border"
                        :class="
                          getConversationStatusBadge(
                            activity.conversation_status
                          ).colorClass
                        "
                      >
                        {{
                          getConversationStatusBadge(
                            activity.conversation_status
                          ).label
                        }}
                      </span>
                      <span
                        v-if="
                          activity.metadata && activity.metadata.approximate
                        "
                        v-tooltip.top="
                          $t('OPPORTUNITIES.ACTIVITY_LOG.APPROXIMATE_TOOLTIP')
                        "
                        class="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-amber-3 text-n-amber-11 border border-n-amber-6 cursor-help"
                      >
                        {{
                          `(${$t('OPPORTUNITIES.ACTIVITY_LOG.APPROXIMATE_BADGE')})`
                        }}
                      </span>
                    </div>
                  </div>
                </BaseTableCell>

                <!-- Actor Column -->
                <BaseTableCell class="w-44">
                  <span
                    class="text-body-main text-n-slate-11 whitespace-nowrap"
                  >
                    {{ getActorName(activity.actor) }}
                  </span>
                </BaseTableCell>

                <!-- Time Column -->
                <BaseTableCell class="w-52">
                  <span
                    v-tooltip.top="getRelativeTime(activity.occurred_at)"
                    class="text-body-main text-n-slate-11 whitespace-nowrap cursor-default"
                  >
                    {{ formatEventTime(activity.occurred_at) }}
                  </span>
                </BaseTableCell>
              </template>
            </BaseTableRow>
          </template>
        </BaseTable>
      </div>

      <!-- Pagination Footer -->
      <PaginationFooter
        v-if="totalItems > itemsPerPage"
        :current-page="currentPage"
        :total-items="totalItems"
        :items-per-page="itemsPerPage"
        class="!px-6 mt-auto shrink-0"
        @update:current-page="onPageChange"
      />
    </div>
  </div>
</template>
