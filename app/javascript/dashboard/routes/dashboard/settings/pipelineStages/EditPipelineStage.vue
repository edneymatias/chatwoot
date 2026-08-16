<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import StageDescriptionEditor from 'dashboard/components-next/Opportunities/StageDescriptionEditor.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  stage: { type: Object, required: true },
});

const emit = defineEmits(['close']);
const store = useStore();
const { t } = useI18n();

const name = ref('');
const description = ref('');
const isSubmitting = ref(false);

const requiresDealValue = ref(false);
const selectedAttributeIds = ref([]);
const accentColor = ref('');
const totalDisplayMode = ref('value_sum');
const staleAfterDays = ref('');

const canSubmit = computed(() => name.value.trim().length > 0);

const opportunityAttributes = computed(() =>
  store.getters['attributes/getAttributesByModel']('opportunity_attribute')
);

onMounted(() => {
  const currentStage =
    store.getters['pipelineStages/stageById'](props.stage.id) || props.stage;

  name.value = currentStage.name || '';
  description.value = currentStage.description || '';
  requiresDealValue.value = currentStage.requires_deal_value || false;
  accentColor.value = currentStage.accent_color || '';
  totalDisplayMode.value = currentStage.total_display_mode || 'value_sum';
  staleAfterDays.value = currentStage.stale_after_days ?? '';

  store.dispatch('attributes/get');
  const requiredDefs = currentStage.required_custom_attribute_definitions || [];
  selectedAttributeIds.value = requiredDefs.map(def => def.id);
});

const onClose = () => emit('close');

