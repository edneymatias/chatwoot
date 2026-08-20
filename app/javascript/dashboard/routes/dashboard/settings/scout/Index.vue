<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const scouts = ref([]);
const selectedScoutId = ref(null);
const providerSettings = ref(null);
const isLoading = ref(true);
const isSaving = ref(false);
const saveSuccess = ref(false);

const providerOptions = [
  { value: 'gemini', label: 'Google Gemini' },
  { value: 'openai', label: 'OpenAI' },
  { value: 'anthropic', label: 'Anthropic Claude' },
];

const scoutOptions = computed(() =>
  scouts.value.map(item => ({
    value: item.id,
    label: `${item.name} (${item.provider} / ${item.model_name})`,
  }))
);

const provider = ref('gemini');
const modelName = ref('gemini-2.5-flash');
const apiKeyOverride = ref('');

const fetchProviderSettings = async scoutId => {
  try {
    const { data } = await ScoutAPI.getProviderSettings(scoutId);
    providerSettings.value = data;
    provider.value = data.provider || 'gemini';
    modelName.value = data.model_name || 'gemini-2.5-flash';
    apiKeyOverride.value = '';
  } catch (error) {
    // Handled
  }
};

const fetchScouts = async () => {
  isLoading.value = true;
  try {
    const { data } = await ScoutAPI.get();
    scouts.value = Array.isArray(data) ? data : [];
    if (scouts.value.length > 0) {
      selectedScoutId.value = scouts.value[0].id;
      await fetchProviderSettings(scouts.value[0].id);
    }
  } catch (error) {
    scouts.value = [];
  } finally {
    isLoading.value = false;
  }
};

const handleSelectScout = async id => {
  selectedScoutId.value = id;
  await fetchProviderSettings(id);
};

const handleSave = async () => {
  if (!selectedScoutId.value) return;

  isSaving.value = true;
  saveSuccess.value = false;
  try {
    const payload = {
      provider: provider.value,
      model_name: modelName.value.trim(),
    };

    if (apiKeyOverride.value.trim()) {
      payload.api_key_override = apiKeyOverride.value.trim();
    }

    const { data } = await ScoutAPI.updateProviderSettings(
      selectedScoutId.value,
      payload
    );
    providerSettings.value = data;
    apiKeyOverride.value = '';
    saveSuccess.value = true;
    setTimeout(() => {
      saveSuccess.value = false;
    }, 3000);
  } catch (error) {
    // Handled
  } finally {
    isSaving.value = false;
  }
};

onMounted(() => {
  fetchScouts();
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :no-records-found="!isLoading && scouts.length === 0"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('SCOUT.PROVIDER_SETTINGS.TITLE')"
        :description="t('SCOUT.PROVIDER_SETTINGS.SUBTITLE')"
        feature-name="scout_providers"
      />
    </template>

    <template #body>
      <div
        v-if="scouts.length === 0"
        class="py-12 flex flex-col items-center justify-center text-center text-n-slate-11 border border-dashed border-n-weak rounded-xl"
      >
        <span class="i-lucide-bot size-8 text-n-slate-10 mb-2" />
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('SCOUT.EMPTY_STATE.TITLE') }}
        </p>
        <p class="text-xs text-n-slate-10 mt-1 max-w-sm">
          {{ t('SCOUT.EMPTY_STATE.DESCRIPTION') }}
        </p>
      </div>

      <div
        v-else
        class="p-6 rounded-xl border border-n-weak bg-n-solid-2 shadow-sm space-y-6"
      >
        <div class="space-y-4">
          <!-- Select Scout -->
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ t('SCOUT.PROVIDER_SETTINGS.SELECT_SCOUT_LABEL') }}
            </label>
            <Select
              :model-value="selectedScoutId"
              class="!w-full max-w-md [&>select]:w-full"
              :options="scoutOptions"
              @update:model-value="handleSelectScout"
            />
          </div>

          <!-- Provider Selection -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2">
            <div>
              <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
                {{ t('SCOUT.PROVIDER_LABEL') }}
              </label>
              <Select
                v-model="provider"
                class="!w-full [&>select]:w-full"
                :options="providerOptions"
              />
            </div>

            <div>
              <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
                {{ t('SCOUT.MODEL_NAME_LABEL') }}
              </label>
              <Input v-model="modelName" placeholder="gemini-2.5-flash" />
            </div>
          </div>

          <!-- API Key Override -->
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ t('SCOUT.API_KEY_OVERRIDE_LABEL') }}
            </label>
            <Input
              v-model="apiKeyOverride"
              type="password"
              :placeholder="
                providerSettings?.has_api_key_override
                  ? t('SCOUT.PROVIDER_SETTINGS.API_KEY_CONFIGURED_HINT')
                  : t('SCOUT.API_KEY_OVERRIDE_PLACEHOLDER')
              "
            />
            <span class="text-[11px] text-n-slate-10 mt-1 block">
              {{ t('SCOUT.PROVIDER_SETTINGS.API_KEY_SECURITY_NOTE') }}
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
            @click="handleSave"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
