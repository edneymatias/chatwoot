<script setup>
import { computed, ref } from 'vue';

const props = defineProps({
  points: {
    type: Array,
    default: () => [],
  },
  valueLabel: {
    type: String,
    default: '',
  },
  horizontal: {
    type: Boolean,
    default: false,
  },
});

// T008: Clamp percentage defensively to [0, 100]
function clampPct(pct) {
  return Math.max(0, Math.min(100, pct ?? 0));
}

// ─── Vertical geometry (original) ──────────────────────────────────────────
const SVG_WIDTH = 600;
const BAND_HEIGHT = 60;
const MIN_WIDTH_RATIO = 0.08;
const CURVE_CONTROL_V = 0.4;

const verticalBands = computed(() => {
  if (!props.points || props.points.length === 0) return [];

  const firstPct = clampPct(props.points[0].percentage);
  const scale = firstPct > 0 ? firstPct : 100;

  return props.points.map((point, i) => {
    const pct = clampPct(point.percentage);
    const endWidthRatio = Math.max(MIN_WIDTH_RATIO, pct / scale);
    const endWidth = endWidthRatio * SVG_WIDTH;

    let startWidth;
    if (i === 0) {
      startWidth = SVG_WIDTH;
    } else {
      const prevPct = clampPct(props.points[i - 1].percentage);
      const prevWidthRatio = Math.max(MIN_WIDTH_RATIO, prevPct / scale);
      startWidth = prevWidthRatio * SVG_WIDTH;
    }

    const y = i * BAND_HEIGHT;
    const cx = SVG_WIDTH / 2;
    const startLeft = cx - startWidth / 2;
    const startRight = cx + startWidth / 2;
    const endLeft = cx - endWidth / 2;
    const endRight = cx + endWidth / 2;
    const cp = BAND_HEIGHT * CURVE_CONTROL_V;

    const path = [
      `M ${startLeft} ${y}`,
      `L ${startRight} ${y}`,
      `C ${startRight} ${y + cp}, ${endRight} ${y + BAND_HEIGHT - cp}, ${endRight} ${y + BAND_HEIGHT}`,
      `L ${endLeft} ${y + BAND_HEIGHT}`,
      `C ${endLeft} ${y + BAND_HEIGHT - cp}, ${startLeft} ${y + cp}, ${startLeft} ${y}`,
      'Z',
    ].join(' ');

    return {
      path,
      fill: point.color,
      label: point.label,
      percentage: pct,
      count: point.count,
      cx,
      cy: y + BAND_HEIGHT / 2,
      bandWidth: (startWidth + endWidth) / 2,
      y,
    };
  });
});

const svgHeightV = computed(() =>
  Math.max(BAND_HEIGHT, props.points.length * BAND_HEIGHT)
);

// ─── Horizontal geometry ────────────────────────────────────────────────────
// Each band occupies an equal horizontal slice; height tapers proportionally.
const SVG_H_WIDTH = 1000; // viewBox width for horizontal mode
const SVG_H_HEIGHT = 200; // viewBox height for horizontal mode
const MIN_HEIGHT_RATIO = 0.08;
const CURVE_CONTROL_H = 0.4; // Bézier cp offset as fraction of band width

const horizontalBands = computed(() => {
  if (!props.points || props.points.length === 0) return [];

  const n = props.points.length;
  const bandWidth = SVG_H_WIDTH / n;
  const cy = SVG_H_HEIGHT / 2;

  const firstPct = clampPct(props.points[0].percentage);
  const scale = firstPct > 0 ? firstPct : 100;

  return props.points.map((point, i) => {
    const pct = clampPct(point.percentage);
    const endHeightRatio = Math.max(MIN_HEIGHT_RATIO, pct / scale);
    const endHalfH = (endHeightRatio * SVG_H_HEIGHT) / 2;

    let startHalfH;
    if (i === 0) {
      startHalfH = SVG_H_HEIGHT / 2;
    } else {
      const prevPct = clampPct(props.points[i - 1].percentage);
      const prevRatio = Math.max(MIN_HEIGHT_RATIO, prevPct / scale);
      startHalfH = (prevRatio * SVG_H_HEIGHT) / 2;
    }

    const x = i * bandWidth;
    const cp = bandWidth * CURVE_CONTROL_H;

    // Path flows: top-left → (curve) → top-right → bottom-right → (curve) → bottom-left → close
    const path = [
      `M ${x} ${cy - startHalfH}`,
      `C ${x + cp} ${cy - startHalfH}, ${x + bandWidth - cp} ${cy - endHalfH}, ${x + bandWidth} ${cy - endHalfH}`,
      `L ${x + bandWidth} ${cy + endHalfH}`,
      `C ${x + bandWidth - cp} ${cy + endHalfH}, ${x + cp} ${cy + startHalfH}, ${x} ${cy + startHalfH}`,
      'Z',
    ].join(' ');

    const bandCx = x + bandWidth / 2;
    const avgHalfH = (startHalfH + endHalfH) / 2;

    return {
      path,
      fill: point.color,
      label: point.label,
      percentage: pct,
      count: point.count,
      cx: bandCx,
      cy,
      // Whether the band is tall enough to show inline labels (threshold: ~40px half-height in viewBox)
      labelVisible: avgHalfH >= 40,
      bandWidth,
    };
  });
});

