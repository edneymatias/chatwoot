<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  opportunityId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['close', 'statusChanged']);

const store = useStore();

const opportunity = computed(() =>
  store.getters['opportunities/cardById'](props.opportunityId)
);

const statusBadgeClass = computed(() => {
  if (!opportunity.value) return '';
  if (opportunity.value.status === 'won') return 'bg-n-green-3 text-n-green-11';
  if (opportunity.value.status === 'lost') return 'bg-n-red-3 text-n-red-11';
  return 'bg-n-slate-3 text-n-slate-11';
});

const setStatus = status => {
  emit('statusChanged', { id: props.opportunityId, status });
};
</script>

<template>
  <div
    v-if="opportunity"
    class="flex flex-col h-full bg-n-surface-1 border-l border-n-weak w-80 min-w-[20rem] overflow-y-auto"
  >
    <div class="p-4 border-b border-n-weak flex items-center justify-between">
      <h2
        class="text-n-slate-12 font-medium text-lg leading-6 truncate"
        :title="opportunity.title"
      >
        {{ opportunity.title }}
      </h2>
      <button
        class="p-1 rounded-sm text-n-slate-11 hover:bg-n-surface-2 transition-colors"
        @click="$emit('close')"
      >
        <fluent-icon icon="dismiss" size="16" />
      </button>
    </div>

    <div class="p-4 flex flex-col gap-6">
      <!-- Status -->
      <div>
        <label class="text-xs font-medium text-n-slate-11 mb-2 block">
          {{ $t('OPPORTUNITIES.DETAIL.STATUS_LABEL') }}
        </label>
        <div class="flex items-center gap-2">
          <span
            class="text-sm px-2.5 py-1 rounded-full capitalize font-medium"
            :class="statusBadgeClass"
          >
            {{
              $t(
                `OPPORTUNITIES.BOARD.STATUS.${opportunity.status.toUpperCase()}`
              )
            }}
          </span>

          <div class="flex items-center gap-1 ml-auto">
            <button
              v-if="opportunity.status !== 'won'"
              class="px-2 py-1 text-xs font-medium rounded bg-n-green-3 text-n-green-11 hover:bg-n-green-4 transition-colors"
              @click="setStatus('won')"
            >
              {{ $t('OPPORTUNITIES.BOARD.ACTIONS.MARK_WON') }}
            </button>
            <button
              v-if="opportunity.status !== 'lost'"
              class="px-2 py-1 text-xs font-medium rounded bg-n-red-3 text-n-red-11 hover:bg-n-red-4 transition-colors"
              @click="setStatus('lost')"
            >
              {{ $t('OPPORTUNITIES.BOARD.ACTIONS.MARK_LOST') }}
            </button>
            <button
              v-if="opportunity.status !== 'open'"
              class="px-2 py-1 text-xs font-medium rounded bg-n-slate-3 text-n-slate-11 hover:bg-n-slate-4 transition-colors"
              @click="setStatus('open')"
            >
              {{ $t('OPPORTUNITIES.BOARD.ACTIONS.REOPEN') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Contact -->
      <div v-if="opportunity.contact">
        <label class="text-xs font-medium text-n-slate-11 mb-2 block">
          {{ $t('OPPORTUNITIES.DETAIL.CONTACT_LABEL') }}
        </label>
        <div class="flex flex-col">
          <span class="text-sm text-n-slate-12 font-medium">{{
            opportunity.contact.name
          }}</span>
          <span class="text-xs text-n-slate-11">{{
            opportunity.contact.email
          }}</span>
        </div>
      </div>

      <!-- Assignee -->
      <div v-if="opportunity.assignee">
        <label class="text-xs font-medium text-n-slate-11 mb-2 block">
          {{ $t('OPPORTUNITIES.DETAIL.ASSIGNEE_LABEL') }}
        </label>
        <div class="flex flex-col">
          <span class="text-sm text-n-slate-12">{{
            opportunity.assignee.name
          }}</span>
        </div>
      </div>

      <!-- Origin Conversation -->
      <div v-if="opportunity.origin_conversation_id">
        <label class="text-xs font-medium text-n-slate-11 mb-2 block">
          {{ $t('OPPORTUNITIES.DETAIL.ORIGIN_CONVERSATION_LABEL') }}
        </label>
        <router-link
          :to="{
            name: 'inbox_conversation',
            params: { conversation_id: opportunity.origin_conversation_id },
          }"
          class="text-sm text-n-brand-11 hover:underline inline-flex items-center gap-1"
        >
          {{ $t('OPPORTUNITIES.DETAIL.VIEW_CONVERSATION') }}
          <fluent-icon icon="arrow-right" size="14" />
        </router-link>
      </div>
    </div>
  </div>
  <div
    v-else
    class="flex items-center justify-center h-full w-80 border-l border-n-weak bg-n-surface-1"
  >
    <span class="text-sm text-n-slate-11">{{
      $t('OPPORTUNITIES.DETAIL.NOT_FOUND')
    }}</span>
  </div>
</template>
