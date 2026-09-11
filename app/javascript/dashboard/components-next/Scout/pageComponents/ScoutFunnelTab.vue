<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AttributeAPI from 'dashboard/api/attributes';
import ScoutAPI from 'dashboard/api/scout';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  scout: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['updated']);
const { t } = useI18n();
const store = useStore();

const defaultStageId = ref(props.scout.default_pipeline_stage_id ?? '');
const qualifiedStageId = ref(props.scout.qualified_stage_id ?? '');
const unqualifiedStageId = ref(props.scout.unqualified_stage_id ?? '');
const handoverTeamId = ref(props.scout.handover_team_id ?? '');
const defaultCountryCode = ref(props.scout.default_country_code ?? '');
const defaultAreaCode = ref(props.scout.default_area_code ?? '');
const selectedAttributeIds = ref(
  (props.scout.required_custom_attribute_definitions || []).map(a =>
    Number(a.id)
  )
);
const resolveAttributeId = (id, obj) => {
  if (id) return String(id);
  if (obj?.id) return String(obj.id);
  return '';
};

const interestAttributeDefinitionId = ref(
  resolveAttributeId(
    props.scout.interest_attribute_definition_id,
    props.scout.interest_attribute_definition
  )
);
const valueByInterest = ref({ ...(props.scout.value_by_interest || {}) });

const isSaving = ref(false);
const saveSuccess = ref(false);
const errorMessage = ref('');

const rawCustomAttributes = ref([]);

const fetchCustomAttributes = async () => {
  try {
    const accountId =
      props.scout?.account_id ||
      (typeof window !== 'undefined' && window.location?.pathname
        ? window.location.pathname.split('/')[3]
        : undefined);
    const res = await AttributeAPI.getAttributesByModel(accountId);
    if (Array.isArray(res?.data) && res.data.length > 0) {
      rawCustomAttributes.value = res.data;
    }
  } catch (error) {
    // Ignore error
  }
};

const pipelineStages = useMapGetter('pipelineStages/stagesSortedByPosition');
const teams = useMapGetter('teams/getTeams');
const storeCustomAttributes = useMapGetter('attributes/getAttributes');

const getAttrModel = attr => attr.attribute_model ?? attr.attributeModel;
const getAttrType = attr =>
  attr.attribute_display_type ?? attr.attributeDisplayType;
const getAttrDisplayName = attr =>
  attr.attribute_display_name ?? attr.attributeDisplayName ?? attr.name ?? '';

const isOpportunityModel = attr => {
  if (!attr) return false;
  const model = getAttrModel(attr);
  return model === 'opportunity_attribute' || model === 3 || model === '3';
};

const isListType = attr => {
  if (!attr) return false;
  const type = getAttrType(attr);
  return type === 'list' || type === 6 || type === '6';
};

const allCustomAttributes = computed(() => {
  const map = new Map();
  const addAttr = attr => {
    if (attr && attr.id != null && !map.has(Number(attr.id))) {
      map.set(Number(attr.id), attr);
    }
  };

  (rawCustomAttributes.value || []).forEach(addAttr);
  (storeCustomAttributes.value || []).forEach(addAttr);
  (props.scout?.required_custom_attribute_definitions || []).forEach(addAttr);
  if (props.scout?.interest_attribute_definition) {
    addAttr(props.scout.interest_attribute_definition);
  }

  return Array.from(map.values());
});

const qualificationAttributes = computed(() => {
  return allCustomAttributes.value.filter(attr => {
    const model = getAttrModel(attr);
    return (
      model === 'contact_attribute' ||
      model === 'opportunity_attribute' ||
      model === 1 ||
      model === 3 ||
      model === '1' ||
      model === '3'
    );
  });
});

const listOpportunityAttributes = computed(() => {
  return allCustomAttributes.value.filter(
    attr => isOpportunityModel(attr) && isListType(attr)
  );
});

