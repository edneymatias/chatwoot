<script setup>
import { computed } from 'vue';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
});

defineEmits(['click', 'status-changed']);

const statusBadgeClass = computed(() => {
  if (props.opportunity.status === 'won') return 'bg-n-green-3 text-n-green-11';
  if (props.opportunity.status === 'lost') return 'bg-n-red-3 text-n-red-11';
  return 'bg-n-slate-3 text-n-slate-11';
});
</script>

<template>
  <div
    class="bg-n-surface-1 border border-n-weak rounded-md p-3 shadow-sm cursor-pointer hover:bg-n-surface-2 transition-colors duration-200 group relative"
    @click="$emit('click', opportunity.id)"
  >
    <div class="flex justify-between items-start mb-2 gap-2">
      <h3
        class="text-n-slate-12 text-sm font-medium leading-5 truncate"
        :title="opportunity.title"
      >
        {{ opportunity.title }}
      </h3>
      <span
        v-if="opportunity.status && opportunity.status !== 'open'"
        class="text-[10px] px-1.5 py-0.5 rounded-full capitalize shrink-0 font-medium"
        :class="statusBadgeClass"
      >
        {{
          $t(`OPPORTUNITIES.BOARD.STATUS.${opportunity.status.toUpperCase()}`)
        }}
      </span>
    </div>

    <div class="flex items-center text-xs text-n-slate-11 mb-1">
      <div
        v-if="opportunity.contact"
        class="flex items-center truncate max-w-[60%]"
        :title="opportunity.contact.name"
      >
        <span class="truncate">{{ opportunity.contact.name }}</span>
      </div>
      <div v-if="opportunity.contact && opportunity.assignee" class="mx-1.5">
        •
      </div>
      <div
        v-if="opportunity.assignee"
        class="flex items-center truncate"
        :title="opportunity.assignee.name"
      >
        <span class="truncate">{{ opportunity.assignee.name }}</span>
      </div>
    </div>

    <!-- Quick Actions Overlay -->
    <div
      class="absolute bottom-2 right-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
    >
      <button
        v-if="opportunity.status !== 'won'"
        class="p-1 rounded bg-n-green-3 text-n-green-11 hover:bg-n-green-4 transition-colors"
        :title="$t('OPPORTUNITIES.BOARD.ACTIONS.MARK_WON')"
        @click.stop="
          $emit('statusChanged', { id: opportunity.id, status: 'won' })
        "
      >
        <fluent-icon icon="checkmark-circle" size="14" />
      </button>
      <button
        v-if="opportunity.status !== 'lost'"
        class="p-1 rounded bg-n-red-3 text-n-red-11 hover:bg-n-red-4 transition-colors"
        :title="$t('OPPORTUNITIES.BOARD.ACTIONS.MARK_LOST')"
        @click.stop="
          $emit('statusChanged', { id: opportunity.id, status: 'lost' })
        "
      >
        <fluent-icon icon="dismiss-circle" size="14" />
      </button>
      <button
        v-if="opportunity.status !== 'open'"
        class="p-1 rounded bg-n-slate-3 text-n-slate-11 hover:bg-n-slate-4 transition-colors"
        :title="$t('OPPORTUNITIES.BOARD.ACTIONS.REOPEN')"
        @click.stop="
          $emit('statusChanged', { id: opportunity.id, status: 'open' })
        "
      >
        <fluent-icon icon="arrow-counterclockwise" size="14" />
      </button>
    </div>
  </div>
</template>
