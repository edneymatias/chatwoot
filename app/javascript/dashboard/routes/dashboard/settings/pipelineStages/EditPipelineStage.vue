<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  show: { type: Boolean, default: false },
  stage: { type: Object, required: true },
});

const emit = defineEmits(['close']);
const store = useStore();

const name = ref('');
const description = ref('');
const isSubmitting = ref(false);

const canSubmit = computed(() => name.value.trim().length > 0);

onMounted(() => {
  name.value = props.stage.name || '';
  description.value = props.stage.description || '';
});

const onClose = () => emit('close');

const submit = async () => {
  if (!canSubmit.value) return;
  isSubmitting.value = true;
  try {
    await store.dispatch('pipelineStages/update', {
      id: props.stage.id,
      name: name.value.trim(),
      description: description.value.trim(),
    });
    onClose();
  } catch (error) {
    // Handled by API error interceptor
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
        <textarea
          v-model="description"
          rows="3"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
        />
      </div>

      <div class="flex justify-end gap-2 mt-4">
        <button
          class="px-4 py-2 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 transition-colors"
          @click="onClose"
        >
          {{ $t('PIPELINE_STAGES_MGMT.FORM.CANCEL') }}
        </button>
        <button
          :disabled="!canSubmit || isSubmitting"
          class="px-4 py-2 text-sm font-medium bg-n-brand-9 text-white rounded-md hover:bg-n-brand-10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center min-w-[100px]"
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
