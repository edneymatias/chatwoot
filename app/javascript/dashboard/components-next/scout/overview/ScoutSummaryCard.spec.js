import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import ScoutSummaryCard from './ScoutSummaryCard.vue';

describe('ScoutSummaryCard', () => {
  it('renders card label and numeric value (U31)', () => {
    const wrapper = mount(ScoutSummaryCard, {
      props: {
        label: 'Total Handled',
        value: 47,
      },
    });

    expect(wrapper.text()).toContain('Total Handled');
    expect(wrapper.text()).toContain('47');
  });

  it('renders neutral placeholder "—" when value is null (U32)', () => {
    const wrapper = mount(ScoutSummaryCard, {
      props: {
        label: 'Qualification Rate',
        value: null,
      },
    });

    expect(wrapper.text()).toContain('Qualification Rate');
    expect(wrapper.text()).toContain('—');
  });

  it('renders percentage symbol or custom unit suffix when specified (U33)', () => {
    const wrapper = mount(ScoutSummaryCard, {
      props: {
        label: 'Qualification Rate',
        value: 51.06,
        unit: '%',
      },
    });

    expect(wrapper.text()).toContain('51.06%');
  });
});
