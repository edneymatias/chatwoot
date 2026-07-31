<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  originConversationId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['close', 'created']);

const store = useStore();

const title = ref('');
const selectedStageId = ref('');
const searchQuery = ref('');
const searchResults = ref([]);
const selectedContact = ref(null);
const isSearching = ref(false);

const stages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition']
);
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
      const response = await store.dispatch('contacts/search', {
        search: searchQuery.value,
      });
      // response is usually the array directly from the action or payload
      searchResults.value = Array.isArray(response)
        ? response
        : response.payload || [];
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

const submit = async () => {
  if (!canSubmit.value) return;

  try {
    const opp = await store.dispatch('opportunities/create', {
      title: title.value.trim(),
      contactId: selectedContact.value.id,
      pipelineStageId: selectedStageId.value,
      originConversationId: props.originConversationId,
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

      <div class="flex justify-end gap-2 mt-4">
        <button
          class="px-4 py-2 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 transition-colors"
          @click="onClose"
        >
          {{ $t('OPPORTUNITIES.CREATE_MODAL.CANCEL') }}
        </button>
        <button
          :disabled="!canSubmit || isSubmitting"
          class="px-4 py-2 text-sm font-medium bg-n-brand-9 text-white rounded-md hover:bg-n-brand-10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center min-w-[100px]"
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
