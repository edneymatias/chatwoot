<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useConversationDrawer } from '../../composables/useConversationDrawer';
import ConversationBox from '../../components/widgets/conversation/ConversationBox.vue';
import ConversationSidebar from '../../components/widgets/conversation/ConversationSidebar.vue';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import OpportunityActivityLog from 'dashboard/components-next/Opportunities/OpportunityActivityLog.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useStore } from 'vuex';
import Spinner from 'shared/components/Spinner.vue';

const router = useRouter();
const route = useRoute();
const store = useStore();
const { loading, ready, error, processConversation } = useConversationDrawer();
const { isCloudFeatureEnabled } = useAccount();

const currentChat = computed(() => store.getters.getSelectedChat);
const isOpportunitiesFeatureEnabled = computed(() => {
  if (route.name && String(route.name).startsWith('opportunities')) return true;
  return isCloudFeatureEnabled(FEATURE_FLAGS.OPPORTUNITIES);
});

const currentOpportunity = computed(() => {
  const queryOppId = route.query?.opportunityId;
  if (queryOppId) {
    const directOpp = store.getters['opportunities/cardById'](
      Number(queryOppId)
    );
    if (directOpp) return directOpp;
  }

  const chatId = currentChat.value?.id;
  const chatDisplayId = currentChat.value?.display_id;
  const routeParamId = route.params?.conversationId;

  return (
    (chatId &&
      store.getters['opportunities/opportunityByConversationId'](chatId)) ||
    (chatDisplayId &&
      store.getters['opportunities/opportunityByConversationId'](
        chatDisplayId
      )) ||
    (routeParamId &&
      store.getters['opportunities/opportunityByConversationId'](
        routeParamId
      )) ||
    null
  );
});

const activeTab = ref(
  route.params?.conversationId ? 'conversation' : 'activity'
);

watch(
  () => route.params?.conversationId,
  newId => {
    if (newId) {
      activeTab.value = 'conversation';
    } else {
      activeTab.value = 'activity';
    }
  }
);

watch(
  () => [currentChat.value?.id, currentChat.value?.meta?.sender?.id],
  ([, newContactId]) => {
    if (route.params?.conversationId) {
      activeTab.value = 'conversation';
    }
    if (newContactId && !currentOpportunity.value) {
      store.dispatch('opportunities/fetchForContact', {
        contactId: newContactId,
      });
    }
  },
  { immediate: true }
);

const onSelectConversation = conversationId => {
  activeTab.value = 'conversation';
  if (
    conversationId &&
    String(route.params?.conversationId) === String(conversationId)
  ) {
    processConversation(Number(conversationId));
  }
};

const { uiSettings } = useUISettings();
const shouldShowSidebar = computed(() => {
  if (!currentChat.value?.id) return false;
  return uiSettings.value?.is_contact_sidebar_open;
});

const close = () => {
  // Push back to the board explicitly
  router.push({
    name: 'opportunities_index',
    params: { accountId: store.getters.getCurrentAccountId },
  });
};

const isExpanded = ref(false);
const toggleExpand = () => {
  isExpanded.value = !isExpanded.value;
};

// Vertical drag functionality for the floating pill
const DEFAULT_TOP = 80;
const storedTop = Number(
  localStorage.getItem('chatwoot_opportunity_drawer_pill_top')
);
const pillTop = ref(
  !Number.isNaN(storedTop) && storedTop > 0 ? storedTop : DEFAULT_TOP
);
const isDragging = ref(false);
let startY = 0;
let startTop = 0;

const onDragMove = event => {
  if (!isDragging.value) return;
  const deltaY = event.clientY - startY;
  const maxTop = window.innerHeight - 200;
  const minTop = 16;
  pillTop.value = Math.max(minTop, Math.min(maxTop, startTop + deltaY));
};

const onDragEnd = () => {
  if (!isDragging.value) return;
  isDragging.value = false;
  localStorage.setItem(
    'chatwoot_opportunity_drawer_pill_top',
    String(pillTop.value)
  );
  window.removeEventListener('pointermove', onDragMove);
  window.removeEventListener('pointerup', onDragEnd);
};

const onDragStart = event => {
  isDragging.value = true;
  startY = event.clientY;
  startTop = pillTop.value;
  window.addEventListener('pointermove', onDragMove);
  window.addEventListener('pointerup', onDragEnd);
};

