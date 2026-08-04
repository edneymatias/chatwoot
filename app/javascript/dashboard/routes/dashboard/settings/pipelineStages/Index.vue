<script setup>
import { onMounted, ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import AddPipelineStage from './AddPipelineStage.vue';
import EditPipelineStage from './EditPipelineStage.vue';
import ClosingRequiredFields from './ClosingRequiredFields.vue';
import CardFieldConfig from './CardFieldConfig.vue';

const { t } = useI18n();
const store = useStore();

const [showAddPopup, toggleAddPopup] = useToggle(false);
const [showEditPopup, toggleEditPopup] = useToggle(false);
const selectedStage = ref({});
const selectedTabIndex = ref(0);

const tabs = computed(() => {
  return [
    {
      key: 0,
      name: t('PIPELINE_STAGES_MGMT.CARD_FIELDS.TITLE') || 'Card Fields',
    },
    {
      key: 1,
      name: t('PIPELINE_STAGES_MGMT.TABS.STAGES') || 'Pipeline Stages',
    },
    {
      key: 2,
      name:
        t('OPPORTUNITIES.REQUIREMENTS_MODAL.CLOSING_REQUIREMENTS_TITLE') ||
        'Closing Requirements',
    },
  ];
});

const tabsForTabBar = computed(() =>
  tabs.value.map(tab => ({ label: tab.name, key: tab.key }))
);

const onClickTabChange = tab => {
  selectedTabIndex.value = tab.key;
};

const stages = computed({
  get: () => store.getters['pipelineStages/stagesSortedByPosition'],
  set: value => {
    store.commit('pipelineStages/SET_STAGES', value);
  },
});

onMounted(() => {
  store.dispatch('pipelineStages/fetch');
});

const onEdit = stage => {
  selectedStage.value = stage;
  toggleEditPopup(true);
};

const onDelete = async stage => {
  // eslint-disable-next-line no-alert
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

const onChange = async event => {
  if (event.moved) {
    const stage = event.moved.element;
    const newIndex = event.moved.newIndex;
    const newPosition = newIndex + 1;
    try {
      await store.dispatch('pipelineStages/update', {
        id: stage.id,
        position: newPosition,
      });
    } catch (error) {
      store.dispatch('pipelineStages/fetch');
      useAlert(t('PIPELINE_STAGES_MGMT.REORDER.ERROR'));
    }
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
        <template #tabs>
          <TabBar
            :tabs="tabsForTabBar"
            :initial-active-tab="selectedTabIndex"
            @tab-changed="onClickTabChange"
          />
        </template>
        <template #actions>
          <div v-if="selectedTabIndex === 1" class="flex items-center gap-2">
            <Button size="sm" icon="plus" @click="toggleAddPopup(true)">
              {{ $t('PIPELINE_STAGES_MGMT.ADD.TITLE') }}
            </Button>
          </div>
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <template v-if="selectedTabIndex === 0">
        <CardFieldConfig />
      </template>
      <template v-else-if="selectedTabIndex === 1">
        <div class="flex-1 flex flex-col max-h-[calc(100vh-240px)] overflow-y-auto pt-4 pb-8">
          <div class="flex flex-col max-w-4xl">
            <div v-if="stages.length === 0" class="text-sm text-n-slate-11">
              {{ $t('PIPELINE_STAGES_MGMT.LIST.EMPTY_STATE') }}
            </div>
            <div
              v-else
              class="border border-n-weak rounded-xl bg-n-surface-1 overflow-visible"
            >
              <Draggable
                v-model="stages"
                item-key="id"
                class="divide-y divide-n-weak"
                ghost-class="opacity-50"
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
                        >
                          {{ element.description }}
                        </span>
                      </div>
                    </div>
                    <div
                      class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity"
                    >
                      <Button
                        variant="ghost"
                        icon="i-lucide-pencil"
                        size="sm"
                        @click="onEdit(element)"
                      />
                      <Button
                        variant="ghost"
                        color-scheme="alert"
                        icon="i-lucide-trash"
                        size="sm"
                        @click="onDelete(element)"
                      />
                    </div>
                  </div>
                </template>
              </Draggable>
            </div>
          </div>
        </div>
      </template>
      <template v-else-if="selectedTabIndex === 2">
        <ClosingRequiredFields />
      </template>

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
