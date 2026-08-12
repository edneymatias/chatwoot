<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import campaignAttributionSettingsAPI from 'dashboard/api/campaignAttributionSettings';
import { setupFacebookSdk } from '../inbox/channels/whatsapp/utils';

const { t } = useI18n();

const isLoading = ref(true);
const isConnecting = ref(false);
const isUpdating = ref(false);

const setting = ref({
  enabled: false,
  connected: false,
  meta_app_id: '',
  meta_api_version: 'v22.0',
});

const fetchSetting = async () => {
  isLoading.value = true;
  try {
    const response = await campaignAttributionSettingsAPI.get();
    setting.value = response.data;
  } catch (error) {
    useAlert(t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(async () => {
  await fetchSetting();
  if (setting.value.meta_app_id) {
    setupFacebookSdk(setting.value.meta_app_id, setting.value.meta_api_version);
  }
});

const onConnectMeta = async () => {
  isConnecting.value = true;
  try {
    const response = await new Promise((resolve, reject) => {
      window.FB.login(
        res => {
          if (res.authResponse && res.authResponse.accessToken) {
            resolve(res.authResponse.accessToken);
          } else {
            reject(new Error('Login cancelled or failed'));
          }
        },
        {
          scope: 'ads_read',
        }
      );
    });

    await campaignAttributionSettingsAPI.connect(response);
    useAlert(t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.CONNECT_SUCCESS'));
    await fetchSetting();
  } catch (error) {
    useAlert(t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.CONNECT_ERROR'));
  } finally {
    isConnecting.value = false;
  }
};

const onToggleEnable = async value => {
  if (value && !setting.value.connected) {
    useAlert(t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.NEED_CONNECTION'));
    return;
  }

  isUpdating.value = true;
  try {
    await campaignAttributionSettingsAPI.update({ enabled: value });
    setting.value.enabled = value;
    useAlert(t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.UPDATE_SUCCESS'));
  } catch (error) {
    useAlert(t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.UPDATE_ERROR'));
  } finally {
    isUpdating.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col max-w-4xl p-4 gap-6">
    <div v-if="isLoading" class="text-sm text-n-slate-11">
      {{ $t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.LOADING') }}
    </div>
    <div v-else class="flex flex-col gap-6">
      <div
        class="flex items-center justify-between border-b border-n-weak pb-4"
      >
        <div class="flex flex-col gap-1">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{
              $t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.META_CONNECTION')
            }}
          </h3>
          <p class="text-xs text-n-slate-11">
            {{
              $t(
                'PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.META_CONNECTION_DESC'
              )
            }}
          </p>
        </div>
        <div class="flex items-center gap-3">
          <span
            v-if="setting.connected"
            class="text-sm text-n-green-11 flex items-center gap-1"
          >
            <span class="i-lucide-check-circle size-4" />
            {{ $t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.CONNECTED') }}
          </span>
          <Button
            v-else
            :is-loading="isConnecting"
            icon="i-lucide-link"
            size="sm"
            @click="onConnectMeta"
          >
            {{ $t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.CONNECT_BUTTON') }}
          </Button>
        </div>
      </div>

      <div class="flex items-center justify-between">
        <div class="flex flex-col gap-1">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{
              $t('PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.ENABLE_ATTRIBUTION')
            }}
          </h3>
          <p class="text-xs text-n-slate-11">
            {{
              $t(
                'PIPELINE_STAGES_MGMT.CAMPAIGN_ATTRIBUTION.ENABLE_ATTRIBUTION_DESC'
              )
            }}
          </p>
        </div>
        <Switch
          v-model="setting.enabled"
          :disabled="!setting.connected || isUpdating"
          @change="onToggleEnable"
        />
      </div>
    </div>
  </div>
</template>
