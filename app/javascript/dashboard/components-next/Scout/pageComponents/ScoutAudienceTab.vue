<script setup>
import { ref, watch, onMounted, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import ScoutAPI from 'dashboard/api/scout';
import Button from 'dashboard/components-next/button/Button.vue';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import { useContactFilterContext } from 'dashboard/components-next/filter/contactProvider.js';

const props = defineProps({
  scout: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['updated']);
const { t } = useI18n();
const store = useStore();
const { filterTypes, attributeFilterTypes } = useContactFilterContext();
const conditionsRef = useTemplateRef('conditionsRef');
const filters = ref([]);
const isSaving = ref(false);
const saveSuccess = ref(false);
const errorMessage = ref('');

const DEFAULT_FILTER = {
  attributeKey: 'phone_number',
  filterOperator: 'equal_to',
  values: '',
  queryOperator: 'and',
};

const findOption = (filterType, value) =>
  filterType?.options?.find(option => String(option.id) === String(value));

const hydrateValues = (item, filterType) => {
  const raw = Array.isArray(item.values) ? item.values : [item.values];
  const inputType = filterType?.inputType;

  if (inputType === 'multiSelect') {
    return raw
      .filter(
        v =>
          v !== null &&
          v !== undefined &&
          v !== '' &&
          String(v) !== '[object Object]'
      )
      .map(
        value => findOption(filterType, value) ?? { id: value, name: value }
      );
  }

  if (['searchSelect', 'booleanSelect'].includes(inputType)) {
    const val = raw[0];
    if (
      val === null ||
      val === undefined ||
      val === '' ||
      String(val) === '[object Object]'
    ) {
      return {};
    }
    return findOption(filterType, val) ?? { id: val, name: val };
  }

  if (inputType === 'multiText') {
    return raw.filter(
      v =>
        v !== null &&
        v !== undefined &&
        v !== '' &&
        String(v) !== '[object Object]'
    );
  }

  const first = raw[0];
  if (first == null || String(first) === '[object Object]') return '';
  return String(first);
};

const serializeValues = values => {
  if (Array.isArray(values)) {
    return values
      .map(item =>
        item && typeof item === 'object' && item.id !== undefined
          ? item.id
          : item
      )
      .filter(
        v =>
          v !== '' &&
          v !== null &&
          v !== undefined &&
          String(v) !== '[object Object]'
      )
      .map(String);
  }

  if (values && typeof values === 'object') {
    if (
      values.id !== undefined &&
      values.id !== null &&
      values.id !== '' &&
      String(values.id) !== '[object Object]'
    ) {
      return [String(values.id)];
    }
    return [];
  }

  if (
    values === '' ||
    values === null ||
    values === undefined ||
    String(values) === '[object Object]'
  ) {
    return [];
  }

  return [String(values)];
};

const initializeFilters = () => {
  if (Array.isArray(props.scout?.audience) && props.scout.audience.length > 0) {
    filters.value = props.scout.audience.map((item, index) => {
      const filterType = filterTypes.value?.find(
        type => type.attributeKey === item.attribute_key
      );

      return {
        id: index + 1,
        attributeKey: item.attribute_key,
        filterOperator: item.filter_operator,
        values: hydrateValues(item, filterType),
        queryOperator: item.query_operator || 'and',
      };
    });
  } else {
    filters.value = [];
  }
};

onMounted(() => {
  if (store?.dispatch) {
    store.dispatch('labels/get');
  }
});

watch(
  () => props.scout,
  () => {
    initializeFilters();
  },
  { immediate: true, deep: true }
);

const addCondition = () => {
  filters.value.push({
    ...DEFAULT_FILTER,
    id: Date.now(),
  });
};

const removeCondition = index => {
  filters.value.splice(index, 1);
};

const isConditionsValid = () => {
  if (!conditionsRef.value || conditionsRef.value.length === 0) return true;
  return conditionsRef.value.every(condition => {
    return typeof condition.validate === 'function'
      ? condition.validate()
      : true;
  });
};

const clearAudience = async () => {
  isSaving.value = true;
  errorMessage.value = '';
  try {
    const { data } = await ScoutAPI.update(props.scout.id, {
      scout: {
        audience: [],
      },
    });
    filters.value = [];
    saveSuccess.value = true;
    emit('updated', data);
    setTimeout(() => {
      saveSuccess.value = false;
    }, 3000);
  } catch (error) {
    errorMessage.value =
      error.response?.data?.error ||
      error.message ||
      t('SCOUT.AUDIENCE.ERROR_MESSAGE');
  } finally {
    isSaving.value = false;
  }
};

const saveAudience = async () => {
  if (!isConditionsValid()) return;

  isSaving.value = true;
  errorMessage.value = '';
  saveSuccess.value = false;

  try {
    const audiencePayload = filters.value.map((filter, index) => {
      return {
        attribute_key: filter.attributeKey,
        filter_operator: filter.filterOperator,
        query_operator: index === 0 ? 'and' : filter.queryOperator || 'and',
        values: serializeValues(filter.values),
      };
    });

    const { data } = await ScoutAPI.update(props.scout.id, {
      scout: {
        audience: audiencePayload,
      },
    });

    saveSuccess.value = true;
    emit('updated', data);
    setTimeout(() => {
      saveSuccess.value = false;
    }, 3000);
  } catch (error) {
    errorMessage.value =
      error.response?.data?.error ||
      error.message ||
      t('SCOUT.AUDIENCE.ERROR_MESSAGE');
  } finally {
    isSaving.value = false;
  }
};

defineExpose({
  clearAudience,
  saveAudience,
  addCondition,
  removeCondition,
  filters,
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="pb-4 border-b border-n-weak">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('SCOUT.AUDIENCE.TITLE') }}
      </h2>
      <p class="text-xs text-n-slate-11 mt-0.5">
        {{ t('SCOUT.AUDIENCE.SUBTITLE') }}
      </p>
    </div>

    <!-- Success Message -->
    <div
      v-if="saveSuccess"
      class="p-4 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-600 dark:text-emerald-400 text-xs flex items-center gap-2"
    >
      <span class="i-lucide-check-circle size-4 flex-shrink-0" />
      <span>{{ t('SCOUT.AUDIENCE.SUCCESS_MESSAGE') }}</span>
    </div>

    <!-- Error Message -->
    <div
      v-if="errorMessage"
      class="p-4 rounded-lg bg-red-500/10 border border-red-500/20 text-red-600 dark:text-red-400 text-xs flex items-center gap-2"
    >
      <span class="i-lucide-alert-triangle size-4 flex-shrink-0" />
      <span>{{ errorMessage }}</span>
    </div>

    <!-- Empty State -->
    <div
      v-if="filters.length === 0"
      class="flex flex-col items-center justify-center p-8 rounded-xl border border-dashed border-n-weak bg-n-alpha-1 text-center"
    >
      <div class="p-3 bg-n-alpha-2 rounded-full mb-3 text-n-slate-10">
        <span class="i-lucide-users size-6" />
      </div>
      <h3 class="text-sm font-medium text-n-slate-12 mb-1">
        {{ t('SCOUT.AUDIENCE.EMPTY_STATE.TITLE') }}
      </h3>
      <p class="text-xs text-n-slate-11 max-w-md mb-4">
        {{ t('SCOUT.AUDIENCE.EMPTY_STATE.DESCRIPTION') }}
      </p>
      <Button
        :label="t('SCOUT.AUDIENCE.EMPTY_STATE.BUTTON')"
        icon="i-lucide-plus"
        color="blue"
        size="sm"
        @click="addCondition"
      />
    </div>

    <!-- Conditions List -->
    <div v-else class="flex flex-col gap-4">
      <ul class="grid gap-4 list-none p-0 m-0">
        <template v-for="(filter, index) in filters" :key="filter.id">
          <ConditionRow
            v-if="index === 0"
            ref="conditionsRef"
            :key="`filter-${filter.attributeKey}-0`"
            v-model:attribute-key="filter.attributeKey"
            v-model:filter-operator="filter.filterOperator"
            v-model:values="filter.values"
            :filter-types="attributeFilterTypes"
            :show-query-operator="false"
            @remove="removeCondition(index)"
          />
          <ConditionRow
            v-else
            :key="`filter-${filter.attributeKey}-${index}`"
            ref="conditionsRef"
            v-model:attribute-key="filter.attributeKey"
            v-model:filter-operator="filter.filterOperator"
            v-model:query-operator="filter.queryOperator"
            v-model:values="filter.values"
            show-query-operator
            :filter-types="attributeFilterTypes"
            @remove="removeCondition(index)"
          />
        </template>
      </ul>

      <!-- Action Buttons -->
      <div
        class="flex justify-between items-center pt-4 border-t border-n-weak"
      >
        <Button
          :label="t('SCOUT.AUDIENCE.ADD_CONDITION')"
          icon="i-lucide-plus"
          size="sm"
          faded
          blue
          @click="addCondition"
        />

        <div class="flex items-center gap-2">
          <Button
            :label="t('SCOUT.AUDIENCE.CLEAR_AUDIENCE')"
            size="sm"
            faded
            slate
            :disabled="isSaving"
            @click="clearAudience"
          />
          <Button
            :label="t('SCOUT.AUDIENCE.SAVE')"
            size="sm"
            solid
            blue
            :is-loading="isSaving"
            :disabled="isSaving"
            @click="saveAudience"
          />
        </div>
      </div>
    </div>
  </div>
</template>