const selectedInterestAttribute = computed(() => {
  if (!interestAttributeDefinitionId.value) return null;
  const targetId = Number(interestAttributeDefinitionId.value);
  if (!targetId) return null;

  const foundInList = listOpportunityAttributes.value.find(
    attr => Number(attr.id) === targetId
  );
  if (
    foundInList &&
    (foundInList.attribute_values || foundInList.attributeValues)
  ) {
    return foundInList;
  }

  const foundInAll = allCustomAttributes.value.find(
    attr => Number(attr.id) === targetId
  );
  if (
    foundInAll &&
    (foundInAll.attribute_values || foundInAll.attributeValues)
  ) {
    return foundInAll;
  }

  const scoutAttr = props.scout?.interest_attribute_definition;
  if (scoutAttr && Number(scoutAttr.id) === targetId) {
    return scoutAttr;
  }

  return foundInList || foundInAll || null;
});

const interestOptions = computed(() => {
  if (!selectedInterestAttribute.value) return [];
  const rawVals =
    selectedInterestAttribute.value.attribute_values ??
    selectedInterestAttribute.value.attributeValues ??
    [];
  return Array.isArray(rawVals) ? rawVals : [];
});

const stageOptions = computed(() => [
  { value: '', label: t('SCOUT.FUNNEL.NONE_SELECTED') },
  ...(pipelineStages.value || []).map(s => ({ value: s.id, label: s.name })),
]);

const teamOptions = computed(() => [
  { value: '', label: t('SCOUT.FUNNEL.NO_TEAM_SELECTED') },
  ...(teams.value || []).map(tm => ({ value: tm.id, label: tm.name })),
]);

watch(
  () => props.scout,
  newVal => {
    if (!newVal) return;
    defaultStageId.value = newVal.default_pipeline_stage_id ?? '';
    qualifiedStageId.value = newVal.qualified_stage_id ?? '';
    unqualifiedStageId.value = newVal.unqualified_stage_id ?? '';
    handoverTeamId.value = newVal.handover_team_id ?? '';
    defaultCountryCode.value = newVal.default_country_code ?? '';
    defaultAreaCode.value = newVal.default_area_code ?? '';
    selectedAttributeIds.value = (
      newVal.required_custom_attribute_definitions || []
    ).map(a => Number(a.id));
    interestAttributeDefinitionId.value = resolveAttributeId(
      newVal.interest_attribute_definition_id,
      newVal.interest_attribute_definition
    );
    valueByInterest.value = { ...(newVal.value_by_interest || {}) };
  },
  { deep: true }
);

const isAttributeSelected = id =>
  selectedAttributeIds.value.includes(Number(id));

const toggleAttribute = id => {
  const numId = Number(id);
  const index = selectedAttributeIds.value.indexOf(numId);
  if (index >= 0) {
    selectedAttributeIds.value = selectedAttributeIds.value.filter(
      item => item !== numId
    );
  } else {
    selectedAttributeIds.value = [...selectedAttributeIds.value, numId];
  }
};

const updateOptionValue = (option, val) => {
  const trimmed = typeof val === 'string' ? val.trim() : val;
  if (trimmed === '' || trimmed === null || trimmed === undefined) {
    const updated = { ...valueByInterest.value };
    delete updated[option];
    valueByInterest.value = updated;
  } else {
    const num = Number(trimmed);
    valueByInterest.value = {
      ...valueByInterest.value,
      [option]: Number.isNaN(num) ? trimmed : num,
    };
  }
};

