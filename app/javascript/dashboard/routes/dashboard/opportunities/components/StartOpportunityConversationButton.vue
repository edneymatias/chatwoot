<script setup>
import { ref, watch, computed } from 'vue';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import OpportunityConversationLinkModal from 'dashboard/components-next/Opportunities/OpportunityConversationLinkModal.vue';
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

const isFetching = ref(false);
const isTracking = ref(false);
const showLinkModal = ref(false);
const composeButtonRef = ref(null);
const knownConversationIds = ref(new Set());

const contactConversations = computed(() => {
  return (
    store.getters['contactConversations/getContactConversation'](
      props.opportunity.contact_id
    ) || []
  );
});

const openConversations = computed(() => {
  return contactConversations.value.filter(
    c => c.status === 'open' || c.status === 0
  );
});

const triggerCompose = () => {
  const btn = composeButtonRef.value;
  if (btn) {
    btn.click();
  }
};

const onTriggerClick = async () => {
  if (isFetching.value) return;
  isFetching.value = true;
  isTracking.value = false;

  try {
    await Promise.all([
      store.dispatch('contacts/show', { id: props.opportunity.contact_id }),
      store.dispatch(
        'contacts/fetchContactableInbox',
        props.opportunity.contact_id
      ),
      store.dispatch('contactConversations/get', props.opportunity.contact_id),
    ]);
  } catch (error) {
    // Continue anyway
  } finally {
    isFetching.value = false;
  }

  // Snapshot current conversation IDs to only detect newly created ones
  knownConversationIds.value = new Set(
    contactConversations.value.map(c => c.id)
  );

  if (openConversations.value.length > 0) {
    showLinkModal.value = true;
  } else {
    isTracking.value = true;
    triggerCompose();
  }
};

const handleStartNew = () => {
  showLinkModal.value = false;
  knownConversationIds.value = new Set(
    contactConversations.value.map(c => c.id)
  );
  isTracking.value = true;
  setTimeout(() => {
    triggerCompose();
  }, 100);
};

const handleCloseCompose = () => {
  isTracking.value = false;
};

watch(
  contactConversations,
  async newConversations => {
    if (!isTracking.value) return;

    const newlyCreated = newConversations.find(
      c =>
        !knownConversationIds.value.has(c.id) &&
        (c.status === 'open' || c.status === 0)
    );

    if (newlyCreated) {
      isTracking.value = false;
      knownConversationIds.value.add(newlyCreated.id);

      try {
        await store.dispatch('opportunities/linkConversation', {
          id: props.opportunity.id,
          conversationId: newlyCreated.id,
        });

        router.push({
          name: 'opportunities_conversation',
          params: {
            accountId: route.params.accountId,
            conversationId: newlyCreated.display_id || newlyCreated.id,
          },
        });
      } catch (error) {
        // Continue
      }
    }
  },
  { deep: true }
);
</script>

<template>
  <div class="relative" @click.stop>
    <!-- Visible Trigger Button -->
    <Button
      v-tooltip.bottom="
        $t('OPPORTUNITIES.START_CONVERSATION', 'Start conversation')
      "
      variant="ghost"
      color="slate"
      size="sm"
      :is-loading="isFetching"
      icon="i-lucide-message-square-plus"
      @click="onTriggerClick"
    />

    <!-- Compose Popover Anchor -->
    <div
      class="absolute inset-0 pointer-events-none opacity-0 w-0 h-0 overflow-hidden"
    >
      <ComposeConversation
        :contact-id="String(opportunity.contact_id)"
        align="end"
        @close="handleCloseCompose"
      >
        <template #trigger>
          <button
            ref="composeButtonRef"
            type="button"
            class="pointer-events-auto"
          />
        </template>
      </ComposeConversation>
    </div>

    <!-- Link Modal -->
    <OpportunityConversationLinkModal
      v-if="showLinkModal"
      :opportunity="opportunity"
      :open-conversations="openConversations"
      @close="showLinkModal = false"
      @start-new="handleStartNew"
    />
  </div>
</template>
