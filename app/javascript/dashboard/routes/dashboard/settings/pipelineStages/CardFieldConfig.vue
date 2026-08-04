<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import { SUPPORTED_PIPELINE_CURRENCIES } from 'dashboard/constants/pipelineCurrency';

const store = useStore();
const { t } = useI18n();

const isSubmitting = ref(false);

const selectedCurrency = ref('usd');

const selectedFields = ref([]);

const opportunityAttributes = computed(() =>
  store.getters['attributes/getAttributesByModel']('opportunity_attribute')
);

const cardFieldConfigs = computed(
  () => store.getters['pipelineCardFieldConfigs/getRecords'] || []
);

const pipelineCurrency = computed(
  () => store.getters['pipelineCurrencySetting/getCurrency']
);

onMounted(async () => {
  store.dispatch('attributes/get');
  await store.dispatch('pipelineCardFieldConfigs/fetch');
  await store.dispatch('pipelineCurrencySetting/fetch');

  selectedCurrency.value = pipelineCurrency.value;

  selectedFields.value = cardFieldConfigs.value.map(c => ({
    id:
      c.field_type === 'deal_value'
        ? 'deal_value'
        : c.custom_attribute_definition_id,
    type: c.field_type,
    color: c.color,
    configId: c.id,
  }));
});

const availableOptions = computed(() => {
  const options = opportunityAttributes.value.map(attr => ({
    id: attr.id,
    type: 'custom_attribute',
    label: attr.attribute_display_name,
    description: attr.attribute_description || attr.attribute_key,
  }));

  options.unshift({
    id: 'deal_value',
    type: 'deal_value',
    label: t('PIPELINE_STAGES_MGMT.CARD_FIELDS.DEAL_VALUE') || 'Deal Value',
    description:
      t('PIPELINE_STAGES_MGMT.CARD_FIELDS.DEAL_VALUE_DESC') ||
      'Monetary value of the deal',
  });

  return options;
});

const isChecked = optionId => {
  return selectedFields.value.some(f => f.id === optionId);
};

const getColor = optionId => {
  const field = selectedFields.value.find(f => f.id === optionId);
  return field ? field.color : '#000000';
};

const toggleField = (option, event) => {
  if (event.target.checked) {
    if (selectedFields.value.length < 3) {
      selectedFields.value.push({
        id: option.id,
        type: option.type,
        color: '#000000',
        configId: null,
      });
    } else {
      event.target.checked = false;
    }
  } else {
    selectedFields.value = selectedFields.value.filter(f => f.id !== option.id);
  }
};

const updateColor = (optionId, color) => {
  const field = selectedFields.value.find(f => f.id === optionId);
  if (field) {
    field.color = color;
  }
};

