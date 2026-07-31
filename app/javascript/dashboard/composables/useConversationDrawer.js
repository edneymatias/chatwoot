import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useRoute, onBeforeRouteLeave } from 'vue-router';
import ConversationApi from 'dashboard/api/inbox/conversation';

export const useConversationDrawer = () => {
  const store = useStore();
  const route = useRoute();

  const loading = ref(false);
  const ready = ref(false);
  const error = ref(false);

  const currentChat = computed(() => store.getters.getSelectedChat);

  const findConversation = id => {
    return store.getters.getConversationById(id);
  };

  const clearSelected = () => {
    store.dispatch('clearSelectedState');
  };

  const processConversation = async id => {
    if (!id) return;

    loading.value = true;
    ready.value = false;
    error.value = false;

    let chat = findConversation(id);
    if (!chat) {
      try {
        const response = await ConversationApi.show(id);
        store.commit('ADD_CONVERSATION', response.data);
        if (response.data.meta && response.data.meta.sender) {
          store.commit('contacts/SET_CONTACT_ITEM', response.data.meta.sender);
        }
        chat = findConversation(id);
      } catch (e) {
        // error handled below
      }
    }

    if (!chat) {
      loading.value = false;
      error.value = true;
      return;
    }

    // if already active, do nothing
    if (currentChat.value?.id !== chat.id) {
      await store.dispatch('setActiveChat', { data: chat });
    }

    store.dispatch('markMessagesRead', { id });

    loading.value = false;
    ready.value = true;
  };

  watch(
    () => route.params.conversationId,
    newId => {
      if (newId) {
        processConversation(Number(newId));
      }
    },
    { immediate: true }
  );

  onBeforeUnmount(() => {
    clearSelected();
  });

  onBeforeRouteLeave((to, from, next) => {
    if (from.params.conversationId) {
      clearSelected();
    }
    next();
  });

  return {
    loading,
    ready,
    error,
  };
};
