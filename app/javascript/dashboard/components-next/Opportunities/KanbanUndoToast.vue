<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  toasts: {
    type: Array,
    required: true,
  },
});

defineEmits(['undo', 'pause', 'resume']);

const { t } = useI18n();
</script>

<template>
  <div
    v-show="toasts.length > 0"
    role="status"
    aria-live="polite"
    class="absolute bottom-4 left-4 flex flex-col items-start gap-2 pointer-events-none z-30"
    @mouseenter="$emit('pause')"
    @mouseleave="$emit('resume')"
  >
    <div
      v-for="toast in toasts"
      :key="toast.id"
      class="pointer-events-auto flex items-center justify-between gap-3.5 px-4 py-2.5 bg-n-amber-3 dark:bg-n-solid-3 border border-n-amber-6 dark:border-n-amber-7 rounded-xl shadow-lg text-n-amber-12 dark:text-n-amber-11 text-sm min-w-[300px] max-w-md transition-all duration-200"
    >
      <div class="flex items-center gap-2.5 min-w-0 flex-1">
        <Icon
          icon="i-lucide-alert-triangle"
          class="text-n-amber-10 dark:text-n-amber-10 size-4 shrink-0"
        />
        <span class="font-medium truncate" :title="toast.message">
          {{ toast.message }}
        </span>
      </div>
      <button
        type="button"
        class="text-n-amber-11 hover:text-n-amber-12 dark:text-n-amber-10 dark:hover:text-n-amber-11 underline font-semibold text-sm cursor-pointer whitespace-nowrap focus:outline-none focus-visible:ring-2 focus-visible:ring-n-amber-8 rounded px-1 flex-shrink-0"
        @click="$emit('undo', toast.id)"
      >
        {{ t('OPPORTUNITIES.UNDO.ACTION') }}
      </button>
    </div>
  </div>
</template>
