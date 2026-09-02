import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useOperators } from './operators';
import { useMapGetter } from 'dashboard/composables/store.js';
import { buildAttributesFilterTypes } from './helper/filterHelper';

export function useOpportunityFilterContext() {
  const { t } = useI18n();

  const opportunityAttributes = useMapGetter(
    'attributes/getOpportunityAttributes'
  );

  const agents = useMapGetter('agents/getAgents');
  const stages = useMapGetter('pipelineStages/stagesSortedByPosition');

  const {
    equalityOperators,
    presenceOperators,
    containmentOperators,
    dateOperators,
    getOperatorTypes,
  } = useOperators();

  const customFilterTypes = computed(() => {
    const attrs = opportunityAttributes.value || [];
    return buildAttributesFilterTypes(attrs, getOperatorTypes, 'opportunity');
  });

  const filterTypes = computed(() => [
    {
      attributeKey: 'status',
      value: 'status',
      attributeName: t('FILTER.ATTRIBUTES.STATUS'),
      label: t('FILTER.ATTRIBUTES.STATUS'),
      inputType: 'multiSelect',
      options: ['open', 'won', 'lost'].map(id => {
        return {
          id,
          // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
          name: t(`OPPORTUNITIES.BOARD.STATUS.${id.toUpperCase()}`),
        };
      }),
      dataType: 'text',
      filterOperators: equalityOperators.value,
      attributeModel: 'standard',
    },
    {
      attributeKey: 'assignee_id',
      value: 'assignee_id',
      attributeName: t('FILTER.ATTRIBUTES.ASSIGNEE_NAME'),
      label: t('FILTER.ATTRIBUTES.ASSIGNEE_NAME'),
      inputType: 'searchSelect',
      options: agents.value.map(agent => {
        return {
          id: agent.id,
          name: agent.name,
        };
      }),
      dataType: 'text',
      filterOperators: presenceOperators.value,
      attributeModel: 'standard',
    },
    {
      attributeKey: 'pipeline_stage_id',
      value: 'pipeline_stage_id',
      attributeName: 'Stage', // Fallback until we have a translation key
      label: 'Stage',
      inputType: 'searchSelect',
      options: stages.value.map(stage => {
        return {
          id: stage.id,
          name: stage.name,
        };
      }),
      dataType: 'text',
      filterOperators: equalityOperators.value,
      attributeModel: 'standard',
    },
    {
      attributeKey: 'campaign_name',
      value: 'campaign_name',
      attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_NAME'),
      label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_NAME'),
      inputType: 'plainText',
      dataType: 'text',
      filterOperators: containmentOperators.value,
      attributeModel: 'standard',
    },
    {
      attributeKey: 'campaign_adset_name',
      value: 'campaign_adset_name',
      attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_ADSET_NAME'),
      label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_ADSET_NAME'),
      inputType: 'plainText',
      dataType: 'text',
      filterOperators: containmentOperators.value,
      attributeModel: 'standard',
    },
    {
      attributeKey: 'campaign_ad_name',
      value: 'campaign_ad_name',
      attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_AD_NAME'),
      label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_AD_NAME'),
      inputType: 'plainText',
      dataType: 'text',
      filterOperators: containmentOperators.value,
      attributeModel: 'standard',
    },
    {
      attributeKey: 'campaign_platform',
      value: 'campaign_platform',
      attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_PLATFORM'),
      label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_PLATFORM'),
      inputType: 'multiSelect',
      options: [
        { id: 'facebook', name: 'Facebook' },
        { id: 'instagram', name: 'Instagram' },
        {
          id: 'none',
          name: t('FILTER.ATTRIBUTES.OPPORTUNITY_CAMPAIGN_PLATFORM_NONE'),
        },
      ],
      dataType: 'text',
      filterOperators: equalityOperators.value,
      attributeModel: 'standard',
    },
    {
      attributeKey: 'created_at',
      value: 'created_at',
      attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_CREATED_AT'),
      label: t('FILTER.ATTRIBUTES.OPPORTUNITY_CREATED_AT'),
      inputType: 'date',
      dataType: 'text',
      filterOperators: dateOperators.value,
      attributeModel: 'standard',
    },
    {
      attributeKey: 'updated_at',
      value: 'updated_at',
      attributeName: t('FILTER.ATTRIBUTES.OPPORTUNITY_UPDATED_AT'),
      label: t('FILTER.ATTRIBUTES.OPPORTUNITY_UPDATED_AT'),
      inputType: 'date',
      dataType: 'text',
      filterOperators: dateOperators.value,
      attributeModel: 'standard',
    },
    ...customFilterTypes.value,
  ]);

  return { filterTypes };
}
