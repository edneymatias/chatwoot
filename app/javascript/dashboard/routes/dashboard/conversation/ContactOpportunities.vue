<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ContactOpportunityCard from 'dashboard/components-next/Opportunities/ContactOpportunityCard.vue';
import OpportunityBackfillModal from 'dashboard/components-next/Opportunities/OpportunityBackfillModal.vue';
import OpportunityCreateModal from 'dashboard/components-next/Opportunities/OpportunityCreateModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
});

const store = useStore();

const cardsForContactGetter = useMapGetter('opportunities/cardsForContact');
const baseOpportunities = computed(
  () => cardsForContactGetter.value(props.contactId) || []
);

const currentChat = useMapGetter('getSelectedChat');
const contactGetter = useMapGetter('contacts/getContact');
const contact = computed(() => contactGetter.value(props.contactId));

const initialContact = computed(() => {
  if (!contact.value) return null;
  return {
    id: contact.value.id,
    name: contact.value.name,
    email: contact.value.email,
  };
});

const opportunities = computed(() => {
  const currentChatId = currentChat.value?.id;
  if (!currentChatId) return baseOpportunities.value;

  const currentMatch = baseOpportunities.value.find(
    o => o.origin_conversation_id === currentChatId
  );
  if (!currentMatch) return baseOpportunities.value;

  const others = baseOpportunities.value.filter(
    o => o.origin_conversation_id !== currentChatId
  );
  return [currentMatch, ...others];
});

const isAddDisabled = computed(() => {
  const currentChatId = currentChat.value?.id;
  if (!currentChatId) return false;
  return baseOpportunities.value.some(
    o => o.origin_conversation_id === currentChatId
  );
});

const isCreateModalOpen = ref(false);
const openCreateModal = () => {
  isCreateModalOpen.value = true;
};
const closeCreateModal = () => {
  isCreateModalOpen.value = false;
};

watch(
  () => currentChat.value?.id,
  () => {
    isCreateModalOpen.value = false;
  }
);

const backfillOpportunityId = ref(null);
const isBackfillModalOpen = computed(() => !!backfillOpportunityId.value);

const openBackfillModal = opportunityId => {
  backfillOpportunityId.value = opportunityId;
};

const closeBackfillModal = () => {
  backfillOpportunityId.value = null;
};

watch(
  () => props.contactId,
  (newId, oldId) => {
    if (newId && newId !== oldId) {
      store.dispatch('opportunities/fetchForContact', { contactId: newId });
    }
  }
);

onMounted(() => {
  store.dispatch('pipelineStages/fetch');
  store.dispatch('pipelineCardFieldConfigs/fetch');
  store.dispatch('pipelineCurrencySetting/fetch');
  store.dispatch('opportunities/fetchForContact', {
    contactId: props.contactId,
  });
});
</script>

<template>
  <div class="flex flex-col">
    <div class="px-4 pt-3 pb-2">
      <Button
        ghost
        xs
        icon="i-lucide-plus"
        :label="
          $t('CONVERSATION_SIDEBAR.PREVIOUS_OPPORTUNITIES.ADD_OPPORTUNITY')
        "
        :disabled="isAddDisabled"
        @click="openCreateModal"
      />
    </div>
    <div v-if="!opportunities.length" class="text-n-slate-11 mb-4 px-4 p-3">
      <span>{{ $t('CONVERSATION_SIDEBAR.PREVIOUS_OPPORTUNITIES.EMPTY') }}</span>
    </div>
    <div v-else class="flex flex-col [&>*:last-child]:!border-b-0">
      <ContactOpportunityCard
        v-for="opportunity in opportunities"
        :key="opportunity.id"
        :opportunity="opportunity"
        :is-current-conversation="
          currentChat && opportunity.origin_conversation_id === currentChat.id
        "
        @click="openBackfillModal"
      />
    </div>
    <OpportunityBackfillModal
      v-if="isBackfillModalOpen"
      :opportunity-id="backfillOpportunityId"
      @close="closeBackfillModal"
    />
    <OpportunityCreateModal
      v-if="isCreateModalOpen"
      :origin-conversation-id="currentChat?.id"
      :initial-contact="initialContact"
      @close="closeCreateModal"
      @created="closeCreateModal"
    />
  </div>
</template>
