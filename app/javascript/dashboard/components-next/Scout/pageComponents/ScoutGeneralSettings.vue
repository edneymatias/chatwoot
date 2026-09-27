<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
const props = defineProps({
  scout: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['updated']);
const { t } = useI18n();

const name = ref(props.scout.name || '');
const persona = ref(props.scout.persona || '');
const debounceDelay = ref(props.scout.debounce_delay_seconds || 5);
const responsesQuota = ref(props.scout.responses_quota ?? -1);
const isEnabled = ref(props.scout.enabled ?? true);
const role = ref(props.scout.role || '');
const scope = ref(props.scout.scope || '');
const tone = ref(props.scout.tone || 'friendly');
const responseLength = ref(props.scout.response_length || 'concise');
const greeting = ref(props.scout.greeting || '');
const isSaving = ref(false);
const saveSuccess = ref(false);

const toneOptions = computed(() => [
  { value: 'friendly', label: t('SCOUT.GENERAL.TONE_OPTIONS.FRIENDLY') },
  { value: 'neutral', label: t('SCOUT.GENERAL.TONE_OPTIONS.NEUTRAL') },
  {
    value: 'matter_of_fact',
    label: t('SCOUT.GENERAL.TONE_OPTIONS.MATTER_OF_FACT'),
  },
  {
    value: 'professional',
    label: t('SCOUT.GENERAL.TONE_OPTIONS.PROFESSIONAL'),
  },
  { value: 'humorous', label: t('SCOUT.GENERAL.TONE_OPTIONS.HUMOROUS') },
]);

const responseLengthOptions = computed(() => [
  {
    value: 'concise',
    label: t('SCOUT.GENERAL.RESPONSE_LENGTH_OPTIONS.CONCISE'),
  },
  {
    value: 'standard',
    label: t('SCOUT.GENERAL.RESPONSE_LENGTH_OPTIONS.STANDARD'),
  },
  {
    value: 'thorough',
    label: t('SCOUT.GENERAL.RESPONSE_LENGTH_OPTIONS.THOROUGH'),
  },
]);

watch(
  () => props.scout,
  newVal => {
    if (!newVal) return;
    name.value = newVal.name || '';
    persona.value = newVal.persona || '';
    debounceDelay.value = newVal.debounce_delay_seconds || 5;
    responsesQuota.value = newVal.responses_quota ?? -1;
    isEnabled.value = newVal.enabled ?? true;
    role.value = newVal.role || '';
    scope.value = newVal.scope || '';
    tone.value = newVal.tone || 'friendly';
    responseLength.value = newVal.response_length || 'concise';
    greeting.value = newVal.greeting || '';
  },
  { deep: true }
);

const handleSave = async () => {
  if (!name.value.trim()) return;

  isSaving.value = true;
  saveSuccess.value = false;
  try {
    const payload = {
      name: name.value.trim(),
      persona: persona.value.trim(),
      debounce_delay_seconds: parseInt(debounceDelay.value, 10) || 5,
      responses_quota: parseInt(responsesQuota.value, 10),
      enabled: isEnabled.value,
      role: role.value,
      scope: scope.value,
      tone: tone.value,
      response_length: responseLength.value,
      greeting: greeting.value || null,
    };

    await ScoutAPI.update(props.scout.id, payload);
    saveSuccess.value = true;
    emit('updated');
    setTimeout(() => {
      saveSuccess.value = false;
    }, 3000);
  } catch (error) {
    // Handled
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex items-center justify-between pb-4">
      <div>
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('SCOUT.GENERAL.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11 mt-0.5">
          {{ t('SCOUT.GENERAL.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-xs font-medium text-n-slate-12">
          {{
            isEnabled ? t('SCOUT.STATUS_ACTIVE') : t('SCOUT.STATUS_INACTIVE')
          }}
        </span>
        <Switch v-model="isEnabled" />
      </div>
    </div>

    <div class="space-y-4">
      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ `${t('SCOUT.GENERAL.NAME_LABEL')} *` }}
        </label>
        <Input
          v-model="name"
          :placeholder="t('SCOUT.GENERAL.NAME_PLACEHOLDER')"
        />
      </div>

      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ t('SCOUT.GENERAL.PERSONA_LABEL') }}
        </label>
        <TextArea
          v-model="persona"
          :placeholder="t('SCOUT.GENERAL.PERSONA_PLACEHOLDER')"
          :max-length="3000"
          auto-height
        />
        <span class="text-[11px] text-n-slate-10 mt-1 block">
          {{ t('SCOUT.GENERAL.PERSONA_HINT') }}
        </span>
      </div>

      <div class="pt-4 border-t border-n-weak space-y-4">
        <div>
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('SCOUT.GENERAL.V2_SECTION_TITLE') }}
          </h3>
          <p class="text-xs text-n-slate-11 mt-0.5">
            {{ t('SCOUT.GENERAL.V2_SECTION_DESCRIPTION') }}
          </p>
        </div>

        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.GENERAL.ROLE_LABEL') }}
          </label>
          <TextArea
            v-model="role"
            :placeholder="t('SCOUT.GENERAL.ROLE_PLACEHOLDER')"
            :max-length="500"
            show-character-count
            auto-height
          />
          <span class="text-[11px] text-n-slate-10 mt-1 block">
            {{ t('SCOUT.GENERAL.ROLE_HINT') }}
          </span>
        </div>

        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.GENERAL.SCOPE_LABEL') }}
          </label>
          <TextArea
            v-model="scope"
            :placeholder="t('SCOUT.GENERAL.SCOPE_PLACEHOLDER')"
            :max-length="500"
            show-character-count
            auto-height
          />
          <span class="text-[11px] text-n-slate-10 mt-1 block">
            {{ t('SCOUT.GENERAL.SCOPE_HINT') }}
          </span>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ t('SCOUT.GENERAL.TONE_LABEL') }}
            </label>
            <Select
              v-model="tone"
              class="!w-full [&>select]:w-full"
              :options="toneOptions"
            />
            <span class="text-[11px] text-n-slate-10 mt-1 block">
              {{ t('SCOUT.GENERAL.TONE_HINT') }}
            </span>
          </div>

          <div>
            <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
              {{ t('SCOUT.GENERAL.RESPONSE_LENGTH_LABEL') }}
            </label>
            <Select
              v-model="responseLength"
              class="!w-full [&>select]:w-full"
              :options="responseLengthOptions"
            />
            <span class="text-[11px] text-n-slate-10 mt-1 block">
              {{ t('SCOUT.GENERAL.RESPONSE_LENGTH_HINT') }}
            </span>
          </div>
        </div>

        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.GENERAL.GREETING_LABEL') }}
          </label>
          <Input
            v-model="greeting"
            :placeholder="t('SCOUT.GENERAL.GREETING_PLACEHOLDER')"
          />
          <span class="text-[11px] text-n-slate-10 mt-1 block">
            {{ t('SCOUT.GENERAL.GREETING_HINT') }}
          </span>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2">
        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.GENERAL.DEBOUNCE_LABEL') }}
          </label>
          <Input v-model="debounceDelay" type="number" min="1" max="60" />
          <span class="text-[11px] text-n-slate-10 mt-1 block">
            {{ t('SCOUT.GENERAL.DEBOUNCE_HINT') }}
          </span>
        </div>

        <div>
          <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
            {{ t('SCOUT.GENERAL.QUOTA_LABEL') }}
          </label>
          <Input v-model="responsesQuota" type="number" placeholder="-1" />
          <span class="text-[11px] text-n-slate-10 mt-1 block">
            {{ t('SCOUT.GENERAL.QUOTA_HINT') }}
          </span>
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
        :disabled="!name.trim() || isSaving"
        @click="handleSave"
      />
    </div>
  </div>
</template>
