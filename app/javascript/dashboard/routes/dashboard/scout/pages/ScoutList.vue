<script setup>
import { ref, computed, onMounted, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import SettingsLayout from '../../settings/SettingsLayout.vue';
import BaseSettingsHeader from '../../settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const store = useStore();

const scouts = ref([]);
const accountConfig = ref(null);
const isLoading = ref(true);
const isSubmitting = ref(false);
const createDialogRef = ref(null);

const accountId = computed(() => route.params.accountId);
const currentUser = computed(() => store.getters.getCurrentUser);
const isAdmin = computed(() => currentUser.value?.role === 'administrator');
const isConfigured = computed(() => accountConfig.value?.configured === true);

// Form state
const newName = ref('');
const newPersona = ref('');
const newQuota = ref(-1);

const fetchData = async () => {
  isLoading.value = true;
  try {
    const [scoutsRes, configRes] = await Promise.allSettled([
      ScoutAPI.get(),
      ScoutAPI.getAccountConfig(),
    ]);

    if (scoutsRes.status === 'fulfilled') {
      scouts.value = Array.isArray(scoutsRes.value.data)
        ? scoutsRes.value.data
        : [];
    } else {
      scouts.value = [];
    }

    if (configRes.status === 'fulfilled') {
      accountConfig.value = configRes.value.data;
    } else {
      accountConfig.value = null;
    }
  } finally {
    isLoading.value = false;
  }
};

const handleOpenCreate = () => {
  if (!isConfigured.value) {
    router.push({
      name: 'scout_settings',
      params: { accountId: accountId.value },
    });
    return;
  }

  newName.value = '';
  newPersona.value = '';
  newQuota.value = -1;
  nextTick(() => {
    createDialogRef.value?.open();
  });
};

const handleCreateScout = async () => {
  if (!newName.value.trim()) return;

  isSubmitting.value = true;
  try {
    const payload = {
      name: newName.value.trim(),
      persona: newPersona.value.trim(),
      responses_quota: parseInt(newQuota.value, 10),
    };

    const { data } = await ScoutAPI.create(payload);
    createDialogRef.value?.close();
    router.push({
      name: 'scout_detail',
      params: { accountId: accountId.value, scoutId: data.id },
    });
  } catch (error) {
    // Handled
  } finally {
    isSubmitting.value = false;
  }
};

const handleDeleteScout = async scoutId => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('SCOUT.CONFIRM_DELETE_MESSAGE'))) return;

  try {
    await ScoutAPI.delete(scoutId);
    await fetchData();
  } catch (error) {
    // Handled
  }
};

const handleToggleActive = async scout => {
  try {
    await ScoutAPI.update(scout.id, { enabled: !scout.enabled });
    scout.enabled = !scout.enabled;
  } catch (error) {
    // Handled
  }
};

const openScoutDetail = scoutId => {
  router.push({
    name: 'scout_detail',
    params: { accountId: accountId.value, scoutId },
  });
};

const openPlayground = scoutId => {
  router.push({
    name: 'scout_playground',
    params: { accountId: accountId.value, scoutId },
  });
};

const navigateToSettings = () => {
  router.push({
    name: 'scout_settings',
    params: { accountId: accountId.value },
  });
};

