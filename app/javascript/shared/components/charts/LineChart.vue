<script setup>
import { computed } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Tooltip,
} from 'chart.js';

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

// LineController is auto-registered by the typed Line import (vue-chartjs v5).
// Legend is intentionally NOT registered, matching BarChart.vue's real no-legend mechanism:
// an unregistered plugin simply never runs in chart.js v4's tree-shakable system.
// CategoryScale/LinearScale/Tooltip may already be registered by BarChart.vue when
// co-mounted; ChartJS.register is idempotent so re-registering is safe.
ChartJS.register(
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Tooltip
);

const fontFamily =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';

const defaultChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: {
    duration: 0,
  },
  datasets: {
    line: {
      borderWidth: 2,
      fill: false,
    },
  },
  scales: {
    x: {
      ticks: {
        fontFamily,
      },
      grid: {
        drawOnChartArea: false,
      },
    },
    y: {
      type: 'linear',
      position: 'left',
      ticks: {
        fontFamily,
        beginAtZero: true,
        stepSize: 1,
      },
      grid: {
        drawOnChartArea: false,
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
  <Line :data="collection" :options="options" />
</template>
