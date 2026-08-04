<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const store = useStore();
const { t } = useI18n();

const isSubmitting = ref(false);

const selectedWonAttributeIds = ref([]);
const selectedLostAttributeIds = ref([]);

const opportunityAttributes = computed(() =>
  store.getters['attributes/getAttributesByModel']('opportunity_attribute')
);

const requiredForWon = computed(
  () => store.getters['pipelineClosingRequiredFields/requiredForWon']
);
const requiredForLost = computed(
  () => store.getters['pipelineClosingRequiredFields/requiredForLost']
);

onMounted(async () => {
  store.dispatch('attributes/get');
  await store.dispatch('pipelineClosingRequiredFields/fetch');

  selectedWonAttributeIds.value = requiredForWon.value.map(
    r => r.custom_attribute_definition_id
  );
  selectedLostAttributeIds.value = requiredForLost.value.map(
    r => r.custom_attribute_definition_id
  );
});

const submit = async () => {
  isSubmitting.value = true;
  try {
    const originalWonIds = requiredForWon.value.map(
      r => r.custom_attribute_definition_id
    );
    const originalLostIds = requiredForLost.value.map(
      r => r.custom_attribute_definition_id
    );

    const wonToAdd = selectedWonAttributeIds.value.filter(
      id => !originalWonIds.includes(id)
    );
    const wonToRemove = requiredForWon.value.filter(
      r =>
        !selectedWonAttributeIds.value.includes(
          r.custom_attribute_definition_id
        )
    );

    const lostToAdd = selectedLostAttributeIds.value.filter(
      id => !originalLostIds.includes(id)
    );
    const lostToRemove = requiredForLost.value.filter(
      r =>
        !selectedLostAttributeIds.value.includes(
          r.custom_attribute_definition_id
        )
    );

    const promises = [];

    wonToAdd.forEach(id => {
      promises.push(
        store.dispatch('pipelineClosingRequiredFields/create', {
          custom_attribute_definition_id: id,
          outcome: 'won',
        })
      );
    });
    wonToRemove.forEach(r => {
      promises.push(
        store.dispatch('pipelineClosingRequiredFields/destroy', r.id)
      );
    });

    lostToAdd.forEach(id => {
      promises.push(
        store.dispatch('pipelineClosingRequiredFields/create', {
          custom_attribute_definition_id: id,
          outcome: 'lost',
        })
      );
    });
    lostToRemove.forEach(r => {
      promises.push(
        store.dispatch('pipelineClosingRequiredFields/destroy', r.id)
      );
    });

    if (promises.length > 0) {
      await Promise.all(promises);
      await store.dispatch('pipelineClosingRequiredFields/fetch');
    }
    useAlert(
      t('OPPORTUNITIES.REQUIREMENTS_MODAL.SAVE_SUCCESS') || 'Saved successfully'
    );
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error ||
      error?.message ||
      'Error updating closing requirements';
    useAlert(errorMessage);
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div
    class="flex-1 flex flex-col max-h-[calc(100vh-240px)] overflow-y-auto pt-4 pb-8"
  >
    <div class="flex flex-col gap-8 max-w-4xl">
      <!-- Won Requirements -->
      <div class="flex flex-col gap-3">
        <label class="text-sm font-semibold text-n-slate-12">
          {{
            t('OPPORTUNITIES.REQUIREMENTS_MODAL.REQUIRED_FOR_WON') ||
            'Required for won'
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
          class="border border-n-weak rounded-xl bg-n-surface-1 overflow-visible"
        >
          <label
            v-for="(attr, index) in opportunityAttributes"
            :key="attr.id"
            class="flex items-center gap-3 cursor-pointer p-4"
            :class="{
              'border-b border-n-weak':
                index !== opportunityAttributes.length - 1,
            }"
          >
            <input
              v-model="selectedWonAttributeIds"
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

      <!-- Lost Requirements -->
      <div class="flex flex-col gap-3">
        <label class="text-sm font-semibold text-n-slate-12">
          {{
            t('OPPORTUNITIES.REQUIREMENTS_MODAL.REQUIRED_FOR_LOST') ||
            'Required for lost'
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
          class="border border-n-weak rounded-xl bg-n-surface-1 overflow-visible"
        >
          <label
            v-for="(attr, index) in opportunityAttributes"
            :key="attr.id"
            class="flex items-center gap-3 cursor-pointer p-4"
            :class="{
              'border-b border-n-weak':
                index !== opportunityAttributes.length - 1,
            }"
          >
            <input
              v-model="selectedLostAttributeIds"
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
            t('OPPORTUNITIES.REQUIREMENTS_MODAL.SAVE') || 'Save Changes'
          }}</span>
        </button>
      </div>
    </div>
  </div>
</template>
