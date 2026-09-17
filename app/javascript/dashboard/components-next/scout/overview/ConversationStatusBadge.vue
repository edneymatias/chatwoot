<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  status: {
    type: String,
    required: true,
  },
});

const { t } = useI18n();

const STATUS_CONFIG = {
  qualified: {
    classes: 'bg-n-teal-3 text-n-teal-11 dark:bg-n-teal-3 dark:text-n-teal-11',
    i18nKey: 'SCOUT.OVERVIEW.RECENT_CONVERSATIONS.STATUS_BADGES.QUALIFIED',
  },
  disqualified: {
    classes: 'bg-n-ruby-3 text-n-ruby-11 dark:bg-n-ruby-3 dark:text-n-ruby-11',
    i18nKey: 'SCOUT.OVERVIEW.RECENT_CONVERSATIONS.STATUS_BADGES.DISQUALIFIED',
  },
  abandoned: {
    classes:
      'bg-n-amber-3 text-n-amber-11 dark:bg-n-amber-3 dark:text-n-amber-11',
    i18nKey: 'SCOUT.OVERVIEW.RECENT_CONVERSATIONS.STATUS_BADGES.ABANDONED',
  },
  in_progress: {
    classes: 'bg-n-blue-3 text-n-blue-11 dark:bg-n-blue-3 dark:text-n-blue-11',
    i18nKey: 'SCOUT.OVERVIEW.RECENT_CONVERSATIONS.STATUS_BADGES.IN_PROGRESS',
  },
  transferred_without_opportunity: {
    classes:
      'bg-n-slate-3 text-n-slate-11 dark:bg-n-slate-4 dark:text-n-slate-11',
    i18nKey:
      'SCOUT.OVERVIEW.RECENT_CONVERSATIONS.STATUS_BADGES.TRANSFERRED_WITHOUT_OPPORTUNITY',
  },
};

const badgeClass = computed(
  () =>
    STATUS_CONFIG[props.status]?.classes ||
    STATUS_CONFIG.transferred_without_opportunity.classes
);

const label = computed(() => {
  const config = STATUS_CONFIG[props.status];
  return config ? t(config.i18nKey) : props.status;
});
</script>

<template>
  <span
    data-testid="conversation-status-badge"
    class="inline-flex items-center h-6 px-2 rounded-md text-xs font-medium whitespace-nowrap"
    :class="badgeClass"
  >
    {{ label }}
  </span>
</template>
