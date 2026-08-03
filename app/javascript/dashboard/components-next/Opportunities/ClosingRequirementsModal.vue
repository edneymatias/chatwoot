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
  outcome: {
    type: String,
    required: true,
  },
  initialMissingFields: {
    type: Object,
    default: () => ({ custom_attribute_keys: [] }),
  },
});

const emit = defineEmits(['close', 'submit']);

const store = useStore();
const { t } = useI18n();

const customAttributes = ref({ ...props.opportunity.custom_attributes });
const isSubmitting = ref(false);
const missingCustomAttributeKeys = ref([
  ...(props.initialMissingFields.custom_attribute_keys || []),
]);

const opportunityAttributes = computed(() =>
  store.getters['attributes/getAttributesByModel']('opportunity_attribute')
);

const requiredDefs = computed(() => {
  return opportunityAttributes.value.filter(attr =>
    missingCustomAttributeKeys.value.includes(attr.attribute_key)
  );
});

const validateForm = () => {
  let isValid = true;
  missingCustomAttributeKeys.value = [];

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

  return isValid;
};

const onSubmit = async () => {
  if (!validateForm()) return;

  isSubmitting.value = true;
  try {
    await store.dispatch('opportunities/setStatus', {
      id: props.opportunity.id,
      status: props.outcome,
      custom_attributes: customAttributes.value,
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
      <div v-if="requiredDefs.length">
        <h3 class="font-semibold mb-4 text-n-slate-12">
          {{
            t('OPPORTUNITIES.REQUIREMENTS_MODAL.REQUIRED_SECTION') ||
            'Required for this stage'
          }}
        </h3>
        <OpportunityRequiredFieldsForm
          v-model:custom-attributes="customAttributes"
          :required-custom-attribute-definitions="requiredDefs"
          :missing-custom-attribute-keys="missingCustomAttributeKeys"
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