const handleSave = async () => {
  isSaving.value = true;
  saveSuccess.value = false;
  errorMessage.value = '';
  try {
    const cleanedValueByInterest = {};
    Object.entries(valueByInterest.value).forEach(([k, v]) => {
      if (v !== '' && v !== null && v !== undefined) {
        const num = Number(v);
        cleanedValueByInterest[k] = Number.isNaN(num) ? v : num;
      }
    });

    const payload = {
      default_pipeline_stage_id: defaultStageId.value
        ? Number(defaultStageId.value)
        : null,
      qualified_stage_id: qualifiedStageId.value
        ? Number(qualifiedStageId.value)
        : null,
      unqualified_stage_id: unqualifiedStageId.value
        ? Number(unqualifiedStageId.value)
        : null,
      handover_team_id: handoverTeamId.value
        ? Number(handoverTeamId.value)
        : null,
      default_country_code: defaultCountryCode.value || null,
      default_area_code: defaultAreaCode.value || null,
      required_custom_attribute_definition_ids: [...selectedAttributeIds.value],
      interest_attribute_definition_id: interestAttributeDefinitionId.value
        ? Number(interestAttributeDefinitionId.value)
        : null,
      value_by_interest: interestAttributeDefinitionId.value
        ? cleanedValueByInterest
        : {},
    };

    const { data } = await ScoutAPI.update(props.scout.id, payload);
    saveSuccess.value = true;
    if (data?.required_custom_attribute_definitions) {
      selectedAttributeIds.value =
        data.required_custom_attribute_definitions.map(a => Number(a.id));
    }
    if (data && 'interest_attribute_definition_id' in data) {
      interestAttributeDefinitionId.value = resolveAttributeId(
        data.interest_attribute_definition_id,
        data.interest_attribute_definition
      );
    }
    if (data?.value_by_interest) {
      valueByInterest.value = { ...data.value_by_interest };
    }
    emit('updated', data);
    setTimeout(() => {
      saveSuccess.value = false;
    }, 3000);
  } catch (error) {
    errorMessage.value =
      error.response?.data?.error ||
      error.message ||
      t('SCOUT.ACCOUNT_SETTINGS.SAVE_ERROR');
  } finally {
    isSaving.value = false;
  }
};

