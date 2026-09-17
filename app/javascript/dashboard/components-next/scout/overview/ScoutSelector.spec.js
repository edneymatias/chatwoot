import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import ScoutSelector from './ScoutSelector.vue';

describe('ScoutSelector', () => {
  it('renders nothing when scouts length is 1 (U35)', () => {
    const wrapper = mount(ScoutSelector, {
      props: {
        scouts: [{ id: 1, name: 'Scout Alpha' }],
        modelValue: 1,
      },
    });

    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.html()).toBe('<!--v-if-->');
  });

  it('renders select dropdown when scouts length > 1 (U34)', () => {
    const scouts = [
      { id: 1, name: 'Scout Alpha' },
      { id: 2, name: 'Scout Beta' },
    ];
    const wrapper = mount(ScoutSelector, {
      props: {
        scouts,
        modelValue: 1,
      },
    });

    expect(wrapper.find('select').exists()).toBe(true);
    const options = wrapper.findAll('option');
    expect(options).toHaveLength(2);
    expect(options[0].text()).toBe('Scout Alpha');
    expect(options[1].text()).toBe('Scout Beta');
  });

  it('emits update:modelValue when user selects a different scout (U36)', async () => {
    const scouts = [
      { id: 1, name: 'Scout Alpha' },
      { id: 2, name: 'Scout Beta' },
    ];
    const wrapper = mount(ScoutSelector, {
      props: {
        scouts,
        modelValue: 1,
      },
    });

    await wrapper.find('select').setValue('2');
    expect(wrapper.emitted('update:modelValue')).toBeTruthy();
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([2]);
  });
});