onBeforeUnmount(() => {
  window.removeEventListener('pointermove', onDragMove);
  window.removeEventListener('pointerup', onDragEnd);
});
</script>

<template>
  <div
    class="flex absolute right-0 top-0 bottom-0 h-full border-l border-n-weak bg-n-surface-1 shadow-xl z-[40] transition-all duration-300"
    :class="isExpanded ? 'w-full max-w-full' : 'w-[70rem] max-w-[70vw]'"
  >
    <div v-if="loading" class="flex w-full items-center justify-center">
      <Spinner size="lg" />
    </div>

    <div
      v-else-if="error"
      class="flex w-full flex-col items-center justify-center gap-4"
    >
      <span class="text-n-slate-11">
        {{ $t('OPPORTUNITIES.DETAIL.NOT_FOUND') }}
      </span>
      <button
        class="px-3 py-1.5 rounded-md bg-n-surface-2 text-n-slate-11 hover:bg-n-surface-3"
        @click="close"
      >
        {{ $t('GENERAL.CLOSE') }}
      </button>
    </div>

    <template v-else-if="ready">
      <ButtonGroup
        class="flex flex-col justify-center items-center absolute ltr:left-2 rtl:right-2 bg-n-solid-2/90 backdrop-blur-lg border border-n-weak/50 rounded-full gap-1 p-1.5 shadow-sm transition-shadow duration-200 hover:shadow !z-20 select-none"
        :class="{ 'shadow-md border-n-brand/40': isDragging }"
        :style="{ top: `${pillTop}px` }"
      >
        <!-- Drag Handle -->
        <div
          v-tooltip.right="$t('OPPORTUNITIES.ACTIVITY_LOG.DRAG_TO_MOVE')"
          class="flex items-center justify-center w-7 h-4 cursor-grab active:cursor-grabbing text-n-slate-9 hover:text-n-slate-12 transition-colors touch-none"
          @pointerdown="onDragStart"
        >
          <span class="i-ph-dots-six-vertical-bold text-xs" />
        </div>

        <Button
          v-tooltip.right="$t('GENERAL.CLOSE')"
          ghost
          slate
          sm
          class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:!brightness-105 active:duration-75"
          icon="i-ph-x-bold"
          @click="close"
        />
        <Button
          v-if="isOpportunitiesFeatureEnabled && currentOpportunity"
          v-tooltip.right="
            activeTab === 'conversation'
              ? $t('OPPORTUNITIES.ACTIVITY_LOG.VIEW_ACTIVITIES')
              : $t('OPPORTUNITIES.ACTIVITY_LOG.VIEW_CONVERSATION')
          "
          ghost
          slate
          sm
          class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:!brightness-105 active:duration-75"
          :icon="
            activeTab === 'conversation'
              ? 'i-ph-clock-counter-clockwise-bold'
              : 'i-ph-chat-circle-dots-bold'
          "
          @click="
            activeTab =
              activeTab === 'conversation' ? 'activity' : 'conversation'
          "
        />
        <Button
          v-tooltip.right="
            isExpanded
              ? $t('OPPORTUNITIES.ACTIVITY_LOG.COLLAPSE_DRAWER')
              : $t('OPPORTUNITIES.ACTIVITY_LOG.EXPAND_DRAWER')
          "
          ghost
          slate
          sm
          class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:!brightness-105 active:duration-75"
          :icon="
            isExpanded
              ? 'i-ph-caret-double-right-bold'
              : 'i-ph-caret-double-left-bold'
          "
          @click="toggleExpand"
        />
      </ButtonGroup>

      <div
        v-if="activeTab === 'activity' && currentOpportunity"
        class="flex relative w-full h-full min-w-0"
      >
        <OpportunityActivityLog
          :opportunity-id="currentOpportunity.id"
          @select-conversation="onSelectConversation"
        />
      </div>

      <div v-else class="flex relative w-full h-full min-w-0">
        <ConversationBox
          :inbox-id="currentChat?.inbox_id || 0"
          :is-on-expanded-layout="false"
          class="flex-grow min-w-0"
        >
          <SidepanelSwitch v-if="currentChat?.id" />
        </ConversationBox>
        <ConversationSidebar
          v-if="shouldShowSidebar"
          :current-chat="currentChat"
        />
      </div>
    </template>
  </div>
</template>
