<script setup>
import { ref, watch } from 'vue';
import Draggable from 'vuedraggable';

const props = defineProps({
  isDragging: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['statusChanged']);

const wonList = ref([]);
const lostList = ref([]);
const hoveredZone = ref(null);

const onMoveWon = () => {
  hoveredZone.value = 'won';
  return true; // Allow mutation
};

const onMoveLost = () => {
  hoveredZone.value = 'lost';
  return true; // Allow mutation
};

const onChangeWon = evt => {
  if (evt.added) {
    emit('statusChanged', { id: evt.added.element.id, status: 'won' });
    wonList.value = [];
  }
};

const onChangeLost = evt => {
  if (evt.added) {
    emit('statusChanged', { id: evt.added.element.id, status: 'lost' });
    lostList.value = [];
  }
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
    class="flex justify-center gap-4 bg-n-surface-1 p-3 rounded-xl border border-n-weak shrink-0 mx-auto mb-4"
  >
    <Draggable
      v-model="lostList"
      group="kanban-cards"
      :move="onMoveLost"
      item-key="id"
      class="w-48 h-16 border-2 border-dashed rounded-lg flex items-center justify-center transition-colors"
      :class="[
        hoveredZone === 'lost'
          ? 'border-n-ruby-8 bg-n-ruby-4 text-n-ruby-11'
          : 'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11',
      ]"
      @change="onChangeLost"
    >
      <template #item="{ element }">
        <div
          :key="element.id"
          class="w-0 h-0 opacity-0 overflow-hidden absolute"
        />
      </template>
      <template #header>
        <div class="flex items-center gap-2 pointer-events-none">
          <span class="text-sm font-medium transition-colors text-n-ruby-11">
            {{ $t('OPPORTUNITIES.BOARD.STATUS.LOST') }}
          </span>
        </div>
      </template>
    </Draggable>

    <Draggable
      v-model="wonList"
      group="kanban-cards"
      :move="onMoveWon"
      item-key="id"
      class="w-48 h-16 border-2 border-dashed rounded-lg flex items-center justify-center transition-colors"
      :class="[
        hoveredZone === 'won'
          ? 'border-n-teal-8 bg-n-teal-4 text-n-teal-11'
          : 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
      ]"
      @change="onChangeWon"
    >
      <template #item="{ element }">
        <div
          :key="element.id"
          class="w-0 h-0 opacity-0 overflow-hidden absolute"
        />
      </template>
      <template #header>
        <div class="flex items-center gap-2 pointer-events-none">
          <span class="text-sm font-medium transition-colors text-n-teal-11">
            {{ $t('OPPORTUNITIES.BOARD.STATUS.WON') }}
          </span>
        </div>
      </template>
    </Draggable>
  </div>
</template>
