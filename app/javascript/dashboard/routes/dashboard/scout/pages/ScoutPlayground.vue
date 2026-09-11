<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ScoutPlaygroundChat from 'dashboard/components-next/Scout/pageComponents/ScoutPlaygroundChat.vue';

const route = useRoute();
const { t } = useI18n();

const scout = ref(null);
const isLoading = ref(true);

const scoutId = computed(() => route.params.scoutId);
const accountId = computed(() => route.params.accountId);

const backUrl = computed(() => ({
  name: 'scout_detail',
  params: { accountId: accountId.value, scoutId: scoutId.value },
}));

const fetchScout = async () => {
  isLoading.value = true;
  try {
    const { data } = await ScoutAPI.show(scoutId.value);
    scout.value = data;
  } catch (error) {
    // Handled
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  fetchScout();
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <!-- Header -->
    <header
      class="sticky top-0 z-10 px-6 border-b border-n-weak bg-n-surface-1"
    >
      <div
        class="w-full max-w-5xl mx-auto flex items-center justify-between h-20"
      >
        <div class="flex items-center gap-3">
          <BackButton :back-url="backUrl" />
          <div>
            <div class="flex items-center gap-2">
              <h1 class="text-xl font-medium text-n-slate-12">
                {{ t('SCOUT.PLAYGROUND.TITLE') }}
              </h1>
              <span v-if="scout" class="text-sm font-medium text-n-brand">
                {{ `(${scout.name})` }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </header>

    <!-- Main Playground Area -->
    <main class="flex-1 px-6 overflow-hidden">
      <div class="w-full max-w-5xl mx-auto py-4 h-full flex flex-col">
        <div
          v-if="isLoading"
          class="flex items-center justify-center py-20 text-n-slate-11"
        >
          <Spinner />
        </div>

        <ScoutPlaygroundChat
          v-else-if="scout"
          :scout="scout"
          class="flex-1 min-h-0"
        />
      </div>
    </main>
  </section>
</template>
