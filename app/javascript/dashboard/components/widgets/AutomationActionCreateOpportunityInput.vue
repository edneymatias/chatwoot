<script>
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

export default {
  components: {
    SingleSelect,
  },
  props: {
    pipelineStages: { type: Array, required: true },
    agents: { type: Array, required: true },
    modelValue: { type: [Object, Array], default: () => ({}) },
    dropdownMaxHeight: { type: String, default: 'max-h-80' },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      selectedStage: null,
      selectedAgent: null,
    };
  },
  watch: {
    modelValue: {
      handler: 'initializeValues',
      deep: true,
      immediate: true,
    },
    pipelineStages: {
      handler: 'initializeValues',
      immediate: true,
    },
    agents: {
      handler: 'initializeValues',
      immediate: true,
    },
  },
  methods: {
    initializeValues() {
      const rawValue = Array.isArray(this.modelValue)
        ? this.modelValue[0]
        : this.modelValue;
      const { pipeline_stage_id: stageId, assignee_id: assigneeId } =
        rawValue || {};

      if (stageId && Array.isArray(this.pipelineStages)) {
        this.selectedStage =
          this.pipelineStages.find(
            s => s.id === stageId || s.id === Number(stageId)
          ) || null;
      } else if (!stageId) {
        this.selectedStage = null;
      }

      if (
        assigneeId !== undefined &&
        assigneeId !== null &&
        Array.isArray(this.agents)
      ) {
        this.selectedAgent =
          this.agents.find(
            a => a.id === assigneeId || a.id === Number(assigneeId)
          ) || null;
      } else if (!assigneeId) {
        this.selectedAgent = null;
      }
    },
    updateValue() {
      this.$emit('update:modelValue', {
        pipeline_stage_id: this.selectedStage?.id ?? null,
        assignee_id: this.selectedAgent?.id ?? null,
      });
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <SingleSelect
      v-model="selectedStage"
      :options="pipelineStages"
      :dropdown-max-height="dropdownMaxHeight"
      :placeholder="
        $t('AUTOMATION.ACTION.CREATE_OPPORTUNITY_STAGE_PLACEHOLDER')
      "
      @update:model-value="updateValue"
    />
    <SingleSelect
      v-model="selectedAgent"
      :options="agents"
      :dropdown-max-height="dropdownMaxHeight"
      :placeholder="
        $t('AUTOMATION.ACTION.CREATE_OPPORTUNITY_ASSIGNEE_PLACEHOLDER')
      "
      @update:model-value="updateValue"
    />
  </div>
</template>
