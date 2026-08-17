<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import { dynamicTime } from 'shared/helpers/timeHelper';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
  openConversations: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close', 'startNew', 'linked']);

const store = useStore();
const router = useRouter();

const selectedConversationId = ref(props.openConversations[0]?.id || null);
const isSubmitting = ref(false);
const showTransferWarning = ref(false);
const conflictingOpportunity = ref(null);

watch(
  () => props.openConversations,
  newConvs => {
    if (!selectedConversationId.value && newConvs && newConvs.length > 0) {
      selectedConversationId.value = newConvs[0].id;
    }
  },
  { immediate: true }
);

const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);

const getInbox = inboxId => {
  return inboxes.value.find(i => i.id === inboxId);
};

const getInboxIcon = channelType => {
  switch (channelType) {
    case 'Channel::Whatsapp':
      return 'i-ri-whatsapp-line';
    case 'Channel::FacebookPage':
      return 'i-ri-messenger-line';
    case 'Channel::Instagram':
      return 'i-ri-instagram-line';
    case 'Channel::Telegram':
      return 'i-ri-telegram-line';
    case 'Channel::Email':
      return 'i-ri-mail-line';
    default:
      return 'i-ri-chat-1-line';
  }
};

const formatTime = timestamp => {
  if (!timestamp) return '';
  const num = Number(timestamp);
  if (!Number.isNaN(num)) {
    const seconds = num > 1e11 ? Math.floor(num / 1000) : num;
    return dynamicTime(seconds);
  }
  const date = new Date(timestamp);
  return dynamicTime(Math.floor(date.getTime() / 1000));
};

const handleSelect = conversationId => {
  selectedConversationId.value = conversationId;
  showTransferWarning.value = false;
  conflictingOpportunity.value = null;
};

const handleLink = async (forceTransfer = false) => {
  if (!selectedConversationId.value) return;

  isSubmitting.value = true;
  try {
    const payload = await store.dispatch('opportunities/linkConversation', {
      id: props.opportunity.id,
      conversationId: selectedConversationId.value,
      forceTransfer,
    });

    emit('linked', payload);
    emit('close');

    router.push({
      name: 'opportunities_conversation',
      params: {
        conversationId:
          payload.active_conversation_display_id ||
          payload.active_conversation_id,
      },
    });
  } catch (error) {
    if (
      error.response?.status === 409 &&
      error.response?.data?.active_on_opportunity
    ) {
      conflictingOpportunity.value = error.response.data.active_on_opportunity;
      showTransferWarning.value = true;
    }
  } finally {
    isSubmitting.value = false;
  }
};

const handleStartNew = () => {
  emit('startNew');
  emit('close');
};

const onClose = () => emit('close');
</script>

