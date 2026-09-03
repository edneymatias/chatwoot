import { describe, it, expect, vi, beforeEach } from 'vitest';
import { shallowMount } from '@vue/test-utils';
import { useStore } from 'dashboard/composables/store';
import EditPipelineStage from '../EditPipelineStage.vue';

vi.mock('dashboard/composables/store');

describe('EditPipelineStage.vue', () => {
  let dispatchMock;

  const stage = {
    id: 1,
    name: 'Stage 1',
    description: 'Desc',
    requires_deal_value: false,
    campaign_report_milestone: false,
    accent_color: '',
    total_display_mode: 'value_sum',
    stale_after_days: null,
    required_custom_attribute_definitions: [],
  };

  const createWrapper = (customStage = stage) => {
    dispatchMock = vi.fn().mockResolvedValue({});
    useStore.mockReturnValue({
      dispatch: dispatchMock,
      getters: {
        'pipelineStages/stageById': () => customStage,
        'attributes/getAttributesByModel': () => [],
      },
    });

    return shallowMount(EditPipelineStage, {
      props: {
        show: true,
        stage: customStage,
      },
      global: {
        mocks: {
          $t: key => key,
        },
        stubs: {
          WootModal: { template: '<div><slot /></div>' },
          WootModalHeader: true,
          StageDescriptionEditor: true,
          ColorPicker: true,
        },
      },
    });
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('initializes with stage campaign_report_milestone value', async () => {
    const wrapper = createWrapper({
      ...stage,
      campaign_report_milestone: true,
    });
    await wrapper.vm.$nextTick();

    const checkboxes = wrapper.findAll('input[type="checkbox"]');
    expect(checkboxes.length).toBeGreaterThanOrEqual(2);
    expect(checkboxes[1].element.checked).toBe(true);
  });

  it('submits updated campaign_report_milestone value', async () => {
    const wrapper = createWrapper();

    const checkboxes = wrapper.findAll('input[type="checkbox"]');
    await checkboxes[1].setValue(true);

    const submitButton = wrapper
      .findAll('button')
      .find(b => b.text().includes('PIPELINE_STAGES_MGMT.FORM.SUBMIT_EDIT'));

    await submitButton.trigger('click');

    expect(dispatchMock).toHaveBeenCalledWith(
      'pipelineStages/update',
      expect.objectContaining({
        id: 1,
        campaign_report_milestone: true,
      })
    );
  });
});
