<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import ContactAPI from 'dashboard/api/contacts';
import OpportunityRequiredFieldsForm from './OpportunityRequiredFieldsForm.vue';

const props = defineProps({
  originConversationId: {
    type: Number,
    default: null,
  },
  defaultStageId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['close', 'created']);

const store = useStore();

const title = ref('');
const selectedStageId = ref(props.defaultStageId || '');
const searchQuery = ref('');
const searchResults = ref([]);
const selectedContact = ref(null);
const isSearching = ref(false);
const assigneeId = ref(null);

const agents = computed(() => store.getters['agents/getVerifiedAgents']);

onMounted(() => {
  store.dispatch('agents/get');
});

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);

const destinationStage = computed(() => {
  if (!selectedStageId.value) return null;
  return store.getters['pipelineStages/stageById'](selectedStageId.value);
});

const requiredDefs = computed(() => {
  if (
    !destinationStage.value ||
    !destinationStage.value.required_custom_attribute_definitions
  )
    return [];
  return destinationStage.value.required_custom_attribute_definitions;
});

const requiresDealValue = computed(
  () => destinationStage.value?.requires_deal_value || false
);

const customAttributes = ref({});
const dealValue = ref(null);
const missingCustomAttributeKeys = ref([]);
const missingDealValue = ref(false);

const canSubmit = computed(
  () => title.value.trim() && selectedStageId.value && selectedContact.value
);
const isSubmitting = computed(
  () => store.state.opportunities.uiFlags.isCreating
);

let searchTimeout = null;

const onSearch = () => {
  if (searchTimeout) clearTimeout(searchTimeout);

  if (!searchQuery.value.trim()) {
    searchResults.value = [];
    return;
  }

  isSearching.value = true;
  searchTimeout = setTimeout(async () => {
    try {
      const response = await ContactAPI.search(searchQuery.value);
      searchResults.value = response.data.payload || [];
    } catch (e) {
      searchResults.value = [];
    } finally {
      isSearching.value = false;
    }
  }, 300);
};

const selectContact = contact => {
  selectedContact.value = contact;
  searchQuery.value = '';
  searchResults.value = [];
};

const onClose = () => {
  emit('close');
};

const validateForm = () => {
  let isValid = true;
  missingCustomAttributeKeys.value = [];
  missingDealValue.value = false;

  requiredDefs.value.forEach(def => {
    if (
      customAttributes.value[def.attribute_key] === undefined ||
      customAttributes.value[def.attribute_key] === null ||
      customAttributes.value[def.attribute_key] === ''
    ) {
      missingCustomAttributeKeys.value.push(def.attribute_key);
      isValid = false;
    }
  });

  if (
    requiresDealValue.value &&
    (dealValue.value === undefined ||
      dealValue.value === null ||
      dealValue.value === '')
  ) {
    missingDealValue.value = true;
    isValid = false;
  }

  return isValid;
};

const submit = async () => {
  if (!canSubmit.value) return;
  if (!validateForm()) return;

  try {
    const opp = await store.dispatch('opportunities/create', {
      title: title.value.trim(),
      contactId: selectedContact.value.id,
      pipelineStageId: selectedStageId.value,
      originConversationId: props.originConversationId,
      custom_attributes: customAttributes.value,
      value: dealValue.value,
      assigneeId: assigneeId.value,
    });
    emit('created', opp);
    onClose();
  } catch (error) {
    // Error handled by store/API client
  }
};
</script>