<template>
  <TeleportWithDirection>
    <woot-modal show size="modal-medium" @close="onClose">
      <woot-modal-header
        :header-title="$t('OPPORTUNITIES.LINK_CONVERSATION_MODAL.TITLE')"
      />

      <div class="flex flex-col max-h-[80vh]">
        <div class="px-8 pt-4 pb-6 flex flex-col gap-4 overflow-y-auto">
          <p class="text-sm text-n-slate-11">
            {{ $t('OPPORTUNITIES.LINK_CONVERSATION_MODAL.DESCRIPTION') }}
          </p>

          <!-- Transfer Warning Alert -->
          <div
            v-if="showTransferWarning"
            class="p-3 bg-n-amber-3 border border-n-amber-6 rounded-md flex flex-col gap-2"
          >
            <div
              class="flex items-center gap-2 text-n-amber-11 font-medium text-sm"
            >
              <Icon icon="i-lucide-alert-triangle" class="size-4 shrink-0" />
              <span>
                {{
                  $t(
                    'OPPORTUNITIES.LINK_CONVERSATION_MODAL.TRANSFER_WARNING_TITLE'
                  )
                }}
              </span>
            </div>
            <p class="text-xs text-n-amber-11">
              {{
                $t(
                  'OPPORTUNITIES.LINK_CONVERSATION_MODAL.TRANSFER_WARNING_MESSAGE',
                  {
                    opportunity:
                      conflictingOpportunity?.title ||
                      `#${conflictingOpportunity?.id}`,
                  }
                )
              }}
            </p>
            <div class="flex justify-end gap-2 mt-1">
              <button
                type="button"
                class="px-2.5 py-1 text-xs font-medium text-n-slate-11 bg-n-surface-1 border border-n-slate-4 rounded hover:bg-n-surface-2"
                @click="showTransferWarning = false"
              >
                {{ $t('OPPORTUNITIES.LINK_CONVERSATION_MODAL.CANCEL') }}
              </button>
              <button
                type="button"
                class="px-2.5 py-1 text-xs font-medium text-white bg-n-amber-9 rounded hover:bg-n-amber-10"
                @click="handleLink(true)"
              >
                {{
                  $t('OPPORTUNITIES.LINK_CONVERSATION_MODAL.CONFIRM_TRANSFER')
                }}
              </button>
            </div>
          </div>

          <!-- Open Conversations List -->
          <div class="flex flex-col gap-2">
            <label class="text-xs font-medium uppercase text-n-slate-11">
              {{ $t('OPPORTUNITIES.LINK_CONVERSATION_MODAL.OPEN_CHATS_LABEL') }}
            </label>

            <div
              v-for="conv in openConversations"
              :key="conv.id"
              class="flex items-center justify-between p-3 border rounded-lg cursor-pointer transition-colors"
              :class="[
                selectedConversationId === conv.id
                  ? 'border-n-brand bg-n-brand/5 dark:bg-n-brand/10'
                  : 'border-n-slate-3 hover:bg-n-surface-2 bg-n-surface-1',
              ]"
              @click="handleSelect(conv.id)"
            >
              <div class="flex items-center gap-3 min-w-0">
                <input
                  type="radio"
                  name="conversation-select"
                  :value="conv.id"
                  :checked="selectedConversationId === conv.id"
                  class="accent-n-brand cursor-pointer"
                  @click.stop="handleSelect(conv.id)"
                />
                <div class="flex flex-col min-w-0">
                  <div class="flex items-center gap-2">
                    <Icon
                      :icon="
                        getInboxIcon(
                          conv.inbox?.channel_type ||
                            getInbox(conv.inbox_id)?.channel_type
                        )
                      "
                      class="size-4 text-n-slate-11 shrink-0"
                    />
                    <span class="text-sm font-medium text-n-slate-12 truncate">
                      {{
                        conv.inbox?.name ||
                        getInbox(conv.inbox_id)?.name ||
                        'Inbox'
                      }}
                    </span>
                    <span class="text-xs text-n-slate-10">
                      {{ `#${conv.display_id || conv.id}` }}
                    </span>
                  </div>
                  <p
                    v-if="conv.messages && conv.messages.length > 0"
                    class="text-xs text-n-slate-11 truncate mt-0.5"
                  >
                    {{ conv.messages[conv.messages.length - 1]?.content }}
                  </p>
                </div>
              </div>

              <div class="flex flex-col items-end shrink-0 pl-2">
                <span
                  class="text-[10px] px-1.5 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11 font-medium capitalize"
                >
                  {{ $t('OPPORTUNITIES.BOARD.STATUS.OPEN') }}
                </span>
                <span class="text-[11px] text-n-slate-10 mt-1">
                  {{ formatTime(conv.created_at) }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Modal Footer -->
        <div
          class="flex justify-between items-center px-8 py-4 border-t border-n-slate-3 shrink-0"
        >
          <Button
            variant="faded"
            color="slate"
            size="sm"
            icon="i-lucide-plus"
            :label="
              $t('OPPORTUNITIES.LINK_CONVERSATION_MODAL.START_NEW_BUTTON')
            "
            @click="handleStartNew"
          />

          <div class="flex items-center gap-2">
            <Button
              variant="ghost"
              color="slate"
              size="sm"
              :label="$t('OPPORTUNITIES.LINK_CONVERSATION_MODAL.CANCEL')"
              @click="onClose"
            />
            <Button
              variant="solid"
              color="blue"
              size="sm"
              :disabled="!selectedConversationId || isSubmitting"
              :is-loading="isSubmitting"
              :label="$t('OPPORTUNITIES.LINK_CONVERSATION_MODAL.LINK_BUTTON')"
              @click="handleLink(false)"
            />
          </div>
        </div>
      </div>
    </woot-modal>
  </TeleportWithDirection>
</template>