const submit = async () => {
  isSubmitting.value = true;
  try {
    const promises = [];

    if (selectedCurrency.value !== pipelineCurrency.value) {
      promises.push(
        store.dispatch('pipelineCurrencySetting/update', {
          currency: selectedCurrency.value,
        })
      );
    }

    const originalConfigs = cardFieldConfigs.value;

    const fieldsToCreate = selectedFields.value.filter(f => !f.configId);
    const fieldsToUpdate = selectedFields.value.filter(f => {
      if (!f.configId) return false;
      const original = originalConfigs.find(c => c.id === f.configId);
      return original && original.color !== f.color;
    });

    const fieldsToRemove = originalConfigs.filter(c => {
      const fieldId =
        c.field_type === 'deal_value'
          ? 'deal_value'
          : c.custom_attribute_definition_id;
      return !selectedFields.value.some(f => f.id === fieldId);
    });

    fieldsToCreate.forEach(f => {
      promises.push(
        store.dispatch('pipelineCardFieldConfigs/create', {
          field_type: f.type,
          custom_attribute_definition_id:
            f.type === 'custom_attribute' ? f.id : null,
          color: f.color,
        })
      );
    });

    fieldsToUpdate.forEach(f => {
      promises.push(
        store.dispatch('pipelineCardFieldConfigs/update', {
          id: f.configId,
          color: f.color,
        })
      );
    });

    fieldsToRemove.forEach(c => {
      promises.push(store.dispatch('pipelineCardFieldConfigs/destroy', c.id));
    });

    if (promises.length > 0) {
      await Promise.all(promises);
      await store.dispatch('pipelineCardFieldConfigs/fetch');
    }

    useAlert(
      t('PIPELINE_STAGES_MGMT.CARD_FIELDS.SAVE_SUCCESS') || 'Saved successfully'
    );
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error ||
      error?.message ||
      'Error updating card fields';
    useAlert(errorMessage);
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div class="flex-1 flex flex-col max-h-[calc(100vh-240px)] overflow-y-auto pt-4 pb-8">
    <div class="flex flex-col gap-8 max-w-4xl">
      <!-- Fields Section -->
      <div class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <label class="text-sm font-semibold text-n-slate-12">
            {{
              t('PIPELINE_STAGES_MGMT.CARD_FIELDS.FIELDS_LABEL') ||
              'Configured Fields'
            }}
          </label>
          <span class="text-xs text-n-slate-11">
            {{ selectedFields.length }}/3
            {{ t('PIPELINE_STAGES_MGMT.CARD_FIELDS.SELECTED') || 'selected' }}
          </span>
        </div>

        <div
          class="border border-n-weak rounded-xl bg-n-surface-1 overflow-visible"
        >
          <div
            v-for="(option, index) in availableOptions"
            :key="option.id"
            class="flex items-center justify-between p-4"
            :class="{
              'border-b border-n-weak': index !== availableOptions.length - 1,
            }"
          >
            <label class="flex items-center gap-3 cursor-pointer flex-1">
              <input
                type="checkbox"
                :checked="isChecked(option.id)"
                :disabled="!isChecked(option.id) && selectedFields.length >= 3"
                class="w-4 h-4 text-n-brand-9 border-n-weak rounded focus:ring-n-brand-9"
                @change="toggleField(option, $event)"
              />
              <div class="flex flex-col">
                <span class="text-sm text-n-slate-12 font-medium">{{
                  option.label
                }}</span>
                <span class="text-xs text-n-slate-11">{{
                  option.description
                }}</span>
              </div>
            </label>
            <div v-if="isChecked(option.id)" class="ml-4 shrink-0">
              <ColorPicker
                :model-value="getColor(option.id)"
                @update:model-value="updateColor(option.id, $event)"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Currency Section -->
      <div class="flex flex-col gap-3">
        <label class="text-sm font-semibold text-n-slate-12">
          {{
            t('PIPELINE_STAGES_MGMT.CARD_FIELDS.CURRENCY_LABEL') || 'Currency'
          }}
        </label>
        <select
          v-model="selectedCurrency"
          class="w-full sm:w-64 border border-n-weak bg-n-surface-1 rounded-md text-sm p-2 outline-none focus:border-n-brand-9"
        >
          <option
            v-for="currency in SUPPORTED_PIPELINE_CURRENCIES"
            :key="currency"
            :value="currency"
          >
            {{ currency.toUpperCase() }}
          </option>
        </select>
      </div>

      <!-- Actions -->
      <div class="flex justify-start mt-2">
        <button
          :disabled="isSubmitting"
          class="px-4 py-2 text-sm font-medium bg-n-brand text-white rounded-md hover:brightness-110 transition-all disabled:opacity-50 flex items-center justify-center min-w-[100px]"
          @click="submit"
        >
          <span
            v-if="isSubmitting"
            class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"
          />
          <span v-else>{{
            t('PIPELINE_STAGES_MGMT.CARD_FIELDS.SAVE') || 'Save Changes'
          }}</span>
        </button>
      </div>
    </div>
  </div>
</template>