onMounted(async () => {
  fetchCustomAttributes();
  await Promise.all([
    store.dispatch('pipelineStages/fetch'),
    store.dispatch('teams/get'),
    store.dispatch('attributes/get', props.scout?.account_id),
  ]);
  if (rawCustomAttributes.value.length === 0) {
    fetchCustomAttributes();
  }
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="pb-4">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('SCOUT.FUNNEL.TITLE') }}
      </h2>
      <p class="text-xs text-n-slate-11 mt-0.5">
        {{ t('SCOUT.FUNNEL.SUBTITLE') }}
      </p>
    </div>

    <!-- Error Banner -->
    <div
      v-if="errorMessage"
      class="p-4 rounded-lg bg-red-500/10 border border-red-500/20 text-red-600 dark:text-red-400 text-xs flex items-center gap-2"
    >
      <span class="i-lucide-alert-triangle size-4 flex-shrink-0" />
      <span>{{ errorMessage }}</span>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <!-- Default / Triage Stage -->
      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ t('SCOUT.FUNNEL.DEFAULT_STAGE_LABEL') }}
        </label>
        <Select
          v-model="defaultStageId"
          class="!w-full [&>select]:w-full"
          :options="stageOptions"
        />
        <span class="text-[11px] text-n-slate-10 mt-1 block">
          {{ t('SCOUT.FUNNEL.DEFAULT_STAGE_HINT') }}
        </span>
      </div>

      <!-- Qualified Stage -->
      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ t('SCOUT.FUNNEL.QUALIFIED_STAGE_LABEL') }}
        </label>
        <Select
          v-model="qualifiedStageId"
          class="!w-full [&>select]:w-full"
          :options="stageOptions"
        />
        <span class="text-[11px] text-n-slate-10 mt-1 block">
          {{ t('SCOUT.FUNNEL.QUALIFIED_STAGE_HINT') }}
        </span>
      </div>

      <!-- Unqualified Stage -->
      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ t('SCOUT.FUNNEL.UNQUALIFIED_STAGE_LABEL') }}
        </label>
        <Select
          v-model="unqualifiedStageId"
          class="!w-full [&>select]:w-full"
          :options="stageOptions"
        />
        <span class="text-[11px] text-n-slate-10 mt-1 block">
          {{ t('SCOUT.FUNNEL.UNQUALIFIED_STAGE_HINT') }}
        </span>
      </div>
    </div>

    <!-- Handover Team -->
    <div class="pt-2">
      <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
        {{ t('SCOUT.FUNNEL.HANDOVER_TEAM_LABEL') }}
      </label>
      <Select
        v-model="handoverTeamId"
        class="!w-full max-w-md [&>select]:w-full"
        :options="teamOptions"
      />
      <span class="text-[11px] text-n-slate-10 mt-1 block">
        {{ t('SCOUT.FUNNEL.HANDOVER_TEAM_HINT') }}
      </span>
    </div>

    <!-- Default Phone Locale -->
    <div class="pt-4 border-t border-n-weak">
      <div>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('SCOUT.FUNNEL.PHONE_DEFAULTS_TITLE') }}
        </h3>
        <p class="text-xs text-n-slate-11 mt-0.5">
          {{ t('SCOUT.FUNNEL.PHONE_DEFAULTS_SUBTITLE') }}
        </p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-3">
        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.FUNNEL.COUNTRY_CODE_LABEL') }}
          </label>
          <Input
            v-model="defaultCountryCode"
            :placeholder="t('SCOUT.FUNNEL.COUNTRY_CODE_PLACEHOLDER')"
          />
          <span class="text-[11px] text-n-slate-10 mt-1 block">
            {{ t('SCOUT.FUNNEL.COUNTRY_CODE_HINT') }}
          </span>
        </div>

        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.FUNNEL.AREA_CODE_LABEL') }}
          </label>
          <Input
            v-model="defaultAreaCode"
            :placeholder="t('SCOUT.FUNNEL.AREA_CODE_PLACEHOLDER')"
          />
          <span class="text-[11px] text-n-slate-10 mt-1 block">
            {{ t('SCOUT.FUNNEL.AREA_CODE_HINT') }}
          </span>
        </div>
      </div>
    </div>

    <!-- Required Qualification Custom Attributes -->
    <div class="pt-4 border-t border-n-weak">
      <div>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('SCOUT.FUNNEL.REQUIRED_FIELDS_TITLE') }}
        </h3>
        <p class="text-xs text-n-slate-11 mt-0.5">
          {{ t('SCOUT.FUNNEL.REQUIRED_FIELDS_SUBTITLE') }}
        </p>
      </div>

      <div
        v-if="qualificationAttributes.length > 0"
        class="flex flex-wrap gap-2 mt-3"
      >
        <button
          v-for="attr in qualificationAttributes"
          :key="attr.id"
          type="button"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all"
          :class="
            isAttributeSelected(attr.id)
              ? 'bg-n-brand text-white shadow-sm'
              : 'bg-n-surface-1 border border-n-weak text-n-slate-11 hover:border-n-brand/40'
          "
          @click="toggleAttribute(attr.id)"
        >
          <span
            :class="
              isAttributeSelected(attr.id)
                ? 'i-lucide-check size-3.5'
                : 'i-lucide-plus size-3.5'
            "
          />
          {{
            `${getAttrDisplayName(attr)} (${getAttrModel(attr) === 'contact_attribute' || getAttrModel(attr) === 1 || getAttrModel(attr) === '1' ? 'Contact' : 'Opportunity'})`
          }}
        </button>
      </div>

      <p v-else class="text-xs text-n-slate-10 mt-2">
        {{ t('SCOUT.FUNNEL.NO_ATTRIBUTES_AVAILABLE') }}
      </p>
    </div>

    <!-- Opportunity Value Estimation -->
    <div class="pt-4 border-t border-n-weak">
      <div>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('SCOUT.FUNNEL.VALUE_ESTIMATION_TITLE') }}
        </h3>
        <p class="text-xs text-n-slate-11 mt-0.5">
          {{ t('SCOUT.FUNNEL.VALUE_ESTIMATION_SUBTITLE') }}
        </p>
      </div>

      <div class="mt-3">
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ t('SCOUT.FUNNEL.INTEREST_ATTRIBUTE_LABEL') }}
        </label>

        <!-- Visual chips listing the available list opportunity attributes, matching the section above -->
        <div
          v-if="listOpportunityAttributes.length > 0"
          class="flex flex-wrap gap-2"
        >
          <button
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all"
            :class="
              !interestAttributeDefinitionId
                ? 'bg-n-brand text-white shadow-sm'
                : 'bg-n-surface-1 border border-n-weak text-n-slate-11 hover:border-n-brand/40'
            "
            @click="interestAttributeDefinitionId = ''"
          >
            <span
              v-if="!interestAttributeDefinitionId"
              class="i-lucide-check size-3.5"
            />
            {{ t('SCOUT.FUNNEL.NONE_SELECTED') }}
          </button>

          <button
            v-for="attr in listOpportunityAttributes"
            :key="attr.id"
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all"
            :class="
              Number(interestAttributeDefinitionId) === Number(attr.id)
                ? 'bg-n-brand text-white shadow-sm'
                : 'bg-n-surface-1 border border-n-weak text-n-slate-11 hover:border-n-brand/40'
            "
            @click="interestAttributeDefinitionId = String(attr.id)"
          >
            <span
              v-if="Number(interestAttributeDefinitionId) === Number(attr.id)"
              class="i-lucide-check size-3.5"
            />
            {{ getAttrDisplayName(attr) }}
          </button>
        </div>

        <p v-else class="text-xs text-n-slate-10">
          {{ t('SCOUT.FUNNEL.NO_LIST_ATTRIBUTES_AVAILABLE') }}
        </p>

        <span class="text-[11px] text-n-slate-10 mt-1.5 block">
          {{ t('SCOUT.FUNNEL.INTEREST_ATTRIBUTE_HINT') }}
        </span>
      </div>

      <!-- Values table for selected interest attribute options -->
      <div v-if="selectedInterestAttribute" class="mt-4">
        <h4 class="text-xs font-medium text-n-slate-12">
          {{ t('SCOUT.FUNNEL.VALUE_TABLE_TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-11 mt-0.5 mb-3">
          {{ t('SCOUT.FUNNEL.VALUE_TABLE_SUBTITLE') }}
        </p>

        <div
          v-if="interestOptions.length > 0"
          class="max-w-lg border border-n-weak rounded-lg overflow-hidden divide-y divide-n-weak"
        >
          <div
            class="grid grid-cols-2 bg-n-surface-1 px-3 py-2 text-xs font-medium text-n-slate-11"
          >
            <span>{{ t('SCOUT.FUNNEL.OPTION_HEADER') }}</span>
            <span>{{ t('SCOUT.FUNNEL.VALUE_HEADER') }}</span>
          </div>
          <div
            v-for="option in interestOptions"
            :key="option"
            class="grid grid-cols-2 items-center px-3 py-2 gap-3"
          >
            <span class="text-xs font-medium text-n-slate-12 truncate">{{
              option
            }}</span>
            <div>
              <Input
                type="number"
                :model-value="valueByInterest[option] ?? ''"
                :placeholder="t('SCOUT.FUNNEL.VALUE_PLACEHOLDER')"
                class="w-full"
                @update:model-value="val => updateOptionValue(option, val)"
              />
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="w-full flex justify-end items-center py-4 mt-2">
      <span
        v-if="saveSuccess"
        class="text-xs font-medium text-emerald-600 dark:text-emerald-400 flex items-center gap-1.5 ltr:mr-4 rtl:ml-4"
      >
        <span class="i-lucide-check size-4" />
        {{ t('SCOUT.GENERAL.SAVED_SUCCESS') }}
      </span>
      <Button
        :label="t('SCOUT.GENERAL.SAVE_BUTTON')"
        color="blue"
        :is-loading="isSaving"
        @click="handleSave"
      />
    </div>
  </div>
</template>
