<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  tool: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();

const IDENTIFIER_REGEX = /^[a-zA-Z_][a-zA-Z0-9_]*$/;

const dialogRef = ref(null);
const name = ref('');
const description = ref('');
const endpointUrl = ref('');
const httpMethod = ref('POST');
const authType = ref('none');
const responseTemplate = ref('');

// Auth credential states
const bearerToken = ref('');
const basicUsername = ref('');
const basicPassword = ref('');
const apiKeyHeaderName = ref('');
const apiKeyHeaderValue = ref('');

// Visual Parameter Builder State
const parameters = ref([]);

const isSubmitting = ref(false);
const formError = ref('');

// Test Playground State
const testPayloadJson = ref('');
const isTesting = ref(false);
const testResult = ref(null);
const testError = ref('');

const isEditing = computed(() => !!props.tool);

const methodOptions = [
  { value: 'POST', label: 'POST' },
  { value: 'GET', label: 'GET' },
  { value: 'PUT', label: 'PUT' },
  { value: 'PATCH', label: 'PATCH' },
  { value: 'DELETE', label: 'DELETE' },
];

const authTypeOptions = computed(() => [
  { value: 'none', label: t('SCOUT.TOOLS.MODAL.AUTH_TYPES.NONE') },
  { value: 'bearer', label: t('SCOUT.TOOLS.MODAL.AUTH_TYPES.BEARER') },
  { value: 'basic', label: t('SCOUT.TOOLS.MODAL.AUTH_TYPES.BASIC') },
  { value: 'api_key', label: t('SCOUT.TOOLS.MODAL.AUTH_TYPES.API_KEY') },
]);

const paramTypeOptions = computed(() => [
  { value: 'string', label: t('SCOUT.TOOLS.MODAL.PARAM_TYPES.STRING') },
  { value: 'number', label: t('SCOUT.TOOLS.MODAL.PARAM_TYPES.NUMBER') },
  { value: 'integer', label: t('SCOUT.TOOLS.MODAL.PARAM_TYPES.INTEGER') },
  { value: 'boolean', label: t('SCOUT.TOOLS.MODAL.PARAM_TYPES.BOOLEAN') },
  { value: 'array', label: t('SCOUT.TOOLS.MODAL.PARAM_TYPES.ARRAY') },
  { value: 'object', label: t('SCOUT.TOOLS.MODAL.PARAM_TYPES.OBJECT') },
]);

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

const generateSamplePayloadObject = () => {
  const sample = {};
  parameters.value.forEach(p => {
    const trimmedName = p.name.trim();
    if (!trimmedName) return;

    if (p.type === 'number' || p.type === 'integer') {
      sample[trimmedName] = 1;
    } else if (p.type === 'boolean') {
      sample[trimmedName] = true;
    } else if (p.type === 'array') {
      sample[trimmedName] = [];
    } else if (p.type === 'object') {
      sample[trimmedName] = {};
    } else {
      sample[trimmedName] = '';
    }
  });
  return sample;
};

const testPayloadPlaceholder = computed(() => {
  if (parameters.value.length > 0) {
    return JSON.stringify(generateSamplePayloadObject(), null, 2);
  }
  return '{\n  "key": "value"\n}';
});

