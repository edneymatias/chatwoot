import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import PipelineDistributionChart from './PipelineDistributionChart.vue';

describe('PipelineDistributionChart', () => {
  const stages = [
    { stage_id: 1, stage_name: 'Novo', stage_position: 0, count: 12 },
    { stage_id: 2, stage_name: 'Qualificado', stage_position: 1, count: 24 },
    { stage_id: 3, stage_name: 'Negociação', stage_position: 2, count: 0 },
  ];

  it('renders stages ordered by stage_position ASC (U37)', () => {
    const wrapper = mount(PipelineDistributionChart, {
      props: { stages },
    });

    const labels = wrapper
      .findAll('[data-testid="stage-label"]')
      .map(w => w.text());
    expect(labels).toEqual(['Novo', 'Qualificado', 'Negociação']);
  });

  it('renders stage names and counts including count 0 (U38)', () => {
    const wrapper = mount(PipelineDistributionChart, {
      props: { stages },
    });

    const counts = wrapper
      .findAll('[data-testid="stage-count"]')
      .map(w => w.text());
    expect(counts).toEqual(['12', '24', '0']);
  });
});
