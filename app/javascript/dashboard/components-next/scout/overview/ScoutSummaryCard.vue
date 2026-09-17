<script setup>
import { computed } from 'vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  value: {
    type: [Number, String],
    default: null,
  },
  unit: {
    type: String,
    default: '',
  },
  tooltip: {
    type: String,
    default: '',
  },
});

const displayValue = computed(() => {
  if (props.value === null || props.value === undefined) {
    return '—';
  }
  return `${props.value}${props.unit}`;
});
</script>

<template>
  <div
    class="flex flex-col p-4 rounded-xl border border-n-weak dark:border-n-weak bg-n-solid-2 dark:bg-n-solid-3 shadow-sm"
  >
    <span
      class="text-xs font-medium text-n-slate-11 dark:text-n-slate-11 truncate"
      :title="tooltip || label"
    >
      {{ label }}
    </span>
    <span
      class="mt-2 text-2xl font-semibold text-n-slate-12 dark:text-n-slate-12 tracking-tight"
    >
      {{ displayValue }}
    </span>
  </div>
</template>
