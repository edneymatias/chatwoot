<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import SettingsLayout from '../../settings/SettingsLayout.vue';
import BaseSettingsHeader from '../../settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const { t } = useI18n();

const config = ref(null);
const isLoading = ref(true);
const isSaving = ref(false);
const saveSuccess = ref(false);
const errorMessage = ref('');

const providerOptions = [
  { value: 'gemini', label: 'Google Gemini' },
  { value: 'openai', label: 'OpenAI' },
  { value: 'anthropic', label: 'Anthropic Claude' },
];

const provider = ref('gemini');
const modelName = ref('gemini-2.5-flash');
const apiKey = ref('');

const fetchConfig = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await ScoutAPI.getAccountConfig();
    config.value = data;
    if (data.configured) {
      provider.value = data.provider || 'gemini';
      modelName.value = data.model_name || 'gemini-2.5-flash';
    }
    apiKey.value = '';
  } catch (error) {
    config.value = null;
  } finally {
    isLoading.value = false;
  }
};

const handleSave = async () => {
  if (!modelName.value.trim()) return;

  isSaving.value = true;
  saveSuccess.value = false;
  errorMessage.value = '';

  try {
    const payload = {
      provider: provider.value,
      model_name: modelName.value.trim(),
    };

    if (apiKey.value.trim()) {
      payload.api_key = apiKey.value.trim();
    }

    const { data } = await ScoutAPI.updateAccountConfig(payload);
    config.value = data;
    apiKey.value = '';
    saveSuccess.value = true;
    setTimeout(() => {
      saveSuccess.value = false;
    }, 4000);
  } catch (error) {
    errorMessage.value =
      error.response?.data?.error || t('SCOUT.ACCOUNT_SETTINGS.SAVE_ERROR');
  } finally {
    isSaving.value = false;
  }
};

onMounted(() => {
  fetchConfig();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full m-0 pb-8 pt-4 px-6 overflow-auto bg-n-surface-1"
  >
    <div class="flex items-start w-full max-w-5xl mx-auto">
      <SettingsLayout :is-loading="isLoading">
        <template #header>
          <BaseSettingsHeader
            :title="t('SCOUT.ACCOUNT_SETTINGS.TITLE')"
            :description="t('SCOUT.ACCOUNT_SETTINGS.SUBTITLE')"
            feature-name="scout_settings"
          />
        </template>

        <template #body>
          <div
            class="p-6 rounded-xl border border-n-weak bg-n-solid-2 shadow-sm space-y-6"
          >
            <!-- Error Banner -->
            <div
              v-if="errorMessage"
              class="p-4 rounded-lg bg-red-500/10 border border-red-500/20 text-red-600 dark:text-red-400 text-xs flex items-center gap-2"
            >
              <span class="i-lucide-alert-triangle size-4 flex-shrink-0" />
              <span>{{ errorMessage }}</span>
            </div>

            <div class="space-y-4">
              <!-- Provider Selection & Model Name -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label
                    class="block text-xs font-medium text-n-slate-11 mb-1.5"
                  >
                    {{ t('SCOUT.PROVIDER_LABEL') }}
                  </label>
                  <Select
                    v-model="provider"
                    class="!w-full [&>select]:w-full"
                    :options="providerOptions"
                  />
                </div>

                <div>
                  <label
                    class="block text-xs font-medium text-n-slate-11 mb-1.5"
                  >
                    {{ t('SCOUT.MODEL_NAME_LABEL') }}
                  </label>
                  <Input v-model="modelName" placeholder="gemini-2.5-flash" />
                </div>
              </div>

              <!-- API Key -->
              <div>
                <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
                  {{ t('SCOUT.ACCOUNT_SETTINGS.API_KEY_LABEL') }}
                </label>
                <Input
                  v-model="apiKey"
                  type="password"
                  :placeholder="
                    config?.has_api_key
                      ? t('SCOUT.ACCOUNT_SETTINGS.API_KEY_CONFIGURED_HINT')
                      : t('SCOUT.ACCOUNT_SETTINGS.API_KEY_PLACEHOLDER')
                  "
                />
                <span class="text-[11px] text-n-slate-10 mt-1 block">
                  {{ t('SCOUT.ACCOUNT_SETTINGS.API_KEY_SECURITY_NOTE') }}
                </span>
              </div>
            </div>

            <div
              class="flex items-center justify-between pt-4 border-t border-n-weak"
            >
              <span
                v-if="saveSuccess"
                class="text-xs font-medium text-emerald-600 dark:text-emerald-400 flex items-center gap-1.5"
              >
                <span class="i-lucide-check size-4" />
                {{ t('SCOUT.GENERAL.SAVED_SUCCESS') }}
              </span>
              <span v-else />

              <Button
                :label="t('SCOUT.GENERAL.SAVE_BUTTON')"
                color="blue"
                size="sm"
                :is-loading="isSaving"
                :disabled="!modelName.trim() || isSaving"
                @click="handleSave"
              />
            </div>
          </div>
        </template>
      </SettingsLayout>
    </div>
  </div>
</template>
