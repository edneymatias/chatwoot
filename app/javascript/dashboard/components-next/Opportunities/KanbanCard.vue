<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import {
  dynamicTime,
  shortTimestamp,
  getDayDifferenceFromNow,
} from 'shared/helpers/timeHelper';
import { getContrastingTextColor } from '@chatwoot/utils';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
});

defineEmits(['statusChanged', 'completeFields']);
const router = useRouter();
const store = useStore();
const { t, locale } = useI18n();

const statusBadgeClass = computed(() => {
  if (props.opportunity.status === 'won') return 'bg-n-teal-3 text-n-teal-11';
  if (props.opportunity.status === 'lost') return 'bg-n-ruby-3 text-n-ruby-11';
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

const isStale = computed(() => {
  if (
    !currentStage.value?.stale_after_days ||
    !props.opportunity.current_stage_entered_at
  ) {
    return false;
  }
  return (
    getDayDifferenceFromNow(
      new Date(),
      props.opportunity.current_stage_entered_at
    ) > currentStage.value.stale_after_days
  );
});

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

const pipelineCurrency = computed(
  () => store.getters['pipelineCurrencySetting/getCurrency']
);
const cardFieldConfigs = computed(
  () => store.getters['pipelineCardFieldConfigs/getRecords'] || []
);

const configuredFields = computed(() => {
  const fields = [];
  const attrs = props.opportunity.custom_attributes || {};

  cardFieldConfigs.value.forEach(config => {
    if (config.field_type === 'deal_value') {
      const rawValue = props.opportunity.value;
      if (rawValue !== null && rawValue !== undefined && rawValue !== '') {
        fields.push({
          id: config.id,
          color: config.color,
          textColor: getContrastingTextColor(config.color),
          value: formatCurrencyAmount(
            rawValue,
            pipelineCurrency.value,
            true // compact mode
          ),
          label: t('OPPORTUNITIES.DEAL_VALUE'),
        });
      }
    } else if (config.field_type === 'custom_attribute') {
      const defId = config.custom_attribute_definition_id;
      const def = store.getters['attributes/getAttributesByModel'](
        'opportunity_attribute'
      ).find(d => d.id === defId);
      if (def) {
        const rawValue = attrs[def.attribute_key];
        if (rawValue !== null && rawValue !== undefined && rawValue !== '') {
          let formattedValue = rawValue;
          if (def.attribute_display_type === 'currency') {
            formattedValue = formatCurrencyAmount(
              rawValue,
              pipelineCurrency.value,
              true // compact mode
            );
          } else if (def.attribute_display_type === 'date') {
            try {
              const dateObj = new Date(rawValue);
              // vue-i18n locale might be pt_BR, replace with pt-BR for Intl
              const localeCode = locale.value
                ? locale.value.replace('_', '-')
                : 'en-US';
              formattedValue = dateObj.toLocaleDateString(localeCode, {
                month: 'numeric',
                day: 'numeric',
              });
            } catch (e) {
              formattedValue = String(rawValue);
            }
          }
          fields.push({
            id: config.id,
            color: config.color,
            textColor: getContrastingTextColor(config.color),
            value: formattedValue,
            label: def.attribute_display_name,
          });
        }
      }
    }
  });
  return fields;
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
        <span
          v-if="opportunity.current_stage_entered_at || opportunity.created_at"
          v-tooltip.top="
            opportunity.current_stage_entered_at
              ? $t('OPPORTUNITIES.BOARD.TIME_IN_STAGE')
              : $t('OPPORTUNITIES.BOARD.TIME_SINCE_CREATED')
          "
          class="text-xs"
          :class="
            isStale
              ? 'bg-n-amber-3 text-n-amber-11 px-1.5 py-0.5 rounded-sm'
              : 'text-n-slate-10'
          "
        >
          {{
            shortTimestamp(
              dynamicTime(
                opportunity.current_stage_entered_at || opportunity.created_at
              )
            )
          }}
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
