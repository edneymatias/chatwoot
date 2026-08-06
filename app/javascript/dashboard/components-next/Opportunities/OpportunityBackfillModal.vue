<script setup>
import { computed, ref, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OpportunityRequiredFieldsForm from './OpportunityRequiredFieldsForm.vue';

const props = defineProps({
  opportunityId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'updated']);

const store = useStore();
const { t } = useI18n();

const isSubmitting = ref(false);
const isReopening = ref(false);
const title = ref('');
const customAttributes = ref({});
const dealValue = ref(null);
const assigneeId = ref(null);
const status = ref('open');
const missingCustomAttributeKeys = ref([]);
const missingDealValue = ref(false);

const statusOptions = computed(() =>
  ['open', 'won', 'lost'].map(value => ({
    value,
    label: t(`OPPORTUNITIES.BOARD.STATUS.${value.toUpperCase()}`),
  }))
);

const agents = computed(() => store.getters['agents/getVerifiedAgents']);

const opportunity = computed(
  () => store.state.opportunities.byId[props.opportunityId]
);

const isClosed = computed(
  () => !!opportunity.value?.status && opportunity.value.status !== 'open'
);

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);

const selectedStageId = ref(null);

const destinationStage = computed(() => {
  if (!selectedStageId.value) return null;
  return store.getters['pipelineStages/stageById'](selectedStageId.value);
});

const savedStage = computed(() =>
  store.getters['pipelineStages/stageById'](
    opportunity.value?.pipeline_stage_id
  )
);

const isForwardMove = computed(() => {
  if (!destinationStage.value || !savedStage.value) return false;
  return destinationStage.value.position > savedStage.value.position;
});

const closingRequiredDefs = computed(() => {
  if (status.value === 'open') return [];
  const records =
    status.value === 'won'
      ? store.getters['pipelineClosingRequiredFields/requiredForWon']
      : store.getters['pipelineClosingRequiredFields/requiredForLost'];
  const allDefs = store.getters['attributes/getAttributesByModel'](
    'opportunity_attribute'
  );
  const ids = records.map(r => r.custom_attribute_definition_id);
  return allDefs.filter(def => ids.includes(def.id));
});

const requiredDefs = computed(() => {
  const stageDefs = isForwardMove.value
    ? destinationStage.value?.required_custom_attribute_definitions || []
    : [];
  const merged = [...stageDefs];
  closingRequiredDefs.value.forEach(def => {
    if (!merged.some(d => d.id === def.id)) merged.push(def);
  });
  return merged;
});
const requiresDealValue = computed(
  () =>
    isForwardMove.value &&
    (destinationStage.value?.requires_deal_value || false)
);

const optionalCustomAttributeDefinitions = computed(() => {
  const allDefs = store.getters['attributes/getAttributesByModel'](
    'opportunity_attribute'
  );
  const requiredIds = requiredDefs.value.map(def => def.id);
  return allDefs.filter(def => !requiredIds.includes(def.id));
});

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('pipelineClosingRequiredFields/fetch');
  if (opportunity.value) {
    title.value = opportunity.value.title;
    customAttributes.value = { ...(opportunity.value.custom_attributes || {}) };
    dealValue.value = opportunity.value.value;
    assigneeId.value = opportunity.value.assignee_id || null;
    selectedStageId.value = opportunity.value.pipeline_stage_id;
    status.value = opportunity.value.status || 'open';
  }
});

const validateForm = () => {
  let isValid = true;
  missingCustomAttributeKeys.value = [];
  missingDealValue.value = false;

  requiredDefs.value.forEach(def => {
    if (
      customAttributes.value[def.attribute_key] === undefined ||
      customAttributes.value[def.attribute_key] === null ||
      customAttributes.value[def.attribute_key] === ''
    ) {
      missingCustomAttributeKeys.value.push(def.attribute_key);
      isValid = false;
    }
  });

  if (
    requiresDealValue.value &&
    (dealValue.value === undefined ||
      dealValue.value === null ||
      dealValue.value === '')
  ) {
    missingDealValue.value = true;
    isValid = false;
  }

  return isValid;
};