const handleAddParameter = () => {
  parameters.value.push({
    id: `param_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
    name: '',
    type: 'string',
    description: '',
    required: false,
  });
};

const handleRemoveParameter = index => {
  parameters.value.splice(index, 1);
};

const handleMoveParameterUp = index => {
  if (index <= 0) return;
  const item = parameters.value.splice(index, 1)[0];
  parameters.value.splice(index - 1, 0, item);
};

const handleMoveParameterDown = index => {
  if (index >= parameters.value.length - 1) return;
  const item = parameters.value.splice(index, 1)[0];
  parameters.value.splice(index + 1, 0, item);
};

const decompileParameterSchema = schema => {
  if (!schema || typeof schema !== 'object') return [];
  const properties = schema.properties || {};
  const requiredList = Array.isArray(schema.required) ? schema.required : [];

  return Object.keys(properties).map(key => {
    const prop = properties[key] || {};
    return {
      id: `param_${key}_${Date.now()}`,
      name: key,
      type: prop.type || 'string',
      description: prop.description || '',
      required: requiredList.includes(key),
    };
  });
};

const detectAuthFromLegacy = (headers, storedAuthType) => {
  if (storedAuthType && storedAuthType !== 'none') return storedAuthType;
  if (!headers) return 'none';

  if (typeof headers === 'object') {
    if (headers.token || headers.Authorization?.startsWith('Bearer')) {
      return 'bearer';
    }
    if (headers.username || headers.password) {
      return 'basic';
    }
    if (headers.header_name && headers.header_value) {
      return 'api_key';
    }
  }
  if (typeof headers === 'string') {
    if (headers.startsWith('Bearer')) return 'bearer';
  }
  return 'none';
};

const compileAuthHeaders = () => {
  switch (authType.value) {
    case 'bearer':
      return { token: bearerToken.value.trim() };
    case 'basic':
      return {
        username: basicUsername.value.trim(),
        password: basicPassword.value.trim(),
      };
    case 'api_key':
      return {
        header_name: apiKeyHeaderName.value.trim(),
        header_value: apiKeyHeaderValue.value.trim(),
      };
    default:
      return {};
  }
};

const compileParameterSchema = () => {
  const properties = {};
  const required = [];

  parameters.value.forEach(p => {
    const trimmedName = p.name.trim();
    if (!trimmedName) return;

    properties[trimmedName] = {
      type: p.type || 'string',
      description: p.description?.trim() || undefined,
    };
    if (p.required) {
      required.push(trimmedName);
    }
  });

  return {
    type: 'object',
    properties,
    ...(required.length ? { required } : {}),
  };
};

const validateForm = () => {
  formError.value = '';

  if (!name.value.trim()) {
    formError.value = t('SCOUT.TOOLS.MODAL.ERRORS.TOOL_NAME_EMPTY');
    return false;
  }
  if (!endpointUrl.value.trim()) {
    formError.value = t('SCOUT.TOOLS.MODAL.ERRORS.ENDPOINT_URL_EMPTY');
    return false;
  }

  // Validate Authentication credentials
  if (authType.value === 'bearer' && !bearerToken.value.trim()) {
    formError.value = t('SCOUT.TOOLS.MODAL.ERRORS.AUTH_BEARER_EMPTY');
    return false;
  }
  if (
    authType.value === 'basic' &&
    (!basicUsername.value.trim() || !basicPassword.value.trim())
  ) {
    formError.value = t('SCOUT.TOOLS.MODAL.ERRORS.AUTH_BASIC_EMPTY');
    return false;
  }
  if (
    authType.value === 'api_key' &&
    (!apiKeyHeaderName.value.trim() || !apiKeyHeaderValue.value.trim())
  ) {
    formError.value = t('SCOUT.TOOLS.MODAL.ERRORS.AUTH_API_KEY_EMPTY');
    return false;
  }

  // Validate parameters
  const seenNames = new Set();
  for (let i = 0; i < parameters.value.length; i += 1) {
    const p = parameters.value[i];
    const trimmedName = p.name.trim();

    if (!trimmedName) {
      formError.value = t('SCOUT.TOOLS.MODAL.ERRORS.PARAM_NAME_EMPTY');
      return false;
    }

    if (!IDENTIFIER_REGEX.test(trimmedName)) {
      formError.value = t('SCOUT.TOOLS.MODAL.ERRORS.PARAM_NAME_INVALID', {
        name: trimmedName,
      });
      return false;
    }

    if (seenNames.has(trimmedName)) {
      formError.value = t('SCOUT.TOOLS.MODAL.ERRORS.PARAM_NAME_DUPLICATE', {
        name: trimmedName,
      });
      return false;
    }
    seenNames.add(trimmedName);
  }

  return true;
};

watch(
  () => props.tool,
  newVal => {
    if (newVal) {
      name.value = newVal.name || '';
      description.value = newVal.description || '';
      endpointUrl.value = newVal.endpoint_url || newVal.url || '';
      httpMethod.value = newVal.http_method || 'POST';
      responseTemplate.value = newVal.response_template || '';

      const detectedAuth = detectAuthFromLegacy(
        newVal.auth_headers,
        newVal.auth_type
      );
      authType.value = detectedAuth;

      const rawHeaders = newVal.auth_headers || {};
      bearerToken.value = rawHeaders.token || '••••••••';
      basicUsername.value = rawHeaders.username || '';
      basicPassword.value = rawHeaders.password || '••••••••';
      apiKeyHeaderName.value = rawHeaders.header_name || '';
      apiKeyHeaderValue.value = rawHeaders.header_value || '••••••••';

      const rawSchema =
        newVal.parameter_schema || newVal.parameters_schema || {};
      parameters.value = decompileParameterSchema(rawSchema);
      testPayloadJson.value = '';
    } else {
      name.value = '';
      description.value = '';
      endpointUrl.value = '';
      httpMethod.value = 'POST';
      authType.value = 'none';
      responseTemplate.value = '';
      bearerToken.value = '';
      basicUsername.value = '';
      basicPassword.value = '';
      apiKeyHeaderName.value = '';
      apiKeyHeaderValue.value = '';
      parameters.value = [];
      testPayloadJson.value = '';
    }
    formError.value = '';
    testResult.value = null;
    testError.value = '';
  },
  { immediate: true }
);

const openModal = () => {
  formError.value = '';
  testResult.value = null;
  testError.value = '';
  dialogRef.value?.open();
};

const handleSave = async () => {
  if (!validateForm()) return;

  isSubmitting.value = true;
  try {
    const payload = {
      name: name.value.trim(),
      description: description.value.trim(),
      endpoint_url: endpointUrl.value.trim(),
      http_method: httpMethod.value,
      auth_type: authType.value,
      auth_headers: compileAuthHeaders(),
      parameter_schema: compileParameterSchema(),
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
    formError.value =
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

  let parsedTestPayload = {};
  if (testPayloadJson.value.trim().length) {
    try {
      parsedTestPayload = JSON.parse(testPayloadJson.value);
    } catch {
      testError.value = t('SCOUT.TOOLS.MODAL.INVALID_PAYLOAD_JSON');
      return;
    }
  } else {
    parsedTestPayload = generateSamplePayloadObject();
  }

  isTesting.value = true;
  try {
    const testPayload = {
      endpoint_url: endpointUrl.value.trim(),
      http_method: httpMethod.value,
      auth_type: authType.value,
      auth_headers: compileAuthHeaders(),
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
    <div
      class="flex flex-col gap-4 py-2 max-h-[65vh] overflow-y-auto pr-2 -mr-1"
    >
      <!-- Tool Name & Method -->
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

      <!-- Endpoint URL -->
      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ `${t('SCOUT.TOOLS.MODAL.URL_LABEL')} *` }}
        </label>
        <Input
          v-model="endpointUrl"
          placeholder="https://api.example.com/orders/{{ order_id }}"
        />
      </div>

      <!-- Description for LLM -->
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

      <!-- Authentication Type Selection -->
      <div
        class="flex flex-col gap-3 p-3.5 rounded-xl border border-n-weak bg-n-alpha-1"
      >
        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.TOOLS.MODAL.AUTH_TYPE_LABEL') }}
          </label>
          <Select
            v-model="authType"
            class="!w-full [&>select]:w-full"
            :options="authTypeOptions"
          />
        </div>

        <!-- Bearer Token Input -->
        <div v-if="authType === 'bearer'">
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ `${t('SCOUT.TOOLS.MODAL.TOKEN_LABEL')} *` }}
          </label>
          <Input
            v-model="bearerToken"
            type="password"
            :placeholder="t('SCOUT.TOOLS.MODAL.TOKEN_PLACEHOLDER')"
          />
        </div>

        <!-- Basic Auth Inputs -->
        <div v-else-if="authType === 'basic'" class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ `${t('SCOUT.TOOLS.MODAL.USERNAME_LABEL')} *` }}
            </label>
            <Input
              v-model="basicUsername"
              :placeholder="t('SCOUT.TOOLS.MODAL.USERNAME_PLACEHOLDER')"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ `${t('SCOUT.TOOLS.MODAL.PASSWORD_LABEL')} *` }}
            </label>
            <Input
              v-model="basicPassword"
              type="password"
              :placeholder="t('SCOUT.TOOLS.MODAL.PASSWORD_PLACEHOLDER')"
            />
          </div>
        </div>

        <!-- API Key Inputs -->
        <div v-else-if="authType === 'api_key'" class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ `${t('SCOUT.TOOLS.MODAL.HEADER_NAME_LABEL')} *` }}
            </label>
            <Input
              v-model="apiKeyHeaderName"
              :placeholder="t('SCOUT.TOOLS.MODAL.HEADER_NAME_PLACEHOLDER')"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ `${t('SCOUT.TOOLS.MODAL.HEADER_VALUE_LABEL')} *` }}
            </label>
            <Input
              v-model="apiKeyHeaderValue"
              type="password"
              :placeholder="t('SCOUT.TOOLS.MODAL.HEADER_VALUE_PLACEHOLDER')"
            />
          </div>
        </div>
      </div>

      <!-- Parameters Section (Visual Parameter Builder) -->
      <div class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <div>
            <label class="block text-xs font-semibold text-n-slate-12">
              {{ t('SCOUT.TOOLS.MODAL.PARAMETERS_LABEL') }}
            </label>
            <p class="text-[11px] text-n-slate-11">
              {{ t('SCOUT.TOOLS.MODAL.PARAMETERS_DESC') }}
            </p>
          </div>
        </div>

        <!-- Parameter Cards List -->
        <div v-if="parameters.length > 0" class="flex flex-col gap-3">
          <div
            v-for="(param, index) in parameters"
            :key="param.id"
            class="flex flex-col gap-2.5 p-3 rounded-xl border border-n-weak bg-n-solid-2"
          >
            <!-- Parameter Name, Type, Reorder & Delete -->
            <div class="flex items-center gap-2">
              <div class="flex-1">
                <Input
                  v-model="param.name"
                  :placeholder="t('SCOUT.TOOLS.MODAL.PARAM_NAME_PLACEHOLDER')"
                />
              </div>

              <div class="w-36">
                <Select
                  v-model="param.type"
                  class="!w-full [&>select]:w-full"
                  :options="paramTypeOptions"
                />
              </div>

              <!-- Reorder Controls -->
              <div class="flex items-center gap-0.5">
                <Button
                  icon="i-lucide-chevron-up"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :disabled="index === 0"
                  :title="t('SCOUT.TOOLS.MODAL.PARAM_MOVE_UP')"
                  @click="handleMoveParameterUp(index)"
                />
                <Button
                  icon="i-lucide-chevron-down"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  :disabled="index === parameters.length - 1"
                  :title="t('SCOUT.TOOLS.MODAL.PARAM_MOVE_DOWN')"
                  @click="handleMoveParameterDown(index)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="xs"
                  :title="t('SCOUT.TOOLS.MODAL.PARAM_DELETE')"
                  @click="handleRemoveParameter(index)"
                />
              </div>
            </div>

            <!-- Parameter Description -->
            <div>
              <TextArea
                v-model="param.description"
                rows="2"
                :placeholder="t('SCOUT.TOOLS.MODAL.PARAM_DESC_PLACEHOLDER')"
                auto-height
              />
            </div>

            <!-- Required Checkbox -->
            <div class="flex items-center gap-2">
              <Checkbox v-model="param.required" />
              <span
                class="text-xs text-n-slate-12 cursor-pointer select-none"
                @click="param.required = !param.required"
              >
                {{ t('SCOUT.TOOLS.MODAL.PARAM_REQUIRED_LABEL') }}
              </span>
            </div>
          </div>
        </div>

        <!-- Add Parameter Action Button -->
        <div class="flex items-center justify-start">
          <Button
            :label="t('SCOUT.TOOLS.MODAL.ADD_PARAMETER')"
            variant="link"
            color="blue"
            size="sm"
            icon="i-lucide-plus"
            @click="handleAddParameter"
          />
        </div>
      </div>

      <!-- Response Template (Optional) -->
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
            rows="3"
            :placeholder="testPayloadPlaceholder"
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
                <span
                  v-if="testResult.truncated"
                  class="text-[10px] text-n-slate-9"
                >
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

      <!-- Form Error Message -->
      <p v-if="formError" class="text-xs text-n-ruby-9 font-medium">
        {{ formError }}
      </p>
    </div>
  </Dialog>
</template>
