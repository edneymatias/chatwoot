<script setup>
import { onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AddPipelineStage from './AddPipelineStage.vue';
import EditPipelineStage from './EditPipelineStage.vue';

const { t } = useI18n();
const store = useStore();

const [showAddPopup, toggleAddPopup] = useToggle(false);
const [showEditPopup, toggleEditPopup] = useToggle(false);
const selectedStage = ref({});

const stages = ref([]);

watch(
  () => store.getters['pipelineStages/stagesSortedByPosition'],
  newStages => {
    stages.value = [...newStages];
  },
  { immediate: true }
);

onMounted(() => {
  store.dispatch('pipelineStages/fetch');
});

const onEdit = stage => {
  selectedStage.value = stage;
  toggleEditPopup(true);
};

const onDelete = async stage => {
  if (window.confirm(t('PIPELINE_STAGES_MGMT.DELETE.CONFIRM'))) {
    try {
      await store.dispatch('pipelineStages/delete', stage.id);
      useAlert(t('PIPELINE_STAGES_MGMT.DELETE.SUCCESS'));
    } catch (error) {
      if (error.response && error.response.status === 422) {
        useAlert(
          error.response.data.error ||
            t('PIPELINE_STAGES_MGMT.DELETE.ERROR_OCCUPIED')
        );
      } else {
        useAlert(t('PIPELINE_STAGES_MGMT.DELETE.ERROR'));
      }
    }
  }
};

const onChange = event => {
  if (event.moved) {
    const stage = event.moved.element;
    const newIndex = event.moved.newIndex;
    const newPosition = newIndex + 1;
    store.dispatch('pipelineStages/update', {
      id: stage.id,
      position: newPosition,
    });
  }
};
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="$t('PIPELINE_STAGES_MGMT.HEADER')"
        :description="$t('PIPELINE_STAGES_MGMT.DESCRIPTION')"
      >
        <template #actions>
          <Button icon="plus" @click="toggleAddPopup(true)">
            {{ $t('PIPELINE_STAGES_MGMT.ADD.TITLE') }}
          </Button>
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div
        class="flex-1 overflow-auto bg-n-surface-1 border border-n-weak rounded-xl shadow-sm my-4"
      >
        <div v-if="stages.length === 0" class="p-8 text-center text-n-slate-11">
          {{ $t('PIPELINE_STAGES_MGMT.LIST.EMPTY_STATE') }}
        </div>
        <Draggable
          v-else
          v-model="stages"
          item-key="id"
          class="divide-y divide-n-weak"
          ghost-class="opacity-50 bg-n-surface-3"
          @change="onChange"
        >
          <template #item="{ element }">
            <div
              class="p-4 flex items-center justify-between hover:bg-n-surface-2 transition-colors group"
            >
              <div class="flex items-center gap-3">
                <span
                  class="flex-shrink-0 transition-colors i-lucide-grip-vertical size-5 text-n-slate-9 group-hover:text-n-slate-11 cursor-grab"
                />
                <div class="flex flex-col">
                  <span class="font-medium text-n-slate-12 text-sm">{{
                    element.name
                  }}</span>
                  <span
                    v-if="element.description"
                    class="text-xs text-n-slate-11"
                    >{{ element.description }}</span>
                </div>
              </div>
              <div
                class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Button
                  variant="ghost"
                  icon="edit"
                  size="sm"
                  @click="onEdit(element)"
                />
                <Button
                  variant="ghost"
                  color-scheme="alert"
                  icon="delete"
                  size="sm"
                  @click="onDelete(element)"
                />
              </div>
            </div>
          </template>
        </Draggable>
      </div>

      <AddPipelineStage
        v-if="showAddPopup"
        :show="showAddPopup"
        @close="toggleAddPopup(false)"
      />
      <EditPipelineStage
        v-if="showEditPopup"
        :show="showEditPopup"
        :stage="selectedStage"
        @close="toggleEditPopup(false)"
      />
    </template>
  </SettingsLayout>
</template>
