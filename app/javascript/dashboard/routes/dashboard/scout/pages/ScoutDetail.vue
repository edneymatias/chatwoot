<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Button from 'dashboard/components-next/button/Button.vue';
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import SettingIntroBanner from 'dashboard/components/widgets/SettingIntroBanner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ScoutGeneralSettings from 'dashboard/components-next/Scout/pageComponents/ScoutGeneralSettings.vue';
import ScoutInboxesTab from 'dashboard/components-next/Scout/pageComponents/ScoutInboxesTab.vue';
import ScoutProductsTab from 'dashboard/components-next/Scout/pageComponents/ScoutProductsTab.vue';
import ScoutKnowledgeTab from 'dashboard/components-next/Scout/pageComponents/ScoutKnowledgeTab.vue';
import ScoutFunnelTab from 'dashboard/components-next/Scout/pageComponents/ScoutFunnelTab.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const scout = ref(null);
const isLoading = ref(true);

const scoutId = computed(() => route.params.scoutId);
const accountId = computed(() => route.params.accountId);

const tabIndexMap = {
  general: 0,
  inboxes: 1,
  products: 2,
  knowledge: 3,
  funnel: 4,
};

const currentTab = computed(() => {
  const name = route.name;
  if (name === 'scout_inboxes') return 'inboxes';
  if (name === 'scout_products') return 'products';
  if (name === 'scout_knowledge') return 'knowledge';
  if (name === 'scout_funnel') return 'funnel';
  return 'general';
});

const activeTabIndex = computed(() => tabIndexMap[currentTab.value] ?? 0);

const tabs = computed(() => [
  { key: 'general', label: t('SCOUT.TABS.GENERAL') },
  {
    key: 'inboxes',
    label: t('SCOUT.TABS.INBOXES'),
    count: scout.value?.inboxes?.length || 0,
  },
  { key: 'products', label: t('SCOUT.TABS.PRODUCTS') },
  { key: 'knowledge', label: t('SCOUT.TABS.KNOWLEDGE') },
  { key: 'funnel', label: t('SCOUT.TABS.FUNNEL') },
]);

const fetchScout = async () => {
  isLoading.value = true;
  try {
    const { data } = await ScoutAPI.show(scoutId.value);
    scout.value = data;
  } catch (error) {
    router.push({
      name: 'scouts_index',
      params: { accountId: accountId.value },
    });
  } finally {
    isLoading.value = false;
  }
};

const handleTabChanged = tab => {
  const routeMap = {
    general: 'scout_detail',
    inboxes: 'scout_inboxes',
    products: 'scout_products',
    knowledge: 'scout_knowledge',
    funnel: 'scout_funnel',
  };

  const targetRouteName = routeMap[tab.key] || 'scout_detail';
  router.push({
    name: targetRouteName,
    params: { accountId: accountId.value, scoutId: scoutId.value },
  });
};

const onTabChange = index => {
  const tab = tabs.value[index];
  if (tab) {
    handleTabChanged({ key: tab.key });
  }
};

const navigateToPlayground = () => {
  router.push({
    name: 'scout_playground',
    params: { accountId: accountId.value, scoutId: scoutId.value },
  });
};

const backUrl = computed(() => ({
  name: 'scouts_index',
  params: { accountId: accountId.value },
}));

onMounted(() => {
  fetchScout();
});
</script>

<template>
  <div v-if="isLoading" class="flex items-center justify-center h-full w-full">
    <Spinner />
  </div>
  <div
    v-else-if="scout"
    class="flex flex-col h-full w-full min-w-0 overflow-hidden"
  >
    <!-- Header like SettingsHeader.vue -->
    <div
      class="flex-none flex justify-between items-center h-20 min-h-[3.5rem] px-6 py-2 bg-n-surface-1"
    >
      <h1 class="flex items-center mb-0 text-2xl text-n-slate-12">
        <BackButton
          :back-url="backUrl"
          :button-label="t('SCOUT.TOOLS.BACK')"
          class="ltr:mr-4 rtl:ml-4"
        />
        <span class="text-xl font-medium text-n-slate-12">
          {{ t('SCOUT.HEADER') }}
        </span>
      </h1>
      <div class="flex items-center gap-3">
        <span
          class="inline-flex items-center px-2 py-0.5 rounded-full text-xs"
          :class="
            scout.enabled
              ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
              : 'bg-n-alpha-1 text-n-slate-10'
          "
        >
          {{
            scout.enabled
              ? t('SCOUT.STATUS_ACTIVE')
              : t('SCOUT.STATUS_INACTIVE')
          }}
        </span>
        <Button
          :label="t('SCOUT.PLAYGROUND_BUTTON')"
          color="blue"
          size="sm"
          @click="navigateToPlayground"
        />
      </div>
    </div>

    <!-- Intro Banner & Tabs -->
    <SettingIntroBanner :header-title="scout.name" class="flex-none">
      <woot-tabs
        class="[&_ul]:p-0 top-px relative"
        :index="activeTabIndex"
        :border="false"
        @change="onTabChange"
      >
        <woot-tabs-item
          v-for="(tab, index) in tabs"
          :key="tab.key"
          :index="index"
          :name="tab.label"
          :show-badge="false"
          is-compact
        />
      </woot-tabs>
    </SettingIntroBanner>

    <section class="flex-1 w-full overflow-auto py-8">
      <div class="max-w-7xl mx-auto w-full flex justify-center">
        <!-- Center the form wrapper inside max-w-7xl using max-w-4xl (like Inbox Settings.vue) -->
        <div class="w-full max-w-4xl mx-6">
          <!-- General Settings -->
          <ScoutGeneralSettings
            v-if="currentTab === 'general'"
            :scout="scout"
            @updated="fetchScout"
          />

          <!-- Inboxes Tab -->
          <ScoutInboxesTab
            v-else-if="currentTab === 'inboxes'"
            :scout="scout"
            @updated="fetchScout"
          />

          <!-- Products Tab -->
          <ScoutProductsTab
            v-else-if="currentTab === 'products'"
            :scout="scout"
            @updated="fetchScout"
          />

          <!-- Knowledge Tab -->
          <ScoutKnowledgeTab
            v-else-if="currentTab === 'knowledge'"
            :scout="scout"
            @updated="fetchScout"
          />

          <!-- Funnel Tab -->
          <ScoutFunnelTab
            v-else-if="currentTab === 'funnel'"
            :scout="scout"
            @updated="fetchScout"
          />
        </div>
      </div>
    </section>
  </div>
</template>
