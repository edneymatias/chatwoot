<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Popover from 'dashboard/components-next/popover/Popover.vue';

const props = defineProps({
  attribution: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const popoverTitle = computed(() => {
  if (props.attribution.isOrganic) {
    return t(
      'OPPORTUNITIES.CAMPAIGN.POPUP_TITLE_ORGANIC',
      'Organic Publication'
    );
  }
  if (props.attribution.isResolved) {
    return t('OPPORTUNITIES.CAMPAIGN.POPUP_TITLE_PAID', 'Ad Attribution');
  }
  return t('OPPORTUNITIES.CAMPAIGN.POPUP_TITLE_FAILED', 'Attribution Details');
});

const platformName = computed(() => {
  const p = props.attribution.platform;
  if (['ig', 'instagram'].includes(p)) return 'Instagram';
  if (['fb', 'facebook'].includes(p)) return 'Facebook';
  return 'Meta';
});

const hasThumbnail = computed(() => {
  return Boolean(props.attribution.thumbnailUrl);
});
</script>

<template>
  <div class="inline-flex items-center" @click.stop>
    <Popover align="start">
      <button
        type="button"
        class="flex items-center justify-center size-5 rounded hover:bg-n-surface-2 transition-colors cursor-pointer text-n-slate-11 hover:text-n-slate-12 focus:outline-none"
        :title="attribution.label"
      >
        <span class="size-4 shrink-0" :class="[attribution.icon]" />
      </button>

      <template #content>
        <div class="p-3 w-80 max-w-sm flex flex-col gap-2.5 text-xs">
          <!-- Header -->
          <div
            class="flex items-center justify-between border-b border-n-weak pb-2"
          >
            <div class="flex items-center gap-1.5 font-medium text-n-slate-12">
              <span class="size-4" :class="[attribution.icon]" />
              <span>{{ popoverTitle }}</span>
            </div>
            <span
              v-if="attribution.isOrganic"
              class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-brand-3 text-n-brand-11"
            >
              {{ $t('OPPORTUNITIES.CAMPAIGN.ORGANIC_POST', 'Organic') }}
            </span>
            <span
              v-else-if="attribution.isResolved"
              class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-green-3 text-n-green-11"
            >
              {{
                $t(
                  'OPPORTUNITIES.CAMPAIGN.PAID_AD',
                  { platform: platformName },
                  `${platformName} Ads`
                )
              }}
            </span>
            <span
              v-else-if="attribution.isPending"
              class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-amber-3 text-n-amber-11"
            >
              {{ $t('OPPORTUNITIES.CAMPAIGN.PENDING', 'Resolving...') }}
            </span>
          </div>

          <!-- Content Body -->
          <div class="flex gap-2.5 items-start">
            <img
              v-if="hasThumbnail"
              :src="attribution.thumbnailUrl"
              alt="Creative Thumbnail"
              class="size-16 rounded object-cover border border-n-weak shrink-0 bg-n-surface-2"
              loading="lazy"
            />

            <div class="flex-1 min-w-0 flex flex-col gap-1">
              <!-- Organic details -->
              <template v-if="attribution.isOrganic">
                <div
                  v-if="attribution.headline"
                  class="font-medium text-n-slate-12 line-clamp-2"
                >
                  {{ attribution.headline }}
                </div>
                <div
                  v-if="attribution.body"
                  class="text-n-slate-11 line-clamp-3"
                >
                  {{ attribution.body }}
                </div>
              </template>

              <!-- Paid Ad details -->
              <template v-else-if="attribution.isResolved">
                <div v-if="attribution.campaignName" class="flex flex-col">
                  <span
                    class="text-[10px] text-n-slate-10 uppercase tracking-wider"
                  >
                    {{
                      $t('OPPORTUNITIES.CAMPAIGN.CAMPAIGN_LABEL', 'Campaign')
                    }}
                  </span>
                  <span
                    class="font-medium text-n-slate-12 truncate"
                    :title="attribution.campaignName"
                  >
                    {{ attribution.campaignName }}
                  </span>
                </div>
                <div v-if="attribution.adsetName" class="flex flex-col">
                  <span
                    class="text-[10px] text-n-slate-10 uppercase tracking-wider"
                  >
                    {{ $t('OPPORTUNITIES.CAMPAIGN.ADSET_LABEL', 'Ad Set') }}
                  </span>
                  <span
                    class="text-n-slate-11 truncate"
                    :title="attribution.adsetName"
                  >
                    {{ attribution.adsetName }}
                  </span>
                </div>
                <div v-if="attribution.adName" class="flex flex-col">
                  <span
                    class="text-[10px] text-n-slate-10 uppercase tracking-wider"
                  >
                    {{ $t('OPPORTUNITIES.CAMPAIGN.AD_LABEL', 'Ad') }}
                  </span>
                  <span
                    class="text-n-slate-11 truncate"
                    :title="attribution.adName"
                  >
                    {{ attribution.adName }}
                  </span>
                </div>
              </template>

              <!-- Failed or Pending -->
              <template v-else>
                <div class="text-n-slate-11 leading-relaxed">
                  {{ attribution.label }}
                </div>
              </template>
            </div>
          </div>

          <!-- Footer Action -->
          <div
            v-if="attribution.sourceUrl"
            class="pt-1.5 border-t border-n-weak flex justify-end"
          >
            <a
              :href="attribution.sourceUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 text-[11px] text-n-brand-11 hover:underline"
            >
              <span>{{
                $t(
                  'OPPORTUNITIES.CAMPAIGN.VIEW_ORIGIN',
                  { platform: platformName },
                  `View on ${platformName}`
                )
              }}</span>
              <span class="i-lucide-external-link size-3" />
            </a>
          </div>
        </div>
      </template>
    </Popover>
  </div>
</template>
