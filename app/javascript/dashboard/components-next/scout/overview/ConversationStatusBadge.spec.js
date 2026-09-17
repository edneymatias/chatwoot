import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ConversationStatusBadge from './ConversationStatusBadge.vue';

withFullI18n();

describe('ConversationStatusBadge', () => {
  it('renders green/teal styling and translated label for qualified status (U27)', () => {
    const wrapper = mount(ConversationStatusBadge, {
      props: { status: 'qualified' },
    });

    expect(wrapper.text()).toBe('Qualified');
    expect(wrapper.classes()).toContain('bg-n-teal-3');
    expect(wrapper.classes()).toContain('text-n-teal-11');
  });

  it('renders ruby/red styling and translated label for disqualified status (U28)', () => {
    const wrapper = mount(ConversationStatusBadge, {
      props: { status: 'disqualified' },
    });

    expect(wrapper.text()).toBe('Disqualified');
    expect(wrapper.classes()).toContain('bg-n-ruby-3');
    expect(wrapper.classes()).toContain('text-n-ruby-11');
  });

  it('renders amber styling and translated label for abandoned status (U29)', () => {
    const wrapper = mount(ConversationStatusBadge, {
      props: { status: 'abandoned' },
    });

    expect(wrapper.text()).toBe('Abandoned');
    expect(wrapper.classes()).toContain('bg-n-amber-3');
    expect(wrapper.classes()).toContain('text-n-amber-11');
  });

  it('renders blue styling and translated label for in_progress status (U30)', () => {
    const wrapper = mount(ConversationStatusBadge, {
      props: { status: 'in_progress' },
    });

    expect(wrapper.text()).toBe('In Progress');
    expect(wrapper.classes()).toContain('bg-n-blue-3');
    expect(wrapper.classes()).toContain('text-n-blue-11');
  });

  it('renders neutral slate styling for transferred_without_opportunity and never error classes (U31)', () => {
    const wrapper = mount(ConversationStatusBadge, {
      props: { status: 'transferred_without_opportunity' },
    });

    expect(wrapper.text()).toBe('Transferred without opportunity');
    expect(wrapper.classes()).toContain('bg-n-slate-3');
    expect(wrapper.classes()).toContain('text-n-slate-11');
    expect(wrapper.classes()).not.toContain('bg-n-ruby-3');
    expect(wrapper.classes()).not.toContain('text-n-ruby-11');
  });
});
