<script setup>
import { ref, computed, onMounted, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  scout: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['updated']);
const { t } = useI18n();
const store = useStore();

const allInboxes = computed(() => store.getters['inboxes/getInboxes']);
const attachedInboxes = ref(props.scout.inboxes || []);
const selectedInboxId = ref('');
const isAttaching = ref(false);
const isDetaching = ref(false);
const attachDialogRef = ref(null);

const availableInboxes = computed(() => {
  const attachedIds = new Set(attachedInboxes.value.map(i => i.id));
  return allInboxes.value.filter(inbox => !attachedIds.has(inbox.id));
});

const inboxOptions = computed(() =>
  availableInboxes.value.map(inbox => ({
    value: inbox.id,
    label: `${inbox.name} (${inbox.channel_type})`,
  }))
);

const fetchInboxes = async () => {
  await store.dispatch('inboxes/get');
};

const handleOpenAttach = () => {
  selectedInboxId.value = '';
  nextTick(() => {
    attachDialogRef.value?.open();
  });
};

const handleAttachInbox = async () => {
  if (!selectedInboxId.value) return;

  isAttaching.value = true;
  try {
    await ScoutAPI.attachInbox(props.scout.id, selectedInboxId.value);
    attachDialogRef.value?.close();
    emit('updated');
  } catch (error) {
    // Handled
  } finally {
    isAttaching.value = false;
  }
};

const handleDetachInbox = async inboxId => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('SCOUT.INBOXES.CONFIRM_DETACH'))) return;

  isDetaching.value = true;
  try {
    await ScoutAPI.detachInbox(props.scout.id, inboxId);
    emit('updated');
  } catch (error) {
    // Handled
  } finally {
    isDetaching.value = false;
  }
};

onMounted(() => {
  fetchInboxes();
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex items-center justify-between pb-4">
      <div>
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('SCOUT.INBOXES.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11 mt-0.5">
          {{ t('SCOUT.INBOXES.SUBTITLE') }}
        </p>
      </div>
      <Button
        :label="t('SCOUT.INBOXES.ATTACH_BUTTON')"
        color="blue"
        size="sm"
        :disabled="availableInboxes.length === 0"
        @click="handleOpenAttach"
      />
    </div>

    <!-- Inboxes List -->
    <div
      v-if="scout.inboxes && scout.inboxes.length > 0"
      class="divide-y divide-n-weak"
    >
      <div
        v-for="inbox in scout.inboxes"
        :key="inbox.id"
        class="flex items-center justify-between py-3.5 first:pt-0 last:pb-0"
      >
        <div class="flex items-center gap-3">
          <div
            class="flex items-center justify-center size-9 rounded-lg bg-n-alpha-1 text-n-brand"
          >
            <span class="i-lucide-inbox size-4" />
          </div>
          <div>
            <span class="text-sm font-medium text-n-slate-12 block">
              {{ inbox.name }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{ inbox.channel_type }}
            </span>
          </div>
        </div>

        <Button
          :label="t('SCOUT.INBOXES.DETACH_ACTION')"
          variant="ghost"
          color="ruby"
          size="xs"
          @click="handleDetachInbox(inbox.id)"
        />
      </div>
    </div>

    <div
      v-else
      class="py-12 flex flex-col items-center justify-center text-center text-n-slate-11 border border-dashed border-n-weak rounded-xl"
    >
      <span class="i-lucide-inbox size-8 text-n-slate-10 mb-2" />
      <p class="text-sm font-medium text-n-slate-12">
        {{ t('SCOUT.INBOXES.EMPTY_TITLE') }}
      </p>
      <p class="text-xs text-n-slate-10 mt-1 max-w-sm">
        {{ t('SCOUT.INBOXES.EMPTY_DESC') }}
      </p>
    </div>
    <!-- Attach Dialog -->
    <Dialog
      ref="attachDialogRef"
      :title="t('SCOUT.INBOXES.ATTACH_MODAL_TITLE')"
      :description="t('SCOUT.INBOXES.ATTACH_MODAL_DESC')"
      :confirm-button-label="t('SCOUT.INBOXES.ATTACH_SUBMIT')"
      :cancel-button-label="t('SCOUT.INBOXES.ATTACH_CANCEL')"
      :disable-confirm-button="!selectedInboxId || isAttaching"
      :is-loading="isAttaching"
      width="md"
      @confirm="handleAttachInbox"
    >
      <div class="py-2 space-y-2">
        <label class="block text-xs font-medium text-n-slate-11">
          {{ t('SCOUT.INBOXES.SELECT_LABEL') }}
        </label>
        <Select
          v-model="selectedInboxId"
          class="!w-full [&>select]:w-full"
          :options="inboxOptions"
          :placeholder="t('SCOUT.INBOXES.SELECT_PLACEHOLDER')"
        />
        <p
          class="text-[11px] text-amber-600 dark:text-amber-400 mt-2 flex items-center gap-1"
        >
          <span class="i-lucide-alert-triangle size-3.5" />
          {{ t('SCOUT.INBOXES.REASSIGN_WARNING') }}
        </p>
      </div>
    </Dialog>
  </div>
</template>
