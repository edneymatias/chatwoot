<script setup>
import { computed } from 'vue';
import { useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  scouts: {
    type: Array,
    default: () => [],
  },
  modelValue: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['update:modelValue']);

const hasMultipleScouts = computed(() => (props.scouts?.length || 0) > 1);

const [showDropdown, toggleDropdown] = useToggle();

const menuSections = computed(() => {
  const items = props.scouts.map(scout => ({
    value: scout.id,
    label: scout.name,
    action: 'select',
    isSelected: Number(scout.id) === Number(props.modelValue),
  }));
  return [{ items }];
});

const selectedLabel = computed(() => {
  const scout = props.scouts.find(
    s => Number(s.id) === Number(props.modelValue)
  );
  return scout?.name || props.scouts[0]?.name || '';
});

const handleAction = ({ value }) => {
  toggleDropdown(false);
  emit('update:modelValue', value);
};

const onChange = event => {
  const parsed = Number(event.target.value);
  emit('update:modelValue', Number.isNaN(parsed) ? event.target.value : parsed);
};
</script>

<template>
  <div
    v-if="hasMultipleScouts"
    v-on-click-outside="() => toggleDropdown(false)"
    class="relative flex items-center group"
  >
    <Button
      sm
      slate
      faded
      trailing-icon
      icon="i-lucide-chevron-down"
      :label="selectedLabel"
      class="rounded-md group-hover:bg-n-alpha-2"
      @click="toggleDropdown()"
    />
    <DropdownMenu
      v-if="showDropdown"
      :menu-sections="menuSections"
      class="mt-1 ltr:right-0 rtl:left-0 top-full min-w-[140px]"
      @action="handleAction($event)"
    />
    <select
      :value="modelValue"
      class="sr-only"
      tabindex="-1"
      aria-hidden="true"
      @change="onChange"
    >
      <option v-for="scout in scouts" :key="scout.id" :value="scout.id">
        {{ scout.name }}
      </option>
    </select>
  </div>
</template>