const submit = async () => {
  if (!canSubmit.value) return;
  isSubmitting.value = true;
  try {
    await store.dispatch('pipelineStages/update', {
      id: props.stage.id,
      name: name.value.trim(),
      description: description.value ? description.value.trim() : '',
      requires_deal_value: requiresDealValue.value,
      accent_color: accentColor.value || null,
      total_display_mode: totalDisplayMode.value,
      stale_after_days:
        staleAfterDays.value === '' ? null : Number(staleAfterDays.value),
      required_custom_attribute_definition_ids: selectedAttributeIds.value,
    });

    onClose();
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error ||
      error?.response?.data?.message ||
      error?.message ||
      t('PIPELINE_STAGES_MGMT.EDIT.API.ERROR_MESSAGE') ||
      'Error updating stage';
    useAlert(errorMessage);
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <woot-modal :show="show" :on-close="onClose" size="modal-medium">
    <woot-modal-header :header-title="$t('PIPELINE_STAGES_MGMT.EDIT.TITLE')" />

    <div class="p-6 pt-2 flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('PIPELINE_STAGES_MGMT.FORM.NAME_LABEL') }}
        </label>
        <input
          v-model="name"
          type="text"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('PIPELINE_STAGES_MGMT.FORM.DESC_LABEL') }}
        </label>
        <StageDescriptionEditor v-model="description" />
      </div>

      <div class="flex flex-col gap-2 mt-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{
            t('PIPELINE_STAGES_MGMT.REQUIREMENTS.DEAL_VALUE_LABEL') ||
            'Deal Value'
          }}
        </label>
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            v-model="requiresDealValue"
            type="checkbox"
            class="w-4 h-4 text-n-brand-9 border-n-weak rounded focus:ring-n-brand-9"
          />
          <span class="text-sm text-n-slate-11">
            {{
              t('PIPELINE_STAGES_MGMT.REQUIREMENTS.DEAL_VALUE_HELP') ||
              'Require Deal Value for this stage'
            }}
          </span>
        </label>
      </div>

      <div class="flex flex-col gap-2 mt-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{
            t('PIPELINE_STAGES_MGMT.FORM.DISPLAY_MODE_LABEL') ||
            'Lane Total Display'
          }}
        </label>
        <div class="flex gap-4">
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              v-model="totalDisplayMode"
              type="radio"
              value="value_sum"
              class="w-4 h-4 text-n-brand-9 border-n-weak focus:ring-n-brand-9"
            />
            <span class="text-sm text-n-slate-11">
              {{
                t('PIPELINE_STAGES_MGMT.FORM.DISPLAY_MODE_VALUE') ||
                'Total value'
              }}
            </span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              v-model="totalDisplayMode"
              type="radio"
              value="count"
              class="w-4 h-4 text-n-brand-9 border-n-weak focus:ring-n-brand-9"
            />
            <span class="text-sm text-n-slate-11">
              {{ t('PIPELINE_STAGES_MGMT.FORM.DISPLAY_MODE_COUNT') || 'Count' }}
            </span>
          </label>
        </div>
      </div>

      <div class="flex flex-col gap-2 mt-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{
            t('PIPELINE_STAGES_MGMT.FORM.ACCENT_COLOR_LABEL') || 'Accent Color'
          }}
        </label>
        <div class="flex items-center gap-4">
          <ColorPicker v-model="accentColor" />
          <button
            v-if="accentColor"
            class="text-xs text-n-brand-9 hover:underline"
            @click="accentColor = ''"
          >
            {{ t('PIPELINE_STAGES_MGMT.FORM.CLEAR_COLOR') || 'Clear Color' }}
          </button>
        </div>
      </div>

      <div class="flex flex-col gap-2 mt-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('PIPELINE_STAGES_MGMT.FORM.STALE_AFTER_DAYS_LABEL') }}
        </label>
        <div class="flex flex-col gap-1">
          <input
            v-model="staleAfterDays"
            type="number"
            min="1"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
          />
          <span class="text-sm text-n-slate-11">
            {{ $t('PIPELINE_STAGES_MGMT.FORM.STALE_AFTER_DAYS_HELP') }}
          </span>
        </div>
      </div>

      <div class="flex flex-col gap-2 mt-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{
            t('PIPELINE_STAGES_MGMT.REQUIREMENTS.ATTRIBUTES_LABEL') ||
            'Required Custom Attributes'
          }}
        </label>

        <div
          v-if="opportunityAttributes.length === 0"
          class="text-sm text-n-slate-11"
        >
          {{
            t('PIPELINE_STAGES_MGMT.REQUIREMENTS.NO_ATTRIBUTES') ||
            'No opportunity custom attributes available.'
          }}
        </div>

        <div
          v-else
          class="flex flex-col gap-2 border border-n-weak rounded-md p-4 bg-n-surface-1 max-h-60 overflow-y-auto"
        >
          <label
            v-for="attr in opportunityAttributes"
            :key="attr.id"
            class="flex items-center gap-2 cursor-pointer"
          >
            <input
              v-model="selectedAttributeIds"
              type="checkbox"
              :value="attr.id"
              class="w-4 h-4 text-n-brand-9 border-n-weak rounded focus:ring-n-brand-9"
            />
            <div class="flex flex-col">
              <span class="text-sm text-n-slate-12 font-medium">{{
                attr.attribute_display_name
              }}</span>
              <span class="text-xs text-n-slate-11">{{
                attr.attribute_description || attr.attribute_key
              }}</span>
            </div>
          </label>
        </div>
      </div>

      <div class="flex justify-end gap-2 mt-4">
        <button
          class="px-4 py-2 text-sm font-medium bg-n-button-color text-n-slate-12 rounded-md hover:bg-n-alpha-2 transition-colors disabled:opacity-50 min-w-[100px]"
          @click="onClose"
        >
          {{ $t('PIPELINE_STAGES_MGMT.FORM.CANCEL') }}
        </button>
        <button
          :disabled="!canSubmit || isSubmitting"
          class="px-4 py-2 text-sm font-medium bg-n-brand text-white rounded-md hover:brightness-110 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center min-w-[100px]"
          @click="submit"
        >
          <span
            v-if="isSubmitting"
            class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"
          />
          <span v-else>{{ $t('PIPELINE_STAGES_MGMT.FORM.SUBMIT_EDIT') }}</span>
        </button>
      </div>
    </div>
  </woot-modal>
</template>
