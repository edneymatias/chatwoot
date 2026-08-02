<script setup>
import { useI18n } from 'vue-i18n';

const props = defineProps({
  requiredCustomAttributeDefinitions: {
    type: Array,
    default: () => [],
  },
  optionalCustomAttributeDefinitions: {
    type: Array,
    default: () => [],
  },
  requiresDealValue: {
    type: Boolean,
    default: false,
  },
  customAttributes: {
    type: Object,
    default: () => ({}),
  },
  dealValue: {
    type: [Number, String],
    default: null,
  },
  missingCustomAttributeKeys: {
    type: Array,
    default: () => [],
  },
  missingDealValue: {
    type: Boolean,
    default: false,
  },
  isOptional: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:customAttributes', 'update:dealValue']);

const { t } = useI18n();

const handleAttributeUpdate = (attributeKey, value) => {
  emit('update:customAttributes', {
    ...props.customAttributes,
    [attributeKey]: value,
  });
};

const handleDealValueUpdate = event => {
  emit('update:dealValue', event.target.value);
};

const getInputType = displayType => {
  switch (displayType) {
    case 'number':
      return 'number';
    case 'date':
      return 'date';
    case 'link':
      return 'url';
    default:
      return 'text';
  }
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div
      v-for="definition in requiredCustomAttributeDefinitions"
      :key="definition.id"
      class="flex flex-col gap-1"
    >
      <label class="text-sm font-medium text-n-slate-12">
        {{ definition.attribute_display_name }}
        <span v-if="!isOptional" class="text-n-ruby-10">{{ '*' }}</span>
      </label>

      <!-- Checkbox -->
      <div
        v-if="definition.attribute_display_type === 'checkbox'"
        class="flex items-center gap-2 mt-1"
      >
        <input
          type="checkbox"
          :checked="customAttributes[definition.attribute_key]"
          class="w-4 h-4 text-n-brand-9 border-n-weak rounded focus:ring-n-brand-9"
          @change="
            handleAttributeUpdate(
              definition.attribute_key,
              $event.target.checked
            )
          "
        />
        <span class="text-sm text-n-slate-12">{{
          definition.attribute_display_name
        }}</span>
      </div>

      <!-- List (Select) -->
      <select
        v-else-if="definition.attribute_display_type === 'list'"
        :value="customAttributes[definition.attribute_key] || ''"
        class="w-full pl-3 pr-8 py-2 border rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
        :class="
          missingCustomAttributeKeys.includes(definition.attribute_key)
            ? 'border-n-ruby-7'
            : 'border-n-weak'
        "
        @change="
          handleAttributeUpdate(definition.attribute_key, $event.target.value)
        "
      >
        <option value="" disabled>
          {{ t('CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.TRIGGER.SELECT') }}
        </option>
        <option
          v-for="val in definition.attribute_values"
          :key="val"
          :value="val"
        >
          {{ val }}
        </option>
      </select>

      <!-- Standard Inputs (Text, Number, Link, Date) -->
      <input
        v-else
        :type="getInputType(definition.attribute_display_type)"
        :value="customAttributes[definition.attribute_key]"
        class="w-full px-3 py-2 border rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
        :class="
          missingCustomAttributeKeys.includes(definition.attribute_key)
            ? 'border-n-ruby-7'
            : 'border-n-weak'
        "
        :placeholder="t('CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.TRIGGER.INPUT')"
        @input="
          handleAttributeUpdate(definition.attribute_key, $event.target.value)
        "
      />

      <span
        v-if="missingCustomAttributeKeys.includes(definition.attribute_key)"
        class="text-xs text-n-ruby-10"
      >
        {{ t('CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.VALIDATIONS.REQUIRED') }}
      </span>
    </div>

    <!-- Deal Value -->
    <div v-if="requiresDealValue" class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('OPPORTUNITIES.DEAL_VALUE') || 'Deal Value' }}
        <span v-if="!isOptional" class="text-n-ruby-10">{{ '*' }}</span>
      </label>
      <input
        type="number"
        :value="dealValue"
        class="w-full px-3 py-2 border rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9"
        :class="missingDealValue ? 'border-n-ruby-7' : 'border-n-weak'"
        @input="handleDealValueUpdate"
      />
      <span v-if="missingDealValue" class="text-xs text-n-ruby-10">
        {{ t('CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.VALIDATIONS.REQUIRED') }}
      </span>
    </div>

    <!-- Optional Attributes -->
    <div
      v-for="definition in optionalCustomAttributeDefinitions"
      :key="definition.id"
      class="flex flex-col gap-1"
    >
      <label class="text-sm font-medium text-n-slate-12">
        {{ definition.attribute_display_name }}
      </label>

      <!-- Checkbox -->
      <div
        v-if="definition.attribute_display_type === 'checkbox'"
        class="flex items-center gap-2 mt-1"
      >
        <input
          type="checkbox"
          :checked="customAttributes[definition.attribute_key]"
          class="w-4 h-4 text-n-brand-9 border-n-weak rounded focus:ring-n-brand-9"
          @change="
            handleAttributeUpdate(
              definition.attribute_key,
              $event.target.checked
            )
          "
        />
        <span class="text-sm text-n-slate-12">{{
          definition.attribute_display_name
        }}</span>
      </div>

      <!-- List (Select) -->
      <select
        v-else-if="definition.attribute_display_type === 'list'"
        :value="customAttributes[definition.attribute_key] || ''"
        class="w-full pl-3 pr-8 py-2 border rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9 border-n-weak"
        @change="
          handleAttributeUpdate(definition.attribute_key, $event.target.value)
        "
      >
        <option value="" disabled>
          {{ t('CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.TRIGGER.SELECT') }}
        </option>
        <option
          v-for="val in definition.attribute_values"
          :key="val"
          :value="val"
        >
          {{ val }}
        </option>
      </select>

      <!-- Standard Inputs (Text, Number, Link, Date) -->
      <input
        v-else
        :type="getInputType(definition.attribute_display_type)"
        :value="customAttributes[definition.attribute_key]"
        class="w-full px-3 py-2 border rounded-md bg-n-surface-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand-9 border-n-weak"
        :placeholder="t('CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.TRIGGER.INPUT')"
        @input="
          handleAttributeUpdate(definition.attribute_key, $event.target.value)
        "
      />
    </div>
  </div>
</template>