const submit = async () => {
  if (!validateForm()) return;

  isSubmitting.value = true;
  try {
    await store.dispatch('opportunities/updateOpportunity', {
      id: props.opportunityId,
      title: title.value,
      status: status.value,
      custom_attributes: customAttributes.value,
      value: dealValue.value,
      assignee_id: assigneeId.value,
      pipeline_stage_id: selectedStageId.value,
    });
    emit('updated', opportunity.value);
    emit('close');
  } catch (error) {
    if (
      error.response?.status === 422 &&
      error.response?.data?.missing_required_fields
    ) {
      const missing = error.response.data.missing_required_fields;
      missingCustomAttributeKeys.value = missing.custom_attribute_keys || [];
      missingDealValue.value = missing.requires_value || false;
    }
  } finally {
    isSubmitting.value = false;
  }
};

const reopenOpportunity = async () => {
  isReopening.value = true;
  try {
    await store.dispatch('opportunities/updateOpportunity', {
      id: props.opportunityId,
      status: 'open',
    });
    status.value = 'open';
    selectedStageId.value = opportunity.value?.pipeline_stage_id;
  } finally {
    isReopening.value = false;
  }
};

const onClose = () => emit('close');
</script>

<template>
  <woot-modal show size="modal-medium" @close="onClose">
    <woot-modal-header
      :header-title="
        $t('OPPORTUNITIES.BOARD.ACTIONS.EDIT') || 'Edit Opportunity'
      "
    />

    <div class="flex flex-col max-h-[80vh]">
      <div class="p-6 pt-2 flex flex-col gap-4 overflow-y-auto">
        <div v-if="opportunity" class="flex flex-col gap-1 mb-4">
          <label class="text-sm font-medium text-n-slate-12">
            {{
              $t('OPPORTUNITIES.CREATE_MODAL.TITLE_LABEL') ||
              'Opportunity Title'
            }}
          </label>
          <input
            v-model="title"
            type="text"
            class="w-full border border-n-slate-3 rounded-md px-3 py-2 text-sm focus:outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
          />
        </div>

        <div class="flex flex-col gap-1 mb-4">
          <label class="text-sm font-medium text-n-slate-12">
            {{ $t('OPPORTUNITIES.BACKFILL_MODAL.ASSIGNEE_LABEL') }}
          </label>
          <div class="relative">
            <select
              v-model="assigneeId"
              class="w-full appearance-none bg-none border border-n-slate-3 rounded-md px-3 py-2 pr-10 text-sm focus:outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
            >
              <option :value="null">
                {{ $t('OPPORTUNITIES.BACKFILL_MODAL.ASSIGNEE_UNASSIGNED') }}
              </option>
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">
                {{ agent.name }}
              </option>
            </select>
            <div
              class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none"
            >
              <Icon
                icon="i-lucide-chevron-down"
                class="size-4 text-n-slate-11"
              />
            </div>
          </div>
        </div>

        <div v-if="isClosed" class="flex flex-col gap-1 mb-4">
          <label class="text-sm font-medium text-n-slate-12">
            {{ $t('OPPORTUNITIES.BACKFILL_MODAL.STATUS_LABEL') }}
          </label>
          <div class="flex items-center justify-between gap-2">
            <span
              class="text-[10px] px-1.5 py-0.5 rounded-full capitalize font-medium"
              :class="
                status === 'won'
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-ruby-3 text-n-ruby-11'
              "
            >
              {{ $t(`OPPORTUNITIES.BOARD.STATUS.${status.toUpperCase()}`) }}
            </span>
            <button
              type="button"
              :disabled="isReopening"
              class="px-3 py-1.5 text-xs font-medium bg-n-button-color text-n-slate-12 rounded-md hover:bg-n-alpha-2 transition-colors disabled:opacity-50"
              @click="reopenOpportunity"
            >
              {{ $t('OPPORTUNITIES.BOARD.ACTIONS.REOPEN') }}
            </button>
          </div>
        </div>
        <div v-else class="flex flex-col gap-1 mb-4">
          <label class="text-sm font-medium text-n-slate-12">
            {{ $t('OPPORTUNITIES.BACKFILL_MODAL.STATUS_LABEL') }}
          </label>
          <div class="relative">
            <select
              v-model="status"
              class="w-full appearance-none bg-none border border-n-slate-3 rounded-md px-3 py-2 pr-10 text-sm focus:outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
            >
              <option
                v-for="option in statusOptions"
                :key="option.value"
                :value="option.value"
              >
                {{ option.label }}
              </option>
            </select>
            <div
              class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none"
            >
              <Icon
                icon="i-lucide-chevron-down"
                class="size-4 text-n-slate-11"
              />
            </div>
          </div>
        </div>

        <div v-if="status !== 'open'" class="flex flex-col gap-1 mb-4">
          <label class="text-sm font-medium text-n-slate-12">
            {{ $t('OPPORTUNITIES.BACKFILL_MODAL.STAGE_LABEL') }}
          </label>
          <span class="text-sm text-n-slate-12">{{
            destinationStage?.name
          }}</span>
        </div>
        <div v-else class="flex flex-col gap-1 mb-4">
          <label class="text-sm font-medium text-n-slate-12">
            {{ $t('OPPORTUNITIES.BACKFILL_MODAL.STAGE_LABEL') }}
          </label>
          <div class="relative">
            <select
              v-model="selectedStageId"
              class="w-full appearance-none bg-none border border-n-slate-3 rounded-md px-3 py-2 pr-10 text-sm focus:outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
            >
              <option v-for="stage in stages" :key="stage.id" :value="stage.id">
                {{ stage.name }}
              </option>
            </select>
            <div
              class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none"
            >
              <Icon
                icon="i-lucide-chevron-down"
                class="size-4 text-n-slate-11"
              />
            </div>
          </div>
        </div>

        <OpportunityRequiredFieldsForm
          v-model:custom-attributes="customAttributes"
          v-model:deal-value="dealValue"
          :required-custom-attribute-definitions="requiredDefs"
          :optional-custom-attribute-definitions="
            optionalCustomAttributeDefinitions
          "
          :requires-deal-value="requiresDealValue"
          :missing-custom-attribute-keys="missingCustomAttributeKeys"
          :missing-deal-value="missingDealValue"
        />
        <p class="text-xs text-n-slate-11 -mt-2">
          {{ $t('OPPORTUNITIES.BACKFILL_MODAL.DEAL_VALUE_ALWAYS_EDITABLE') }}
        </p>
      </div>
      <div
        class="flex justify-end gap-2 px-6 py-4 border-t border-n-slate-3 shrink-0"
      >
        <button
          class="px-4 py-2 text-sm font-medium bg-n-button-color text-n-slate-12 rounded-md hover:bg-n-alpha-2 transition-colors disabled:opacity-50 min-w-[100px]"
          @click="onClose"
        >
          {{ $t('OPPORTUNITIES.BACKFILL_MODAL.CANCEL') || 'Cancel' }}
        </button>
        <button
          :disabled="isSubmitting"
          class="px-4 py-2 text-sm font-medium bg-n-brand text-white rounded-md hover:brightness-110 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center min-w-[100px]"
          @click="submit"
        >
          <span
            v-if="isSubmitting"
            class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"
          />
          <span v-else>{{
            $t('OPPORTUNITIES.BACKFILL_MODAL.SUBMIT') || 'Save'
          }}</span>
        </button>
      </div>
    </div>
  </woot-modal>
</template>
