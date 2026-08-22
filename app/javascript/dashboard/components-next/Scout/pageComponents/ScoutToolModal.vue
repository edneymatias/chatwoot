<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

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
const endpointUrl = ref('');
const httpMethod = ref('POST');
const headersJson = ref('{}');
const schemaJson = ref('{}');
const responseTemplate = ref('');

const isSubmitting = ref(false);
const jsonError = ref('');

// Test Playground State
const testPayloadJson = ref('{}');
const isTesting = ref(false);
const testResult = ref(null);
const testError = ref('');

const rawPreview = computed(() => {
  return testResult.value?.raw_body || '—';
});

const formattedPreview = computed(() => {
  if (!testResult.value) return '—';
  const fr = testResult.value.formatted_response;
  if (typeof fr === 'object' && fr !== null) {
    return JSON.stringify(fr, null, 2);
  }
  return fr || '—';
});

const isEditing = computed(() => !!props.tool);
const methodOptions = [
  { value: 'POST', label: 'POST' },
  { value: 'GET', label: 'GET' },
  { value: 'PUT', label: 'PUT' },
  { value: 'PATCH', label: 'PATCH' },
  { value: 'DELETE', label: 'DELETE' },
];

watch(
  () => props.tool,
  newVal => {
    if (newVal) {
      name.value = newVal.name || '';
      description.value = newVal.description || '';
      endpointUrl.value = newVal.endpoint_url || newVal.url || '';
      httpMethod.value = newVal.http_method || 'POST';

      if (
        typeof newVal.auth_headers === 'object' &&
        newVal.auth_headers !== null
      ) {
        headersJson.value = JSON.stringify(newVal.auth_headers, null, 2);
      } else if (newVal.auth_headers) {
        headersJson.value = newVal.auth_headers;
      } else if (newVal.headers) {
        headersJson.value = JSON.stringify(newVal.headers, null, 2);
      } else {
        headersJson.value = '{}';
      }

      schemaJson.value = JSON.stringify(
        newVal.parameter_schema ||
          newVal.parameters_schema || { type: 'object', properties: {} },
        null,
        2
      );
      responseTemplate.value = newVal.response_template || '';
    } else {
      name.value = '';
      description.value = '';
      endpointUrl.value = '';
      httpMethod.value = 'POST';
      headersJson.value = '{}';
      schemaJson.value = '{\n  "type": "object",\n  "properties": {}\n}';
      responseTemplate.value = '';
    }
    jsonError.value = '';
    testResult.value = null;
    testError.value = '';
    testPayloadJson.value = '{}';
  },
  { immediate: true }
);

const openModal = () => {
  jsonError.value = '';
  testResult.value = null;
  testError.value = '';
  dialogRef.value?.open();
};

const handleSave = async () => {
  jsonError.value = '';
  if (!name.value.trim() || !endpointUrl.value.trim()) return;

  let parsedHeaders = {};
  let parsedSchema = {};

  try {
    parsedHeaders = headersJson.value.trim().startsWith('{')
      ? JSON.parse(headersJson.value || '{}')
      : headersJson.value.trim();
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
      name: name.value.trim(),
      description: description.value.trim(),
      endpoint_url: endpointUrl.value.trim(),
      http_method: httpMethod.value,
      auth_headers: parsedHeaders,
      parameter_schema: parsedSchema,
      response_template: responseTemplate.value.trim() || null,
    };

    if (isEditing.value) {
      await ScoutAPI.updateTool(props.tool.id, payload);
    } else {
      await ScoutAPI.createTool(payload);
    }

    dialogRef.value?.close();
    emit('saved');
  } catch (error) {
    jsonError.value =
      error.response?.data?.error ||
      error.message ||
      t('SCOUT.ERROR_GENERIC_MESSAGE');
  } finally {
    isSubmitting.value = false;
  }
};