// ─── Shared ─────────────────────────────────────────────────────────────────
const bands = computed(() =>
  props.horizontal ? horizontalBands.value : verticalBands.value
);

const MIN_LABEL_WIDTH = 120;

const hoveredIndex = ref(null);

function onMouseEnter(index) {
  hoveredIndex.value = index;
}

function onMouseLeave() {
  hoveredIndex.value = null;
}
</script>

<template>
  <!-- Empty container — no bands, no error (T007) -->
  <div class="relative w-full h-full">
    <svg
      v-if="points.length > 0"
      :viewBox="
        horizontal
          ? `0 0 ${SVG_H_WIDTH} ${SVG_H_HEIGHT}`
          : `0 0 ${SVG_WIDTH} ${svgHeightV}`
      "
      class="w-full h-full"
      preserveAspectRatio="xMidYMid meet"
      :aria-label="valueLabel || undefined"
      :role="valueLabel ? 'img' : undefined"
    >
      <g
        v-for="(band, index) in bands"
        :key="index"
        class="cursor-pointer"
        @mouseenter="onMouseEnter(index)"
        @mouseleave="onMouseLeave"
      >
        <!-- Band path — fill bound to point.color -->
        <path :d="band.path" :fill="band.fill" opacity="0.9" />

        <!-- Inline labels when there is enough space -->
        <g
          v-if="
            horizontal ? band.labelVisible : band.bandWidth >= MIN_LABEL_WIDTH
          "
          :transform="`translate(${band.cx}, ${band.cy})`"
          pointer-events="none"
        >
          <!-- Stage name -->
          <text
            text-anchor="middle"
            dy="-18"
            :font-size="horizontal ? 13 : 11"
            font-weight="600"
            fill="white"
            font-family="Inter, -apple-system, sans-serif"
          >
            {{ band.label }}
          </text>

          <!-- Count -->
          <text
            text-anchor="middle"
            :dy="horizontal ? 0 : 2"
            :font-size="horizontal ? 15 : 13"
            font-weight="700"
            fill="white"
            font-family="Inter, -apple-system, sans-serif"
          >
            {{ band.count?.toLocaleString() }}
          </text>

          <!-- Badge-styled percentage pill -->
          <g :transform="horizontal ? 'translate(0, 22)' : 'translate(0, 16)'">
            <rect
              x="-22"
              y="-10"
              width="44"
              height="18"
              rx="9"
              fill="rgba(0,0,0,0.25)"
            />
            <text
              text-anchor="middle"
              dy="3"
              font-size="10"
              font-weight="600"
              fill="white"
              font-family="Inter, -apple-system, sans-serif"
            >
              {{ band.percentage }}%
            </text>
          </g>
        </g>
      </g>
    </svg>

    <!-- Tooltip (T012) — shown on hover -->
    <div
      v-if="hoveredIndex !== null && bands[hoveredIndex]"
      class="absolute left-1/2 -translate-x-1/2 top-2 z-10 pointer-events-none px-3 py-2 rounded-lg shadow-lg bg-n-solid-3 border border-n-container text-sm text-n-slate-12 whitespace-nowrap"
    >
      <p class="m-0 font-semibold">{{ bands[hoveredIndex].label }}</p>
      <p class="m-0 text-n-slate-11">
        {{ bands[hoveredIndex].count?.toLocaleString() }}
        &nbsp;·&nbsp;
        <span
          class="px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-xs font-medium"
        >
          {{ bands[hoveredIndex].percentage }}%
        </span>
      </p>
    </div>
  </div>
</template>