<template>
  <woot-modal show size="modal-medium" @close="onClose">
    <woot-modal-header :header-title="$t('OPPORTUNITIES.CREATE_MODAL.TITLE')" />

    <div class="p-6 pt-2 flex flex-col gap-4">
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('OPPORTUNITIES.CREATE_MODAL.TITLE_LABEL') }}
        </label>
        <input
          v-model="title"
          type="text"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
          :placeholder="$t('OPPORTUNITIES.CREATE_MODAL.TITLE_PLACEHOLDER')"
        />
      </div>

      <div class="flex flex-col gap-1 relative">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('OPPORTUNITIES.CREATE_MODAL.CONTACT_LABEL') }}
        </label>
        <div
          v-if="selectedContact"
          class="flex items-center justify-between px-3 py-2 border border-n-weak rounded-md bg-n-surface-2 text-sm"
        >
          <span>
            {{ selectedContact.name }}
            <span v-if="selectedContact.email" class="text-n-slate-11">
              ({{ selectedContact.email }})
            </span>
          </span>
          <button
            class="text-n-slate-11 hover:text-n-slate-12 text-xs"
            @click="selectedContact = null"
          >
            {{ $t('OPPORTUNITIES.CREATE_MODAL.CLEAR') }}
          </button>
        </div>
        <div v-else>
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="$t('OPPORTUNITIES.CREATE_MODAL.SEARCH_PLACEHOLDER')"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
            @input="onSearch"
          />
          <div
            v-if="searchQuery"
            class="absolute left-0 right-0 mt-1 bg-n-surface-1 border border-n-weak rounded-md shadow-lg z-10 max-h-60 overflow-y-auto"
          >
            <div
              v-if="isSearching"
              class="p-3 text-sm text-n-slate-11 text-center"
            >
              {{ $t('OPPORTUNITIES.BOARD.LOADING') }}
            </div>
            <div
              v-else-if="searchResults.length === 0"
              class="p-3 text-sm text-n-slate-11 text-center"
            >
              {{ $t('OPPORTUNITIES.CREATE_MODAL.NO_RESULTS') }}
            </div>
            <div v-else>
              <div
                v-for="contact in searchResults"
                :key="contact.id"
                class="px-3 py-2 hover:bg-n-surface-2 cursor-pointer text-sm flex items-center justify-between"
                @click="selectContact(contact)"
              >
                <span class="font-medium text-n-slate-12">{{
                  contact.name
                }}</span>
                <span class="text-n-slate-11 text-xs">{{ contact.email }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('OPPORTUNITIES.CREATE_MODAL.STAGE_LABEL') }}
        </label>
        <select
          v-model="selectedStageId"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
        >
          <option value="" disabled>
            {{ $t('OPPORTUNITIES.CREATE_MODAL.STAGE_PLACEHOLDER') }}
          </option>
          <option v-for="stage in stages" :key="stage.id" :value="stage.id">
            {{ stage.name }}
          </option>
        </select>
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('OPPORTUNITIES.CREATE_MODAL.ASSIGNEE_LABEL') }}
        </label>
        <select
          v-model="assigneeId"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
        >
          <option :value="null">
            {{ $t('OPPORTUNITIES.CREATE_MODAL.ASSIGNEE_UNASSIGNED') }}
          </option>
          <option v-for="agent in agents" :key="agent.id" :value="agent.id">
            {{ agent.name }}
          </option>
        </select>
      </div>

      <OpportunityRequiredFieldsForm
        v-if="requiredDefs.length || requiresDealValue"
        v-model:custom-attributes="customAttributes"
        v-model:deal-value="dealValue"
        :required-custom-attribute-definitions="requiredDefs"
        :requires-deal-value="requiresDealValue"
        :missing-custom-attribute-keys="missingCustomAttributeKeys"
        :missing-deal-value="missingDealValue"
      />

      <div class="flex justify-end gap-2 mt-4">
        <button
          class="px-4 py-2 text-sm font-medium bg-n-button-color text-n-slate-12 rounded-md hover:bg-n-alpha-2 transition-colors disabled:opacity-50 min-w-[100px]"
          @click="onClose"
        >
          {{ $t('OPPORTUNITIES.CREATE_MODAL.CANCEL') }}
        </button>
        <button
          :disabled="!canSubmit || isSubmitting"
          class="px-4 py-2 text-sm font-medium bg-n-brand text-white rounded-md hover:brightness-110 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center min-w-[100px]"
          @click="submit"
        >
          <span
            v-if="isSubmitting"
            class="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"
          />
          <span v-else>{{ $t('OPPORTUNITIES.CREATE_MODAL.SUBMIT') }}</span>
        </button>
      </div>
    </div>
  </woot-modal>
</template>
