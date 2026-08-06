<script setup>
import { computed, ref, onMounted } from 'vue';
import { useStore } from 'vuex';
import OpportunityRequiredFieldsForm from './OpportunityRequiredFieldsForm.vue';

const props = defineProps({
  opportunityId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'updated']);

const store = useStore();

const isSubmitting = ref(false);
const title = ref('');
const customAttributes = ref({});
const dealValue = ref(null);
const assigneeId = ref(null);
const missingCustomAttributeKeys = ref([]);
const missingDealValue = ref(false);

const agents = computed(() => store.getters['agents/getVerifiedAgents']);

const opportunity = computed(
  () => store.state.opportunities.byId[props.opportunityId]
);
const currentStage = computed(() => {
  if (!opportunity.value) return null;
  return store.getters['pipelineStages/stageById'](
    opportunity.value.pipeline_stage_id
  );
});

const requiredDefs = computed(
  () => currentStage.value?.required_custom_attribute_definitions || []
);
const requiresDealValue = computed(
  () => currentStage.value?.requires_deal_value || false
);

onMounted(() => {
  if (opportunity.value) {
    title.value = opportunity.value.title;
    customAttributes.value = { ...(opportunity.value.custom_attributes || {}) };
    dealValue.value = opportunity.value.value;
    assigneeId.value = opportunity.value.assignee_id || null;
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
      custom_attributes: customAttributes.value,
      value: dealValue.value,
      assignee_id: assigneeId.value,
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

const onClose = () => emit('close');
</script>

<template>
  <woot-modal show size="modal-medium" @close="onClose">
    <woot-modal-header
      :header-title="
        $t('OPPORTUNITIES.BOARD.ACTIONS.EDIT') || 'Edit Opportunity'
      "
    />

    <div class="p-6 pt-2 flex flex-col gap-4">
      <div v-if="opportunity" class="flex flex-col gap-1 mb-4">
        <label class="text-sm font-medium text-n-slate-12">
          {{
            $t('OPPORTUNITIES.CREATE_MODAL.TITLE_LABEL') || 'Opportunity Title'
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
        <select
          v-model="assigneeId"
          class="w-full border border-n-slate-3 rounded-md px-3 py-2 text-sm focus:outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
        >
          <option :value="null">
            {{ $t('OPPORTUNITIES.BACKFILL_MODAL.ASSIGNEE_UNASSIGNED') }}
          </option>
          <option v-for="agent in agents" :key="agent.id" :value="agent.id">
            {{ agent.name }}
          </option>
        </select>
      </div>

      <OpportunityRequiredFieldsForm
        v-model:custom-attributes="customAttributes"
        v-model:deal-value="dealValue"
        :required-custom-attribute-definitions="requiredDefs"
        :optional-custom-attribute-definitions="[]"
        :requires-deal-value="requiresDealValue"
        :missing-custom-attribute-keys="missingCustomAttributeKeys"
        :missing-deal-value="missingDealValue"
      />

      <div class="flex justify-end gap-2 mt-4">
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
