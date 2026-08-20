<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  tool: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();

const dialogRef = ref(null);
const name = ref('');
const description = ref('');
const url = ref('');
const httpMethod = ref('POST');
const headersJson = ref('{}');
const schemaJson = ref('{}');
const isSubmitting = ref(false);
const jsonError = ref('');

const isEditing = computed(() => !!props.tool);
const methodOptions = [
  { value: 'POST', label: 'POST' },
  { value: 'GET', label: 'GET' },
  { value: 'PUT', label: 'PUT' },
  { value: 'PATCH', label: 'PATCH' },
];

watch(
  () => props.tool,
  newVal => {
    if (newVal) {
      name.value = newVal.name || '';
      description.value = newVal.description || '';
      url.value = newVal.url || '';
      httpMethod.value = newVal.http_method || 'POST';
      headersJson.value = JSON.stringify(newVal.headers || {}, null, 2);
      schemaJson.value = JSON.stringify(
        newVal.parameters_schema || {},
        null,
        2
      );
    } else {
      name.value = '';
      description.value = '';
      url.value = '';
      httpMethod.value = 'POST';
      headersJson.value = '{}';
      schemaJson.value = '{\n  "type": "object",\n  "properties": {}\n}';
    }
    jsonError.value = '';
  },
  { immediate: true }
);

const openModal = () => {
  jsonError.value = '';
  dialogRef.value?.open();
};

const handleSave = async () => {
  jsonError.value = '';
  if (!name.value.trim() || !url.value.trim()) return;

  let parsedHeaders = {};
  let parsedSchema = {};

  try {
    parsedHeaders = JSON.parse(headersJson.value || '{}');
  } catch (e) {
    jsonError.value = t('SCOUT.TOOLS.MODAL.INVALID_HEADERS_JSON');
    return;
  }

  try {
    parsedSchema = JSON.parse(schemaJson.value || '{}');
  } catch (e) {
    jsonError.value = t('SCOUT.TOOLS.MODAL.INVALID_SCHEMA_JSON');
    return;
  }

  isSubmitting.value = true;
  try {
    const payload = {
      scout_tool: {
        name: name.value.trim(),
        description: description.value.trim(),
        url: url.value.trim(),
        http_method: httpMethod.value,
        headers: parsedHeaders,
        parameters_schema: parsedSchema,
      },
    };

    if (isEditing.value) {
      await ScoutAPI.updateTool(props.tool.id, payload);
    } else {
      await ScoutAPI.createTool(payload);
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
    :title="
      isEditing
        ? t('SCOUT.TOOLS.MODAL.EDIT_TITLE')
        : t('SCOUT.TOOLS.MODAL.ADD_TITLE')
    "
    :description="t('SCOUT.TOOLS.MODAL.DESCRIPTION')"
    :confirm-button-label="t('SCOUT.TOOLS.MODAL.SUBMIT')"
    :cancel-button-label="t('SCOUT.TOOLS.MODAL.CANCEL')"
    :disable-confirm-button="!name.trim() || !url.trim() || isSubmitting"
    :is-loading="isSubmitting"
    width="xl"
    @confirm="handleSave"
  >
    <form class="flex flex-col gap-4 py-2" @submit.prevent="handleSave">
      <div class="grid grid-cols-3 gap-4">
        <div class="col-span-2">
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ `${t('SCOUT.TOOLS.MODAL.NAME_LABEL')} *` }}
          </label>
          <Input
            v-model="name"
            :placeholder="t('SCOUT.TOOLS.MODAL.NAME_PLACEHOLDER')"
            autofocus
          />
        </div>

        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.TOOLS.MODAL.METHOD_LABEL') }}
          </label>
          <Select
            v-model="httpMethod"
            class="!w-full [&>select]:w-full"
            :options="methodOptions"
          />
        </div>
      </div>

      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ `${t('SCOUT.TOOLS.MODAL.URL_LABEL')} *` }}
        </label>
        <Input
          v-model="url"
          placeholder="https://api.empresa.com/webhooks/check"
        />
      </div>

      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ t('SCOUT.TOOLS.MODAL.DESCRIPTION_LABEL') }}
        </label>
        <TextArea
          v-model="description"
          :placeholder="t('SCOUT.TOOLS.MODAL.DESCRIPTION_PLACEHOLDER')"
          auto-height
        />
      </div>

      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ `${t('SCOUT.TOOLS.MODAL.HEADERS_LABEL')} (JSON)` }}
        </label>
        <textarea
          v-model="headersJson"
          rows="3"
          class="w-full p-3 font-mono text-xs rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
      </div>

      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ `${t('SCOUT.TOOLS.MODAL.SCHEMA_LABEL')} (JSON Schema)` }}
        </label>
        <textarea
          v-model="schemaJson"
          rows="4"
          class="w-full p-3 font-mono text-xs rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
      </div>

      <p v-if="jsonError" class="text-xs text-n-ruby-9 font-medium">
        {{ jsonError }}
      </p>
    </form>
  </Dialog>
</template>
