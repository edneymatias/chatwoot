<script setup>
import { computed } from 'vue';
import { Doughnut } from 'vue-chartjs';
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js';

const props = defineProps({
  collection: {
    type: Object,
    default: () => ({}),
  },
  chartOptions: {
    type: Object,
    default: () => ({}),
  },
  clickable: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['elementClick']);

// DoughnutController is auto-registered by the typed Doughnut import (vue-chartjs v5).
// Do NOT add an explicit ChartJS.register(DoughnutController) call.
ChartJS.register(ArcElement, Tooltip, Legend);

const fontFamily =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';

const defaultChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: {
    duration: 0,
  },
  plugins: {
    legend: {
      display: true,
      position: 'bottom',
      labels: {
        fontFamily,
      },
    },
  },
};

const handleClick = (event, elements, chart) => {
  props.chartOptions.onClick?.(event, elements, chart);

  if (!props.clickable || !elements.length) return;

  const { datasetIndex, index } = elements[0];
  const dataset = props.collection.datasets?.[datasetIndex] || {};

  emit('elementClick', {
    datasetIndex,
    dataIndex: index,
    dataset,
    label: props.collection.labels?.[index],
    value: dataset.data?.[index],
  });
};

const handleHover = (event, elements, chart) => {
  props.chartOptions.onHover?.(event, elements, chart);

  if (!event?.native?.target) return;

  event.native.target.style.cursor =
    props.clickable && elements.length ? 'pointer' : 'default';
};

const options = computed(() => {
  return {
    ...defaultChartOptions,
    ...props.chartOptions,
    onClick: handleClick,
    onHover: handleHover,
  };
});
</script>

<template>
  <Doughnut :data="collection" :options="options" />
</template>
