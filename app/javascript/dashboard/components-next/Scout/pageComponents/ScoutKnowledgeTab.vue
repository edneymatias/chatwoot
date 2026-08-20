<script setup>
import { ref, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ScoutKnowledgeSourceModal from './ScoutKnowledgeSourceModal.vue';

const props = defineProps({
  scout: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const sources = ref([]);
const isLoading = ref(true);
const sourceModalRef = ref(null);

const fetchSources = async () => {
  isLoading.value = true;
  try {
    const { data } = await ScoutAPI.getKnowledgeSources(props.scout.id);
    sources.value = Array.isArray(data) ? data : [];
  } catch (error) {
    sources.value = [];
  } finally {
    isLoading.value = false;
  }
};

const handleOpenAdd = () => {
  nextTick(() => {
    sourceModalRef.value?.openModal();
  });
};

const handleReprocess = async sourceId => {
  try {
    await ScoutAPI.reprocessKnowledgeSource(props.scout.id, sourceId);
    await fetchSources();
  } catch (error) {
    // Handled
  }
};

const handleDelete = async sourceId => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('SCOUT.KNOWLEDGE.CONFIRM_DELETE'))) return;

  try {
    await ScoutAPI.deleteKnowledgeSource(props.scout.id, sourceId);
    await fetchSources();
  } catch (error) {
    // Handled
  }
};

onMounted(() => {
  fetchSources();
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex items-center justify-between pb-4">
      <div>
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('SCOUT.KNOWLEDGE.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11 mt-0.5">
          {{ t('SCOUT.KNOWLEDGE.SUBTITLE') }}
        </p>
      </div>
      <Button
        :label="t('SCOUT.KNOWLEDGE.ADD_BUTTON')"
        color="blue"
        size="sm"
        @click="handleOpenAdd"
      />
    </div>

    <!-- Loading -->
    <div
      v-if="isLoading"
      class="flex items-center justify-center py-12 text-n-slate-11"
    >
      <Spinner />
    </div>

    <!-- Sources List -->
    <div v-else-if="sources.length > 0" class="divide-y divide-n-weak">
      <div
        v-for="item in sources"
        :key="item.id"
        class="flex items-center justify-between py-4 first:pt-0 last:pb-0"
      >
        <div class="flex items-start gap-3">
          <div
            class="flex items-center justify-center size-9 rounded-lg bg-n-alpha-1 text-n-brand mt-0.5"
          >
            <span v-if="item.kind === 'url'" class="i-lucide-globe size-4" />
            <span
              v-else-if="item.kind === 'document'"
              class="i-lucide-file-text size-4"
            />
            <span v-else class="i-lucide-help-circle size-4" />
          </div>
          <div>
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium text-n-slate-12">
                <template v-if="item.kind === 'url'">{{ item.url }}</template>
                <template v-else-if="item.kind === 'document'">{{
                  item.filename || 'PDF Document'
                }}</template>
                <template v-else>{{ item.question }}</template>
              </span>

              <!-- Status Badge -->
              <span
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-medium"
                :class="{
                  'bg-amber-500/10 text-amber-600 dark:text-amber-400':
                    item.status === 'pending',
                  'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400':
                    item.status === 'ready',
                  'bg-ruby-500/10 text-ruby-600 dark:text-ruby-400':
                    item.status === 'failed',
                }"
              >
                <span
                  v-if="item.status === 'pending'"
                  class="i-lucide-loader-2 size-2.5 animate-spin"
                />
                {{ item.status }}
              </span>
            </div>

            <p
              v-if="item.kind === 'faq'"
              class="text-xs text-n-slate-11 mt-1 line-clamp-2"
            >
              {{ item.answer }}
            </p>
            <p v-if="item.error_message" class="text-xs text-n-ruby-9 mt-1">
              {{ item.error_message }}
            </p>
          </div>
        </div>

        <div class="flex items-center gap-1">
          <Button
            v-if="item.status === 'failed' || item.status === 'ready'"
            icon="i-lucide-refresh-cw"
            variant="ghost"
            color="slate"
            size="xs"
            @click="handleReprocess(item.id)"
          />
          <Button
            icon="i-lucide-trash-2"
            variant="ghost"
            color="ruby"
            size="xs"
            @click="handleDelete(item.id)"
          />
        </div>
      </div>
    </div>

    <div
      v-else
      class="py-12 flex flex-col items-center justify-center text-center text-n-slate-11 border border-dashed border-n-weak rounded-xl"
    >
      <span class="i-lucide-book-open size-8 text-n-slate-10 mb-2" />
      <p class="text-sm font-medium text-n-slate-12">
        {{ t('SCOUT.KNOWLEDGE.EMPTY_TITLE') }}
      </p>
      <p class="text-xs text-n-slate-10 mt-1 max-w-sm">
        {{ t('SCOUT.KNOWLEDGE.EMPTY_DESC') }}
      </p>
    </div>
    <!-- Knowledge Source Modal -->
    <ScoutKnowledgeSourceModal
      ref="sourceModalRef"
      :scout-id="scout.id"
      @saved="fetchSources"
    />
  </div>
</template>
