import { computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import {
  getDayDifferenceFromNow,
  dynamicTime,
  shortTimestamp,
} from 'shared/helpers/timeHelper';
import { getContrastingTextColor } from '@chatwoot/utils';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';

export function useOpportunityCardFields(opportunityRef) {
  const store = useStore();
  const { t, locale } = useI18n();

  const statusBadgeClass = computed(() => {
    if (opportunityRef.value.status === 'won')
      return 'bg-n-teal-3 text-n-teal-11';
    if (opportunityRef.value.status === 'lost')
      return 'bg-n-ruby-3 text-n-ruby-11';
    return 'bg-n-slate-3 text-n-slate-11';
  });

  const currentStage = computed(() =>
    store.getters['pipelineStages/stageById'](
      opportunityRef.value.pipeline_stage_id
    )
  );

  const isStale = computed(() => {
    if (
      !currentStage.value?.stale_after_days ||
      !opportunityRef.value.current_stage_entered_at
    ) {
      return false;
    }
    return (
      getDayDifferenceFromNow(
        new Date(),
        opportunityRef.value.current_stage_entered_at
      ) > currentStage.value.stale_after_days
    );
  });

  const pipelineCurrency = computed(
    () => store.getters['pipelineCurrencySetting/getCurrency']
  );
  const cardFieldConfigs = computed(
    () => store.getters['pipelineCardFieldConfigs/getRecords'] || []
  );

  const configuredFields = computed(() => {
    const fields = [];
    const attrs = opportunityRef.value.custom_attributes || {};

    cardFieldConfigs.value.forEach(config => {
      if (config.field_type === 'deal_value') {
        const rawValue = opportunityRef.value.value;
        if (rawValue !== null && rawValue !== undefined && rawValue !== '') {
          fields.push({
            id: config.id,
            color: config.color,
            textColor: getContrastingTextColor(config.color),
            value: formatCurrencyAmount(
              rawValue,
              pipelineCurrency.value,
              true // compact mode
            ),
            label: t('OPPORTUNITIES.DEAL_VALUE'),
          });
        }
      } else if (config.field_type === 'custom_attribute') {
        const defId = config.custom_attribute_definition_id;
        const def = store.getters['attributes/getAttributesByModel'](
          'opportunity_attribute'
        ).find(d => d.id === defId);
        if (def) {
          const rawValue = attrs[def.attribute_key];
          if (rawValue !== null && rawValue !== undefined && rawValue !== '') {
            let formattedValue = rawValue;
            if (def.attribute_display_type === 'currency') {
              formattedValue = formatCurrencyAmount(
                rawValue,
                pipelineCurrency.value,
                true // compact mode
              );
            } else if (def.attribute_display_type === 'date') {
              try {
                const dateObj = new Date(rawValue);
                // vue-i18n locale might be pt_BR, replace with pt-BR for Intl
                const localeCode = locale.value
                  ? locale.value.replace('_', '-')
                  : 'en-US';
                formattedValue = dateObj.toLocaleDateString(localeCode, {
                  month: 'numeric',
                  day: 'numeric',
                });
              } catch (e) {
                formattedValue = String(rawValue);
              }
            }
            fields.push({
              id: config.id,
              color: config.color,
              textColor: getContrastingTextColor(config.color),
              value: formattedValue,
              label: def.attribute_display_name,
            });
          }
        }
      }
    });
    return fields;
  });

  const createdTime = computed(() =>
    shortTimestamp(dynamicTime(opportunityRef.value.created_at))
  );
  const stageTime = computed(() =>
    opportunityRef.value.current_stage_entered_at
      ? shortTimestamp(
          dynamicTime(opportunityRef.value.current_stage_entered_at)
        )
      : null
  );

  const timestampLabel = computed(() =>
    stageTime.value
      ? `${createdTime.value} • ${stageTime.value}`
      : createdTime.value
  );

  const localizedDate = timestamp => {
    // vue-i18n locale might be pt_BR, replace with pt-BR for Intl
    const localeCode = locale.value ? locale.value.replace('_', '-') : 'en-US';
    return new Date(timestamp * 1000).toLocaleDateString(localeCode, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  };

  const timestampTooltip = computed(() => {
    const lines = [
      t('OPPORTUNITIES.BOARD.CREATED_TOOLTIP', {
        date: localizedDate(opportunityRef.value.created_at),
      }),
    ];
    if (opportunityRef.value.current_stage_entered_at) {
      lines.push(
        `${t('OPPORTUNITIES.BOARD.TIME_IN_STAGE')}: ${localizedDate(
          opportunityRef.value.current_stage_entered_at
        )}`
      );
    }
    return lines.join(' • ');
  });

  const campaignAttribution = computed(() => {
    const {
      campaign_source_id,
      campaign_platform,
      campaign_name,
      campaign_adset_name,
      campaign_ad_name,
      campaign_resolution_status,
    } = opportunityRef.value;

    if (!campaign_source_id) return null;

    let icon = 'i-lucide-megaphone';
    if (['ig', 'instagram'].includes(campaign_platform))
      icon = 'i-lucide-instagram';
    else if (['fb', 'facebook'].includes(campaign_platform))
      icon = 'i-lucide-facebook';

    let label = '';
    if (campaign_resolution_status === 'resolved') {
      label = [campaign_name, campaign_adset_name, campaign_ad_name]
        .filter(Boolean)
        .join(' > ');
    } else if (campaign_resolution_status === 'failed') {
      label = campaign_source_id;
    } else {
      label = t('OPPORTUNITIES.CAMPAIGN.PENDING', 'Resolving attribution...');
    }

    return { icon, label };
  });

  return {
    statusBadgeClass,
    isStale,
    pipelineCurrency,
    cardFieldConfigs,
    configuredFields,
    createdTime,
    timestampLabel,
    timestampTooltip,
    campaignAttribution,
  };
}
