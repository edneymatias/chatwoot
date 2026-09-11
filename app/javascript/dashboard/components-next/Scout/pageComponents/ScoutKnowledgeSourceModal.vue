<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  scoutId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();

const dialogRef = ref(null);
const activeKind = ref('url');
const url = ref('');
const question = ref('');
const answer = ref('');
const documentFile = ref(null);
const fileError = ref('');
const isSubmitting = ref(false);

const openModal = () => {
  activeKind.value = 'url';
  url.value = '';
  question.value = '';
  answer.value = '';
  documentFile.value = null;
  fileError.value = '';
  dialogRef.value?.open();
};

const handleFileChange = event => {
  fileError.value = '';
  const file = event.target.files?.[0];
  if (!file) return;

  if (file.type !== 'application/pdf') {
    fileError.value = t('SCOUT.KNOWLEDGE.MODAL.PDF_ONLY_ERROR');
    return;
  }

  if (file.size > 10 * 1024 * 1024) {
    fileError.value = t('SCOUT.KNOWLEDGE.MODAL.FILE_SIZE_ERROR');
    return;
  }

  documentFile.value = file;
};

const handleSave = async () => {
  isSubmitting.value = true;
  try {
    if (activeKind.value === 'url') {
      if (!url.value.trim()) return;
      await ScoutAPI.createKnowledgeSource(props.scoutId, {
        knowledge_source: {
          kind: 'url',
          url: url.value.trim(),
        },
      });
    } else if (activeKind.value === 'document') {
      if (!documentFile.value) return;
      const formData = new FormData();
      formData.append('knowledge_source[kind]', 'document');
      formData.append('knowledge_source[document_file]', documentFile.value);
      await ScoutAPI.createKnowledgeSource(props.scoutId, formData);
    } else if (activeKind.value === 'faq') {
      if (!question.value.trim() || !answer.value.trim()) return;
      await ScoutAPI.createKnowledgeSource(props.scoutId, {
        knowledge_source: {
          kind: 'faq',
          question: question.value.trim(),
          answer: answer.value.trim(),
        },
      });
    }

    dialogRef.value?.close();
    emit('saved');
  } catch (error) {
    // Handled
  } finally {
    isSubmitting.value = false;
  }
};

defineExpose({
  openModal,
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('SCOUT.KNOWLEDGE.MODAL.TITLE')"
    :description="t('SCOUT.KNOWLEDGE.MODAL.DESCRIPTION')"
    :confirm-button-label="t('SCOUT.KNOWLEDGE.MODAL.SUBMIT')"
    :cancel-button-label="t('SCOUT.KNOWLEDGE.MODAL.CANCEL')"
    :disable-confirm-button="isSubmitting"
    :is-loading="isSubmitting"
    width="lg"
    @confirm="handleSave"
  >
    <div class="flex flex-col gap-4 py-2">
      <!-- Kind Selector Buttons -->
      <div
        class="grid grid-cols-3 gap-2 p-1 rounded-xl bg-n-surface-1 border border-n-weak"
      >
        <button
          type="button"
          class="flex items-center justify-center gap-2 py-2 rounded-lg text-xs font-medium transition-all"
          :class="
            activeKind === 'url'
              ? 'bg-n-brand text-white shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeKind = 'url'"
        >
          <span class="i-lucide-globe size-3.5" />
          {{ t('SCOUT.KNOWLEDGE.MODAL.TYPE_URL') }}
        </button>

        <button
          type="button"
          class="flex items-center justify-center gap-2 py-2 rounded-lg text-xs font-medium transition-all"
          :class="
            activeKind === 'document'
              ? 'bg-n-brand text-white shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeKind = 'document'"
        >
          <span class="i-lucide-file-text size-3.5" />
          {{ t('SCOUT.KNOWLEDGE.MODAL.TYPE_DOCUMENT') }}
        </button>

        <button
          type="button"
          class="flex items-center justify-center gap-2 py-2 rounded-lg text-xs font-medium transition-all"
          :class="
            activeKind === 'faq'
              ? 'bg-n-brand text-white shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeKind = 'faq'"
        >
          <span class="i-lucide-help-circle size-3.5" />
          {{ t('SCOUT.KNOWLEDGE.MODAL.TYPE_FAQ') }}
        </button>
      </div>

      <!-- URL Form -->
      <div v-if="activeKind === 'url'" class="space-y-2">
        <label class="block text-xs font-medium text-n-slate-11">
          {{ `${t('SCOUT.KNOWLEDGE.MODAL.URL_LABEL')} *` }}
        </label>
        <Input
          v-model="url"
          placeholder="https://suaempresa.com/precos"
          autofocus
        />
        <span class="text-[11px] text-n-slate-10 block">
          {{ t('SCOUT.KNOWLEDGE.MODAL.URL_HINT') }}
        </span>
      </div>

      <!-- Document Form -->
      <div v-else-if="activeKind === 'document'" class="space-y-2">
        <label class="block text-xs font-medium text-n-slate-11">
          {{ `${t('SCOUT.KNOWLEDGE.MODAL.DOCUMENT_LABEL')} (PDF, max 10MB) *` }}
        </label>
        <div
          class="border-2 border-dashed border-n-weak rounded-xl p-6 text-center hover:border-n-brand/40 transition-colors"
        >
          <input
            id="scout-doc-upload"
            type="file"
            accept="application/pdf"
            class="hidden"
            @change="handleFileChange"
          />
          <label
            for="scout-doc-upload"
            class="cursor-pointer flex flex-col items-center justify-center"
          >
            <span class="i-lucide-upload-cloud size-8 text-n-slate-10 mb-2" />
            <span class="text-xs font-medium text-n-brand">
              {{
                documentFile
                  ? documentFile.name
                  : t('SCOUT.KNOWLEDGE.MODAL.CHOOSE_FILE')
              }}
            </span>
            <span class="text-[10px] text-n-slate-10 mt-1">
              {{ `${t('SCOUT.KNOWLEDGE.MODAL.TYPE_DOCUMENT')} (10MB)` }}
            </span>
          </label>
        </div>
        <p v-if="fileError" class="text-xs text-n-ruby-9 mt-1">
          {{ fileError }}
        </p>
      </div>

      <!-- FAQ Form -->
      <div v-else class="space-y-3">
        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ `${t('SCOUT.KNOWLEDGE.MODAL.QUESTION_LABEL')} *` }}
          </label>
          <Input
            v-model="question"
            :placeholder="t('SCOUT.KNOWLEDGE.MODAL.QUESTION_PLACEHOLDER')"
            autofocus
          />
        </div>
        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ `${t('SCOUT.KNOWLEDGE.MODAL.ANSWER_LABEL')} *` }}
          </label>
          <TextArea
            v-model="answer"
            :placeholder="t('SCOUT.KNOWLEDGE.MODAL.ANSWER_PLACEHOLDER')"
            :max-length="2000"
            auto-height
          />
        </div>
      </div>
    </div>
  </Dialog>
</template>
