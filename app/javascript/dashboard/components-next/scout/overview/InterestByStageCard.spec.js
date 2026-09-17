import { withFullI18n } from 'test-i18n';

withFullI18n();

import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import InterestByStageCard from './InterestByStageCard.vue';

describe('InterestByStageCard', () => {
  it('renders explanatory notice and CTA button navigating to scout_funnel when configured is false (U39)', () => {
    const wrapper = mount(InterestByStageCard, {
      props: {
        interestData: { configured: false },
        scoutId: 42,
        accountId: 1,
      },
    });

    expect(wrapper.text()).toContain('Interest by Stage');
    const ctaButton = wrapper.find('[data-testid="configure-interest-cta"]');
    expect(ctaButton.exists()).toBe(true);
    expect(ctaButton.attributes('href')).toContain(
      '/app/accounts/1/scout/42/funnel'
    );
  });

  it('renders breakdown distribution per stage when configured is true (U40)', () => {
    const wrapper = mount(InterestByStageCard, {
      props: {
        interestData: {
          configured: true,
          attribute_name: 'Produto',
          data: [
            {
              stage_id: 1,
              stage_name: 'Novo',
              breakdown: { Seguro: 7, Financiamento: 4, null: 1 },
            },
            {
              stage_id: 2,
              stage_name: 'Qualificado',
              breakdown: { Seguro: 14, Financiamento: 10 },
            },
          ],
        },
        scoutId: 42,
        accountId: 1,
      },
    });

    expect(wrapper.text()).toContain('Produto by Stage');
    expect(wrapper.text()).toContain('Novo');
    expect(wrapper.text()).toContain('Qualificado');
    expect(wrapper.text()).toContain('Seguro: 7');
    expect(wrapper.text()).toContain('Financiamento: 4');
  });
});
