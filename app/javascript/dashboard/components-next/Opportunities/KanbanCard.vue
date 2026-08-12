<script setup>
import { computed, toRef } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useOpportunityCardFields } from 'dashboard/composables/useOpportunityCardFields';
import StartOpportunityConversationButton from 'dashboard/routes/dashboard/opportunities/components/StartOpportunityConversationButton.vue';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
});

defineEmits(['statusChanged', 'completeFields']);
const router = useRouter();
const store = useStore();

const {
  statusBadgeClass,
  isStale,
  configuredFields,
  timestampLabel,
  timestampTooltip,
} = useOpportunityCardFields(toRef(props, 'opportunity'));

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
  let classes = '';
  if (props.opportunity.origin_conversation_id) {
    classes = 'cursor-pointer hover:bg-n-surface-2 group';
  } else {
    classes = 'cursor-default grayscale border-dashed bg-n-surface-2 group';
  }

  if (props.opportunity.status && props.opportunity.status !== 'open') {
    classes += ' is-closed';
  }

  return classes;
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

const campaignAttribution = computed(() => {
  const {
    campaign_source_id,
    campaign_platform,
    campaign_name,
    campaign_adset_name,
    campaign_ad_name,
    campaign_resolution_status,
  } = props.opportunity;

  if (!campaign_source_id) return null;

  let icon = 'i-lucide-megaphone';
  if (['ig', 'instagram'].includes(campaign_platform))
    icon = 'i-lucide-instagram';
  else if (['fb', 'facebook'].includes(campaign_platform))
    icon = 'i-lucide-facebook';

  let label = '';
  if (campaign_resolution_status === 'resolved') {
    label = [campaign_name, campaign_adset_name, campaign_ad_name]
      .filter(Boolean)
      .join('\n');
  } else if (campaign_resolution_status === 'failed') {
    label = campaign_source_id;
  } else {
    // We cannot easily use i18n here without importing it, so fallback to simple text
    label = 'Resolving attribution...';
  }

  return { icon, label };
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
        <span
          v-tooltip.top="timestampTooltip"
          class="text-xs"
          :class="
            isStale
              ? 'bg-n-amber-3 text-n-amber-11 px-1.5 py-0.5 rounded-sm'
              : 'text-n-slate-10'
          "
        >
          {{ timestampLabel }}
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

    <div v-if="configuredFields.length > 0" class="flex flex-wrap gap-1.5 mt-2">
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

    <!-- Quick Actions Overlay -->
    <div
      class="absolute bottom-2 right-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
    >
      <StartOpportunityConversationButton
        v-if="!opportunity.origin_conversation_id"
        :opportunity="opportunity"
      />
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
        v-if="opportunity.status === 'open'"
        class="p-1 rounded transition-colors bg-n-brand-3 text-n-brand-11 hover:bg-n-brand-4"
        :title="
          hasUnmetRequirements
            ? $t('OPPORTUNITIES.BOARD.ACTIONS.COMPLETE_FIELDS')
            : $t('OPPORTUNITIES.BOARD.ACTIONS.EDIT')
        "
        @click.stop="$emit('completeFields', opportunity.id)"
      >
        <fluent-icon icon="edit" size="14" />
      </button>
    </div>
  </div>
</template>
