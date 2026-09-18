<script setup>
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { computed, onMounted } from 'vue';
import IntegrationItem from '../IntegrationItem.vue';
import SettingsLayout from '../../SettingsLayout.vue';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';

const store = useStore();
const getters = useStoreGetters();

const uiFlags = getters['integrations/getUIFlags'];

const erpAppIntegrations = computed(() => {
  const apps = getters['integrations/getAppIntegrations'].value || [];
  return apps.filter(app => app.category === 'erp');
});

onMounted(() => {
  store.dispatch('integrations/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('INTEGRATION_SETTINGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('INTEGRATION_SETTINGS.ERP.HEADER')"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
        feature-name="erp_integration"
      />
    </template>
    <template #body>
      <div class="flex-grow flex-shrink overflow-auto">
        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          <IntegrationItem
            v-for="item in erpAppIntegrations"
            :id="item.id"
            :key="item.id"
            :name="item.name"
            :description="item.description"
            :enabled="item.enabled"
            :logo="item.logo"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
