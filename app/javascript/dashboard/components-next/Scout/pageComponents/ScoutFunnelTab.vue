<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';

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
const selectedAttributeIds = ref(
  (props.scout.required_custom_attribute_definitions || []).map(a =>
    Number(a.id)
  )
);

const isSaving = ref(false);
const saveSuccess = ref(false);
const errorMessage = ref('');

const pipelineStages = computed(
  () => store.getters['pipelineStages/stagesSortedByPosition'] || []
);
const teams = computed(() => store.getters['teams/getTeams'] || []);
const customAttributes = computed(
  () => store.getters['attributes/getAttributes'] || []
);

const qualificationAttributes = computed(() => {
  return customAttributes.value.filter(
    attr =>
      attr.attribute_model === 'contact_attribute' ||
      attr.attribute_model === 'opportunity_attribute'
  );
});

const stageOptions = computed(() => [
  { value: '', label: t('SCOUT.FUNNEL.NONE_SELECTED') },
  ...pipelineStages.value.map(s => ({ value: s.id, label: s.name })),
]);

const teamOptions = computed(() => [
  { value: '', label: t('SCOUT.FUNNEL.NO_TEAM_SELECTED') },
  ...teams.value.map(tm => ({ value: tm.id, label: tm.name })),
]);

watch(
  () => props.scout,
  newVal => {
    if (!newVal) return;
    defaultStageId.value = newVal.default_pipeline_stage_id ?? '';
    qualifiedStageId.value = newVal.qualified_stage_id ?? '';
    unqualifiedStageId.value = newVal.unqualified_stage_id ?? '';
    handoverTeamId.value = newVal.handover_team_id ?? '';
    selectedAttributeIds.value = (
      newVal.required_custom_attribute_definitions || []
    ).map(a => Number(a.id));
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

const handleSave = async () => {
  isSaving.value = true;
  saveSuccess.value = false;
  errorMessage.value = '';
  try {
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
      required_custom_attribute_definition_ids: [...selectedAttributeIds.value],
    };

    const { data } = await ScoutAPI.update(props.scout.id, payload);
    saveSuccess.value = true;
    if (data?.required_custom_attribute_definitions) {
      selectedAttributeIds.value =
        data.required_custom_attribute_definitions.map(a => Number(a.id));
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
  await Promise.all([
    store.dispatch('pipelineStages/fetch'),
    store.dispatch('teams/get'),
    store.dispatch('attributes/get'),
  ]);
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
            `${attr.attribute_display_name} (${attr.attribute_model === 'contact_attribute' ? 'Contact' : 'Opportunity'})`
          }}
        </button>
      </div>

      <p v-else class="text-xs text-n-slate-10 mt-2">
        {{ t('SCOUT.FUNNEL.NO_ATTRIBUTES_AVAILABLE') }}
      </p>
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