onMounted(() => {
  fetchData();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full m-0 pb-8 pt-4 px-6 overflow-auto bg-n-surface-1"
  >
    <div class="flex items-start w-full max-w-5xl mx-auto">
      <SettingsLayout
        :is-loading="isLoading"
        :no-records-found="!scouts.length && !isLoading"
      >
        <template #header>
          <BaseSettingsHeader
            :title="t('SCOUT.HEADER')"
            :description="t('SCOUT.SUBHEADER')"
            feature-name="scouts"
          >
            <template #actions>
              <div class="flex items-center gap-2">
                <Button
                  v-if="isConfigured"
                  :label="t('SCOUT.CREATE_BUTTON')"
                  color="blue"
                  size="sm"
                  @click="handleOpenCreate"
                />
              </div>
            </template>
          </BaseSettingsHeader>
        </template>
        <template #body>
          <!-- Loading -->
          <div
            v-if="isLoading"
            class="flex items-center justify-center py-20 text-n-slate-11"
          >
            <Spinner />
          </div>

          <!-- Gating Empty State if Account Unconfigured -->
          <EmptyStateLayout
            v-else-if="!isConfigured"
            :title="t('SCOUT.UNCONFIGURED_GATING.TITLE')"
            :subtitle="t('SCOUT.UNCONFIGURED_GATING.DESCRIPTION')"
            :show-backdrop="false"
          >
            <template #actions>
              <Button
                v-if="isAdmin"
                :label="t('SCOUT.UNCONFIGURED_GATING.BUTTON')"
                color="blue"
                size="sm"
                @click="navigateToSettings"
              />
            </template>
          </EmptyStateLayout>

          <!-- Empty State when configured but no scouts -->
          <EmptyStateLayout
            v-else-if="scouts.length === 0"
            :title="t('SCOUT.EMPTY_STATE.TITLE')"
            :subtitle="t('SCOUT.EMPTY_STATE.DESCRIPTION')"
            :show-backdrop="false"
          >
            <template #actions>
              <Button
                :label="t('SCOUT.EMPTY_STATE.BUTTON')"
                color="blue"
                size="sm"
                @click="handleOpenCreate"
              />
            </template>
          </EmptyStateLayout>

          <!-- Scouts List -->
          <div v-else class="divide-y divide-n-weak border-t border-n-weak">
            <div
              v-for="item in scouts"
              :key="item.id"
              class="flex items-center justify-between gap-4 py-4"
            >
              <!-- Left side: Avatar and Text -->
              <div class="flex items-center gap-4">
                <div
                  class="flex items-center justify-center size-10 rounded-xl ring ring-n-solid-1 border border-n-strong shadow-sm"
                  :class="
                    item.enabled
                      ? 'bg-n-brand/10 text-n-brand'
                      : 'bg-n-alpha-1 text-n-slate-10'
                  "
                >
                  <span class="i-lucide-bot size-5" />
                </div>

                <div class="flex flex-col items-start gap-1">
                  <div class="flex items-center gap-2">
                    <span
                      class="block text-heading-3 text-n-slate-12 capitalize"
                    >
                      {{ item.name }}
                    </span>
                  </div>

                  <span class="text-body-main text-n-slate-11 line-clamp-1">
                    {{
                      item.persona ||
                      t('SCOUT.INBOXES_COUNT', {
                        count: item.inboxes ? item.inboxes.length : 0,
                      })
                    }}
                  </span>
                </div>
              </div>

              <!-- Right side: Actions -->
              <div class="flex items-center gap-3 justify-end">
                <div class="flex items-center gap-2 mr-2">
                  <span class="text-xs text-n-slate-11 mr-1">{{
                    item.enabled
                      ? t('SCOUT.STATUS_ACTIVE')
                      : t('SCOUT.STATUS_INACTIVE')
                  }}</span>
                  <Switch
                    :model-value="item.enabled"
                    @change="handleToggleActive(item)"
                  />
                </div>

                <Button
                  v-tooltip.top="t('SCOUT.PLAYGROUND_BUTTON')"
                  icon="i-lucide-play"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="openPlayground(item.id)"
                />
                <Button
                  v-tooltip.top="t('SCOUT.CONFIGURE_BUTTON')"
                  icon="i-lucide-settings"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="openScoutDetail(item.id)"
                />
                <Button
                  v-if="isAdmin"
                  v-tooltip.top="t('SCOUT.DELETE_BUTTON')"
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                  @click.stop="handleDeleteScout(item.id)"
                />
              </div>
            </div>
          </div>
        </template>
        <!-- Create Scout Dialog -->
        <Dialog
          ref="createDialogRef"
          :title="t('SCOUT.CREATE_MODAL.TITLE')"
          :description="t('SCOUT.CREATE_MODAL.DESCRIPTION')"
          :confirm-button-label="t('SCOUT.CREATE_MODAL.SUBMIT')"
          :cancel-button-label="t('SCOUT.CREATE_MODAL.CANCEL')"
          :disable-confirm-button="!newName.trim() || isSubmitting"
          :is-loading="isSubmitting"
          width="lg"
          @confirm="handleCreateScout"
        >
          <form
            class="flex flex-col gap-4 py-2"
            @submit.prevent="handleCreateScout"
          >
            <div>
              <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
                {{ `${t('SCOUT.GENERAL.NAME_LABEL')} *` }}
              </label>
              <Input
                v-model="newName"
                :placeholder="t('SCOUT.GENERAL.NAME_PLACEHOLDER')"
                autofocus
              />
            </div>

            <div>
              <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
                {{ t('SCOUT.GENERAL.PERSONA_LABEL') }}
              </label>
              <TextArea
                v-model="newPersona"
                :placeholder="t('SCOUT.GENERAL.PERSONA_PLACEHOLDER')"
                :max-length="2000"
                auto-height
              />
            </div>

            <div>
              <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
                {{ t('SCOUT.GENERAL.QUOTA_LABEL') }}
              </label>
              <Input v-model="newQuota" type="number" placeholder="-1" />
            </div>
          </form>
        </Dialog>
      </SettingsLayout>
    </div>
  </div>
</template>
