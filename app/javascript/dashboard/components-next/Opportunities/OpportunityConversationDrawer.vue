<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useConversationDrawer } from '../../composables/useConversationDrawer';
import ConversationBox from '../../components/widgets/conversation/ConversationBox.vue';
import ConversationSidebar from '../../components/widgets/conversation/ConversationSidebar.vue';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useStore } from 'vuex';
import Spinner from 'shared/components/Spinner.vue';

const router = useRouter();
const store = useStore();
const { loading, ready, error } = useConversationDrawer();

const currentChat = computed(() => store.getters.getSelectedChat);

const { uiSettings } = useUISettings();
const shouldShowSidebar = computed(() => {
  if (!currentChat.value.id) return false;
  return uiSettings.value.is_contact_sidebar_open;
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
        class="flex flex-col justify-center items-center absolute top-20 ltr:left-2 rtl:right-2 bg-n-solid-2/90 backdrop-blur-lg border border-n-weak/50 rounded-full gap-1.5 p-1.5 shadow-sm transition-shadow duration-200 hover:shadow !z-20"
      >
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
          v-tooltip.right="isExpanded ? 'Recolher painel' : 'Expandir painel'"
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

      <div class="flex relative w-full h-full min-w-0">
        <ConversationBox
          :inbox-id="currentChat.inbox_id"
          :is-on-expanded-layout="false"
          class="flex-grow min-w-0"
        >
          <SidepanelSwitch v-if="currentChat.id" />
        </ConversationBox>
        <ConversationSidebar
          v-if="shouldShowSidebar"
          :current-chat="currentChat"
        />
      </div>
    </template>
  </div>
</template>
