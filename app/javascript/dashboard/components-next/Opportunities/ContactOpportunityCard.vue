<script setup>
import { computed, toRef } from 'vue';
import { useStore } from 'vuex';
import { useOpportunityCardFields } from 'dashboard/composables/useOpportunityCardFields';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
  isCurrentConversation: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['click']);

const store = useStore();

const {
  statusBadgeClass,
  isStale,
  configuredFields,
  timestampLabel,
  timestampTooltip,
  campaignAttribution,
} = useOpportunityCardFields(toRef(props, 'opportunity'));

const currentStage = computed(() =>
  store.getters['pipelineStages/stageById'](props.opportunity.pipeline_stage_id)
);
</script>

<template>
  <div
    class="flex flex-col gap-1 px-4 py-3 border-b last:border-b-0 cursor-pointer hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3"
    :class="isCurrentConversation ? 'border-n-brand' : 'border-n-slate-3'"
    @click="$emit('click', opportunity.id)"
  >
    <div class="flex justify-between items-start gap-2">
      <h3
        class="text-n-slate-12 text-sm font-medium leading-5 truncate flex items-center gap-1.5"
        :title="opportunity.title"
      >
        <span
          v-if="campaignAttribution"
          class="size-4 shrink-0 text-n-slate-11"
          :class="[campaignAttribution.icon]"
          :title="campaignAttribution.label"
        />
        <span class="truncate">{{ opportunity.title }}</span>
      </h3>
      <span
        class="text-[10px] px-1.5 py-0.5 rounded-full capitalize font-medium shrink-0"
        :class="statusBadgeClass"
      >
        {{
          $t(
            `OPPORTUNITIES.BOARD.STATUS.${(opportunity.status || 'open').toUpperCase()}`
          )
        }}
      </span>
    </div>

    <div class="flex items-center justify-between text-xs text-n-slate-11">
      <span v-if="currentStage" class="truncate" :title="currentStage.name">
        {{ currentStage.name }}
      </span>
      <span
        v-tooltip.top="timestampTooltip"
        class="shrink-0 leading-4 text-xxs"
        :class="
          isStale
            ? 'bg-n-amber-3 text-n-amber-11 px-1.5 py-0.5 rounded-sm'
            : 'text-n-slate-10'
        "
      >
        {{ timestampLabel }}
      </span>
    </div>

    <div v-if="configuredFields.length > 0" class="flex flex-wrap gap-1.5">
      <span
        v-for="field in configuredFields"
        :key="field.id"
        class="inline-flex items-center px-1.5 py-0.5 rounded text-[11px] font-medium max-w-full truncate"
        :style="{ backgroundColor: field.color, color: field.textColor }"
        :title="field.label"
      >
        <span class="truncate">{{ field.value }}</span>
      </span>
    </div>
  </div>
</template>
