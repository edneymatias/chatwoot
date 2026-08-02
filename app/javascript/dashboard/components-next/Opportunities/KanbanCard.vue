<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
});

defineEmits(['statusChanged', 'completeFields']);
const router = useRouter();
const store = useStore();

const statusBadgeClass = computed(() => {
  if (props.opportunity.status === 'won') return 'bg-n-green-3 text-n-green-11';
  if (props.opportunity.status === 'lost') return 'bg-n-red-3 text-n-red-11';
  return 'bg-n-slate-3 text-n-slate-11';
});

const handleCardClick = () => {
  if (!props.opportunity.origin_conversation_id) return;
  router.push({
    name: 'opportunities_conversation',
    params: {
      conversationId:
        props.opportunity.origin_conversation_display_id ||
        props.opportunity.origin_conversation_id,
    },
  });
};

const cardClass = computed(() => {
  if (props.opportunity.origin_conversation_id) {
    return 'cursor-pointer hover:bg-n-surface-2 group';
  }
  return 'cursor-default grayscale border-dashed bg-n-surface-2 group';
});

const currentStage = computed(() =>
  store.getters['pipelineStages/stageById'](props.opportunity.pipeline_stage_id)
);

const hasUnmetRequirements = computed(() => {
  if (!currentStage.value) return false;

  const requiredDefs =
    currentStage.value.required_custom_attribute_definitions || [];
  const requiresDealValue = currentStage.value.requires_deal_value || false;
  const attrs = props.opportunity.custom_attributes || {};

  const isAnyDefMissing = requiredDefs.some(def => {
    return (
      attrs[def.attribute_key] === undefined ||
      attrs[def.attribute_key] === null ||
      attrs[def.attribute_key] === ''
    );
  });

  if (isAnyDefMissing) return true;

  if (
    requiresDealValue &&
    (props.opportunity.value === undefined ||
      props.opportunity.value === null ||
      props.opportunity.value === '')
  ) {
    return true;
  }

  return false;
});
</script>

<template>
  <div
    class="bg-n-surface-1 border border-n-weak rounded-md p-3 shadow-sm transition-colors duration-200 relative"
    :class="cardClass"
    @click="handleCardClick"
  >
    <div class="flex justify-between items-start mb-2 gap-2">
      <h3
        class="text-n-slate-12 text-sm font-medium leading-5 truncate"
        :title="opportunity.title"
      >
        {{ opportunity.title }}
      </h3>
      <div class="flex items-center gap-2 shrink-0">
        <span
          v-if="opportunity.status && opportunity.status !== 'open'"
          class="text-[10px] px-1.5 py-0.5 rounded-full capitalize font-medium"
          :class="statusBadgeClass"
        >
          {{
            $t(`OPPORTUNITIES.BOARD.STATUS.${opportunity.status.toUpperCase()}`)
          }}
        </span>
        <span v-if="opportunity.created_at" class="text-xs text-n-slate-10">
          {{ shortTimestamp(dynamicTime(opportunity.created_at)) }}
        </span>
      </div>
    </div>

    <div class="flex items-center text-xs text-n-slate-11 mb-1">
      <div
        v-if="opportunity.contact"
        class="flex items-center truncate max-w-[60%] gap-1.5"
        :title="opportunity.contact.name"
      >
        <Avatar
          :name="opportunity.contact.name"
          :src="opportunity.contact.avatar_url"
          :size="24"
        />
        <span class="truncate">{{ opportunity.contact.name }}</span>
      </div>
      <div v-if="opportunity.contact && opportunity.assignee" class="mx-1.5">
        {{ '\u2022' }}
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
        <fluent-icon icon="arrow-reply" size="14" />
      </button>
      <button
        v-if="hasUnmetRequirements"
        class="p-1 rounded transition-colors bg-n-brand-3 text-n-brand-11 hover:bg-n-brand-4"
        :title="$t('OPPORTUNITIES.BOARD.ACTIONS.COMPLETE_FIELDS')"
        @click.stop="$emit('completeFields', opportunity.id)"
      >
        <fluent-icon icon="edit" size="14" />
      </button>
    </div>
  </div>
</template>
