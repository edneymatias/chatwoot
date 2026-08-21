<script setup>
import { ref, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import SettingsLayout from '../../settings/SettingsLayout.vue';
import BaseSettingsHeader from '../../settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import ScoutToolModal from 'dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue';

const { t } = useI18n();

const tools = ref([]);
const isLoading = ref(true);
const toolModalRef = ref(null);
const editingTool = ref(null);

const fetchTools = async () => {
  isLoading.value = true;
  try {
    const { data } = await ScoutAPI.getTools();
    tools.value = Array.isArray(data) ? data : [];
  } catch (error) {
    tools.value = [];
  } finally {
    isLoading.value = false;
  }
};

const handleOpenAdd = () => {
  editingTool.value = null;
  nextTick(() => {
    toolModalRef.value?.openModal();
  });
};

const handleOpenEdit = tool => {
  editingTool.value = tool;
  nextTick(() => {
    toolModalRef.value?.openModal();
  });
};

const handleToggleActive = async tool => {
  try {
    await ScoutAPI.updateTool(tool.id, { enabled: !tool.enabled });
    tool.enabled = !tool.enabled;
  } catch (error) {
    // Handled
  }
};

const handleDelete = async toolId => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('SCOUT.TOOLS.CONFIRM_DELETE'))) return;

  try {
    await ScoutAPI.deleteTool(toolId);
    await fetchTools();
  } catch (error) {
    // Handled
  }
};

onMounted(() => {
  fetchTools();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full m-0 pb-8 pt-4 px-6 overflow-auto bg-n-surface-1"
  >
    <div class="flex items-start w-full max-w-5xl mx-auto">
      <SettingsLayout
        :is-loading="isLoading"
        :no-records-found="!tools.length && !isLoading"
      >
        <template #header>
          <BaseSettingsHeader
            :title="t('SCOUT.TOOLS.TITLE')"
            :description="t('SCOUT.TOOLS.SUBTITLE')"
            feature-name="scout_tools"
            :back-button-label="t('SCOUT.TOOLS.BACK')"
          >
            <template #actions>
              <Button
                :label="t('SCOUT.TOOLS.ADD_BUTTON')"
                color="blue"
                size="sm"
                @click="handleOpenAdd"
              />
            </template>
          </BaseSettingsHeader>
        </template>
        <template #body>
          <EmptyStateLayout
            v-if="tools.length === 0"
            :title="t('SCOUT.TOOLS.EMPTY_TITLE')"
            :subtitle="t('SCOUT.TOOLS.EMPTY_DESC')"
            :show-backdrop="false"
          >
            <template #actions>
              <Button
                :label="t('SCOUT.TOOLS.ADD_BUTTON')"
                color="blue"
                size="sm"
                @click="handleOpenAdd"
              />
            </template>
          </EmptyStateLayout>

          <!-- Tools List -->
          <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div
              v-for="tool in tools"
              :key="tool.id"
              class="flex flex-col justify-between p-5 rounded-xl border border-n-weak bg-n-solid-2 hover:border-n-brand/40 transition-all duration-200 shadow-sm"
            >
              <div>
                <div class="flex items-start justify-between gap-3">
                  <div class="flex items-center gap-3">
                    <div
                      class="flex items-center justify-center size-9 rounded-lg"
                      :class="
                        tool.enabled
                          ? 'bg-n-brand/10 text-n-brand'
                          : 'bg-n-alpha-1 text-n-slate-10'
                      "
                    >
                      <span class="i-lucide-wrench size-4" />
                    </div>
                    <div>
                      <h3 class="text-sm font-medium text-n-slate-12">
                        {{ tool.name }}
                      </h3>
                      <span class="text-xs font-mono text-n-slate-10">
                        {{ tool.http_method }} {{ tool.url }}
                      </span>
                    </div>
                  </div>

                  <div class="flex items-center gap-2">
                    <Switch
                      :model-value="tool.enabled"
                      @change="handleToggleActive(tool)"
                    />
                    <Button
                      icon="i-lucide-pencil"
                      variant="ghost"
                      color="slate"
                      size="xs"
                      @click="handleOpenEdit(tool)"
                    />
                    <Button
                      icon="i-lucide-trash-2"
                      variant="ghost"
                      color="ruby"
                      size="xs"
                      @click="handleDelete(tool.id)"
                    />
                  </div>
                </div>

                <p
                  v-if="tool.description"
                  class="text-xs text-n-slate-11 mt-3 line-clamp-2 leading-relaxed"
                >
                  {{ tool.description }}
                </p>
              </div>
            </div>
          </div>
        </template>
      </SettingsLayout>
    </div>
  </div>
  <!-- Tool Modal -->
  <ScoutToolModal ref="toolModalRef" :tool="editingTool" @saved="fetchTools" />
</template>
