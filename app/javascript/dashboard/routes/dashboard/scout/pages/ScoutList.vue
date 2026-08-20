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
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const store = useStore();

const scouts = ref([]);
const isLoading = ref(true);
const isSubmitting = ref(false);
const createDialogRef = ref(null);

const accountId = computed(() => route.params.accountId);
const currentUser = computed(() => store.getters.getCurrentUser);
const isAdmin = computed(() => currentUser.value?.role === 'administrator');

const providerOptions = [
  { value: 'gemini', label: 'Google Gemini' },
  { value: 'openai', label: 'OpenAI' },
  { value: 'anthropic', label: 'Anthropic Claude' },
];

// Form state
const newName = ref('');
const newPersona = ref('');
const newProvider = ref('gemini');
const newModelName = ref('gemini-2.5-flash');
const newApiKey = ref('');
const newQuota = ref(-1);

const fetchScouts = async () => {
  isLoading.value = true;
  try {
    const { data } = await ScoutAPI.get();
    scouts.value = Array.isArray(data) ? data : [];
  } catch (error) {
    scouts.value = [];
  } finally {
    isLoading.value = false;
  }
};

const handleOpenCreate = () => {
  newName.value = '';
  newPersona.value = '';
  newProvider.value = 'gemini';
  newModelName.value = 'gemini-2.5-flash';
  newApiKey.value = '';
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
      provider: newProvider.value,
      model_name: newModelName.value.trim(),
      responses_quota: parseInt(newQuota.value, 10),
    };

    if (newApiKey.value.trim()) {
      payload.api_key_override = newApiKey.value.trim();
    }

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
    await fetchScouts();
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

const navigateToTools = () => {
  router.push({
    name: 'scout_tools',
    params: { accountId: accountId.value },
  });
};

onMounted(() => {
  fetchScouts();
});
</script>

<template>
  <div class="flex flex-col w-full h-full m-0 pb-8 pt-4 px-6 overflow-auto bg-n-surface-1">
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
              :label="t('SCOUT.TOOLS.TITLE')"
              variant="faded"
              color="slate"
              size="sm"
              @click="navigateToTools"
            />
            <Button
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

      <!-- Empty State -->
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
                <span class="block text-heading-3 text-n-slate-12 capitalize">
                  {{ item.name }}
                </span>
                <span
                  class="text-[10px] font-medium px-1.5 py-0.5 rounded-sm bg-n-alpha-2 text-n-slate-11 uppercase"
                >
                  {{ item.provider }}
                </span>
              </div>

              <span class="text-body-main text-n-slate-11 line-clamp-1">
                {{
                  item.persona ||
                  `${item.model_name} • ${t('SCOUT.INBOXES_COUNT', { count: item.inboxes ? item.inboxes.length : 0 })}`
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

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ t('SCOUT.PROVIDER_LABEL') }}
            </label>
            <Select
              v-model="newProvider"
              class="!w-full [&>select]:w-full"
              :options="providerOptions"
            />
          </div>

          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ t('SCOUT.MODEL_NAME_LABEL') }}
            </label>
            <Input v-model="newModelName" placeholder="gemini-2.5-flash" />
          </div>
        </div>

        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.API_KEY_OVERRIDE_LABEL') }}
          </label>
          <Input
            v-model="newApiKey"
            type="password"
            :placeholder="t('SCOUT.API_KEY_OVERRIDE_PLACEHOLDER')"
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
