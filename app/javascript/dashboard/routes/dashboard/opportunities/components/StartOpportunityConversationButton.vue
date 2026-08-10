<script setup>
import { ref, watch, computed } from 'vue';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
});

const store = useStore();
const router = useRouter();
const route = useRoute();

const isTracking = ref(false);
let initialConversationsLength = 0;

const contactConversations = computed(() => {
  return (
    store.getters['contactConversations/getContactConversation'](
      props.opportunity.contact_id
    ) || []
  );
});

const snapshotConversations = () => {
  initialConversationsLength = contactConversations.value.length;
  isTracking.value = true;
};

const handleClose = () => {
  isTracking.value = false;
};

watch(
  contactConversations,
  async newConversations => {
    if (
      isTracking.value &&
      newConversations.length > initialConversationsLength
    ) {
      const newConversation = newConversations[newConversations.length - 1];

      // Stop tracking immediately to prevent duplicate triggers
      isTracking.value = false;

      try {
        await store.dispatch('opportunities/update', {
          id: props.opportunity.id,
          origin_conversation_id: newConversation.id,
        });

        router.push({
          name: 'opportunities_conversation',
          params: {
            accountId: route.params.accountId,
            conversationId: newConversation.display_id || newConversation.id,
          },
        });
      } catch (error) {
        // Handle error if needed
      }
    }
  },
  { deep: true }
);
</script>

<template>
  <div @click.stop>
    <ComposeConversation
      :contact-id="String(opportunity.contact_id)"
      align="end"
      @close="handleClose"
    >
      <template #trigger>
        <Button
          v-tooltip.bottom="
            $t('OPPORTUNITIES.START_CONVERSATION', 'Start conversation')
          "
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-message-square-plus"
          @click="snapshotConversations"
        />
      </template>
    </ComposeConversation>
  </div>
</template>
