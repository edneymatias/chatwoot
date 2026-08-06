<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ContactOpportunityCard from 'dashboard/components-next/Opportunities/ContactOpportunityCard.vue';
import OpportunityBackfillModal from 'dashboard/components-next/Opportunities/OpportunityBackfillModal.vue';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
});

const store = useStore();

const cardsForContactGetter = useMapGetter('opportunities/cardsForContact');
const opportunities = computed(() =>
  cardsForContactGetter.value(props.contactId)
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
  <div>
    <div v-if="!opportunities.length" class="text-n-slate-11 mb-4 px-4 p-3">
      <span>{{ $t('CONVERSATION_SIDEBAR.PREVIOUS_OPPORTUNITIES.EMPTY') }}</span>
    </div>
    <div v-else class="flex flex-col [&>*:last-child]:!border-b-0">
      <ContactOpportunityCard
        v-for="opportunity in opportunities"
        :key="opportunity.id"
        :opportunity="opportunity"
        @click="openBackfillModal"
      />
    </div>
    <OpportunityBackfillModal
      v-if="isBackfillModalOpen"
      :opportunity-id="backfillOpportunityId"
      @close="closeBackfillModal"
    />
  </div>
</template>