const handleTest = async () => {
  testError.value = '';
  testResult.value = null;

  if (!endpointUrl.value.trim()) return;

  let parsedHeaders = {};
  let parsedTestPayload = {};

  try {
    parsedHeaders = headersJson.value.trim().startsWith('{')
      ? JSON.parse(headersJson.value || '{}')
      : headersJson.value.trim();
  } catch (e) {
    testError.value = t('SCOUT.TOOLS.MODAL.INVALID_HEADERS_JSON');
    return;
  }

  try {
    parsedTestPayload = testPayloadJson.value.trim().length
      ? JSON.parse(testPayloadJson.value)
      : {};
  } catch (e) {
    testError.value = t('SCOUT.TOOLS.MODAL.INVALID_PAYLOAD_JSON');
    return;
  }

  isTesting.value = true;
  try {
    const testPayload = {
      endpoint_url: endpointUrl.value.trim(),
      http_method: httpMethod.value,
      auth_headers: parsedHeaders,
      response_template: responseTemplate.value.trim() || null,
      payload: parsedTestPayload,
    };

    const { data } = await ScoutAPI.testTool(testPayload);
    testResult.value = data;
  } catch (err) {
    testError.value =
      err.response?.data?.error ||
      err.message ||
      t('SCOUT.ERROR_GENERIC_MESSAGE');
  } finally {
    isTesting.value = false;
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
    :disable-confirm-button="
      !name.trim() || !endpointUrl.trim() || isSubmitting
    "
    :is-loading="isSubmitting"
    width="2xl"
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
          v-model="endpointUrl"
          placeholder="https://api.empresa.com/orders/{{order_id}}/status"
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
          rows="2"
          class="w-full p-3 font-mono text-xs rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
      </div>

      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ `${t('SCOUT.TOOLS.MODAL.SCHEMA_LABEL')} (JSON Schema)` }}
        </label>
        <textarea
          v-model="schemaJson"
          rows="3"
          class="w-full p-3 font-mono text-xs rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
      </div>

      <div>
        <div class="flex items-center justify-between mb-1.5">
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('SCOUT.TOOLS.MODAL.RESPONSE_TEMPLATE_LABEL') }}
          </label>
        </div>
        <textarea
          v-model="responseTemplate"
          rows="2"
          :placeholder="t('SCOUT.TOOLS.MODAL.RESPONSE_TEMPLATE_PLACEHOLDER')"
          class="w-full p-3 font-mono text-xs rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
        <p class="text-[11px] text-n-slate-10 mt-1">
          {{ t('SCOUT.TOOLS.MODAL.RESPONSE_TEMPLATE_HINT') }}
        </p>
      </div>

      <!-- Test Playground Section -->
      <div
        class="mt-2 p-4 rounded-xl border border-n-weak bg-n-alpha-1 flex flex-col gap-3"
      >
        <div class="flex items-center justify-between">
          <div>
            <h4 class="text-xs font-semibold text-n-slate-12">
              {{ t('SCOUT.TOOLS.MODAL.TEST_SECTION_TITLE') }}
            </h4>
            <p class="text-[11px] text-n-slate-11">
              {{ t('SCOUT.TOOLS.MODAL.TEST_SECTION_DESC') }}
            </p>
          </div>
          <Button
            :label="
              isTesting
                ? t('SCOUT.TOOLS.MODAL.TESTING')
                : t('SCOUT.TOOLS.MODAL.TEST_BUTTON')
            "
            variant="faded"
            color="slate"
            size="sm"
            icon="i-lucide-play"
            :is-loading="isTesting"
            :disabled="!endpointUrl.trim() || isTesting"
            @click="handleTest"
          />
        </div>

        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1">
            {{ t('SCOUT.TOOLS.MODAL.TEST_PAYLOAD_LABEL') }}
          </label>
          <textarea
            v-model="testPayloadJson"
            rows="2"
            class="w-full p-2.5 font-mono text-xs rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
          />
        </div>

        <!-- Test Error Banner -->
        <div
          v-if="testError"
          class="p-3 rounded-lg border border-n-ruby-5 bg-n-ruby-2 text-xs text-n-ruby-11 font-medium"
        >
          {{ testError }}
        </div>

        <!-- Test Results Display -->
        <div
          v-if="testResult"
          class="flex flex-col gap-2.5 pt-2 border-t border-n-weak"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('SCOUT.TOOLS.MODAL.TEST_RESULT_TITLE') }}
            </span>
            <div class="flex items-center gap-2">
              <span
                v-if="
                  testResult.status !== null && testResult.status !== undefined
                "
                class="px-2 py-0.5 text-xs font-mono font-semibold rounded"
                :class="
                  testResult.success
                    ? 'bg-n-teal-3 text-n-teal-11 border border-n-teal-5'
                    : 'bg-n-ruby-3 text-n-ruby-11 border border-n-ruby-5'
                "
              >
                {{
                  t('SCOUT.TOOLS.MODAL.STATUS_HTTP', {
                    status: testResult.status,
                  })
                }}
              </span>
              <span
                v-else
                class="px-2 py-0.5 text-xs font-mono font-semibold rounded bg-n-amber-3 text-n-amber-11 border border-n-amber-5"
              >
                {{ t('SCOUT.TOOLS.MODAL.STATUS_ERROR') }}
              </span>
            </div>
          </div>

          <div
            v-if="testResult.error"
            class="p-2.5 rounded-lg border border-n-ruby-5 bg-n-ruby-2 text-xs text-n-ruby-11 font-medium"
          >
            {{ testResult.error }}
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="flex flex-col gap-1">
              <div class="flex items-center justify-between">
                <span class="text-[11px] font-medium text-n-slate-10">
                  {{ t('SCOUT.TOOLS.MODAL.RAW_RESPONSE_LABEL') }}
                </span>
                <span class="text-[10px] text-n-slate-9">
                  {{ t('SCOUT.TOOLS.MODAL.TRUNCATED_HINT') }}
                </span>
              </div>
              <pre
                class="p-2.5 font-mono text-xs rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12 max-h-32 overflow-auto whitespace-pre-wrap break-all"
                >{{ rawPreview }}
              </pre>
            </div>

            <div class="flex flex-col gap-1">
              <span class="text-[11px] font-medium text-n-slate-10">
                {{ t('SCOUT.TOOLS.MODAL.SHAPED_RESPONSE_LABEL') }}
              </span>
              <pre
                class="p-2.5 font-mono text-xs rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12 max-h-32 overflow-auto whitespace-pre-wrap break-all"
                >{{ formattedPreview }}
              </pre>
            </div>
          </div>
        </div>
      </div>

      <p v-if="jsonError" class="text-xs text-n-ruby-9 font-medium">
        {{ jsonError }}
      </p>
    </form>
  </Dialog>
</template>
