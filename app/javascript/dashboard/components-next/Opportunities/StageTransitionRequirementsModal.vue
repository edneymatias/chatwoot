<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import OpportunityRequiredFieldsForm from './OpportunityRequiredFieldsForm.vue';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
  destinationStageId: {
    type: Number,
    required: true,
  },
  toIndex: {
    type: Number,
    default: undefined,
  },
  initialMissingFields: {
    type: Object,
    default: () => ({ custom_attribute_keys: [], requires_value: false }),
  },
});

const emit = defineEmits(['close', 'submit']);

const store = useStore();
const { t } = useI18n();

const customAttributes = ref({ ...props.opportunity.custom_attributes });
const dealValue = ref(props.opportunity.value);
const isSubmitting = ref(false);
const missingCustomAttributeKeys = ref([
  ...props.initialMissingFields.custom_attribute_keys,
]);
const missingDealValue = ref(props.initialMissingFields.requires_value);

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);
const destinationStage = computed(() =>
  store.getters['pipelineStages/stageById'](props.destinationStageId)
);

const allPreviousStages = computed(() => {
  if (!destinationStage.value) return [];
  return stages.value.filter(
    s =>
      (s.position ?? Infinity) <=
        (destinationStage.value.position ?? Infinity) &&
      s.id !== destinationStage.value.id
  );
});

const requiredDefs = computed(() => {
  if (
    !destinationStage.value ||
    !destinationStage.value.required_custom_attribute_definitions
  )
    return [];
  return destinationStage.value.required_custom_attribute_definitions;
});
const requiresDealValue = computed(
  () => destinationStage.value?.requires_deal_value || false
);

const optionalDefs = computed(() => {
  const defs = [];
  const requiredIds = requiredDefs.value.map(d => d.id);
  allPreviousStages.value.forEach(stage => {
    if (stage.required_custom_attribute_definitions) {
      stage.required_custom_attribute_definitions.forEach(def => {
        if (!requiredIds.includes(def.id) && !defs.find(d => d.id === def.id)) {
          defs.push(def);
        }
      });
    }
  });
  return defs;
});
const optionalRequiresDealValue = computed(() => {
  if (requiresDealValue.value) return false;
  return allPreviousStages.value.some(s => s.requires_deal_value);
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

const onSubmit = async () => {
  if (!validateForm()) return;

  isSubmitting.value = true;
  try {
    await store.dispatch('opportunities/moveCard', {
      id: props.opportunity.id,
      fromStageId: props.opportunity.pipeline_stage_id,
      toStageId: props.destinationStageId,
      toIndex: props.toIndex,
      custom_attributes: customAttributes.value,
      value: dealValue.value,
    });
    emit('submit');
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

const onClose = () => {
  emit('close');
};
</script>

<template>
  <woot-modal show size="modal-medium" @close="onClose">
    <woot-modal-header
      :header-title="
        t('OPPORTUNITIES.REQUIREMENTS_MODAL.TITLE') || 'Missing requirements'
      "
    />

    <div class="p-6 pt-2 flex flex-col gap-6">
      <div v-if="requiredDefs.length || requiresDealValue">
        <h3 class="font-semibold mb-4 text-n-slate-12">
          {{
            t('OPPORTUNITIES.REQUIREMENTS_MODAL.REQUIRED_SECTION') ||
            'Required for this stage'
          }}
        </h3>
        <OpportunityRequiredFieldsForm
          v-model:custom-attributes="customAttributes"
          v-model:deal-value="dealValue"
          :required-custom-attribute-definitions="requiredDefs"
          :requires-deal-value="requiresDealValue"
          :missing-custom-attribute-keys="missingCustomAttributeKeys"
          :missing-deal-value="missingDealValue"
        />
      </div>

      <div v-if="optionalDefs.length || optionalRequiresDealValue">
        <h3 class="font-semibold mb-4 text-n-slate-11">
          {{
            t('OPPORTUNITIES.REQUIREMENTS_MODAL.OPTIONAL_SECTION') ||
            'Optional (from previous stages)'
          }}
        </h3>
        <OpportunityRequiredFieldsForm
          v-model:custom-attributes="customAttributes"
          v-model:deal-value="dealValue"
          :optional-custom-attribute-definitions="optionalDefs"
          :requires-deal-value="optionalRequiresDealValue"
        />
      </div>

      <div class="flex justify-end gap-2 mt-4">
        <button
          class="px-4 py-2 text-sm font-medium bg-n-button-color text-n-slate-12 rounded-md hover:bg-n-alpha-2 transition-colors disabled:opacity-50 min-w-[100px]"
          @click="onClose"
        >
          {{ t('OPPORTUNITIES.REQUIREMENTS_MODAL.CANCEL') || 'Cancel' }}
        </button>
        <button
          :disabled="isSubmitting"
          class="px-4 py-2 text-sm font-medium bg-n-brand text-white rounded-md hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center min-w-[100px]"
          @click="onSubmit"
        >
          <span
            v-if="isSubmitting"
            class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"
          />
          <span v-else>{{
            t('OPPORTUNITIES.REQUIREMENTS_MODAL.SUBMIT') || 'Submit'
          }}</span>
        </button>
      </div>
    </div>
  </woot-modal>
</template>
