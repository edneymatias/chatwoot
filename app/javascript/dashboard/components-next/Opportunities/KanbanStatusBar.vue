<script setup>
import { ref, watch } from 'vue';

const props = defineProps({
  isDragging: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['drop', 'hoverState']);

const hoveredZone = ref(null);

watch(hoveredZone, val => {
  emit('hoverState', !!val);
});

const onDrop = status => {
  hoveredZone.value = null;
  emit('drop', status);
};

watch(
  () => props.isDragging,
  newVal => {
    if (!newVal) {
      hoveredZone.value = null;
    }
  }
);
</script>

<template>
  <div
    class="absolute inset-x-0 bottom-0 h-36 z-50 flex items-end justify-center pb-6"
    @dragover.prevent
    @drop.prevent
  >
    <div
      class="flex justify-center gap-4 bg-n-surface-1 p-3 rounded-xl border border-n-weak shadow-lg overflow-hidden"
    >
      <div
        class="w-48 h-16 border-2 border-dashed rounded-lg flex items-center justify-center transition-colors"
        :class="[
          hoveredZone === 'lost'
            ? 'border-n-ruby-8 bg-n-ruby-4 text-n-ruby-11'
            : 'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11',
        ]"
        @dragover.prevent="hoveredZone = 'lost'"
        @dragleave.prevent="hoveredZone = null"
        @drop.prevent="onDrop('lost')"
      >
        <div class="flex items-center gap-2 pointer-events-none">
          <span class="text-sm font-medium transition-colors text-n-ruby-11">
            {{ $t('OPPORTUNITIES.BOARD.STATUS.LOST') }}
          </span>
        </div>
      </div>

      <div
        class="w-48 h-16 border-2 border-dashed rounded-lg flex items-center justify-center transition-colors"
        :class="[
          hoveredZone === 'won'
            ? 'border-n-teal-8 bg-n-teal-4 text-n-teal-11'
            : 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
        ]"
        @dragover.prevent="hoveredZone = 'won'"
        @dragleave.prevent="hoveredZone = null"
        @drop.prevent="onDrop('won')"
      >
        <div class="flex items-center gap-2 pointer-events-none">
          <span class="text-sm font-medium transition-colors text-n-teal-11">
            {{ $t('OPPORTUNITIES.BOARD.STATUS.WON') }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
