import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ScoutGeneralSettings from '../ScoutGeneralSettings.vue';
import ScoutAPI from 'dashboard/api/scout';

vi.mock('dashboard/api/scout', () => ({
  default: {
    update: vi.fn().mockResolvedValue({ data: {} }),
  },
}));

const i18n = withFullI18n();

describe('ScoutGeneralSettings.vue', () => {
  const defaultScout = {
    id: 1,
    name: 'Sales Qualifier',
    persona: 'Qualify leads according to BANT criteria.',
    debounce_delay_seconds: 5,
    responses_quota: -1,
    enabled: true,
    role: null,
    scope: null,
    tone: 'friendly',
    response_length: 'concise',
    greeting: null,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    i18n.global.locale.value = 'en';
  });

  const mountComponent = (scoutProps = {}) => {
    return mount(ScoutGeneralSettings, {
      props: {
        scout: { ...defaultScout, ...scoutProps },
      },
    });
  };

  it('1. renders the five V2 fields without any feature flag', () => {
    const wrapper = mountComponent();

    expect(wrapper.text()).toContain('New version of the Scout');
    expect(wrapper.text()).toContain('Role and Purpose');
    expect(wrapper.text()).toContain('Scope and Boundaries');
    expect(wrapper.text()).toContain('Tone of Voice');
    expect(wrapper.text()).toContain('Response Length');
    expect(wrapper.text()).toContain('Initial Greeting');
  });

  it('2. prefills values when provided and shows empty fields with 0 / 500 counters when null', () => {
    const populatedScout = {
      role: 'SDR de teste',
      scope: 'Apenas agendamentos',
      tone: 'professional',
      response_length: 'thorough',
      greeting: 'Olá! Sou a Clara.',
    };

    const populatedWrapper = mountComponent(populatedScout);
    const textareas = populatedWrapper.findAll('textarea');
    // textareas: 0 is persona, 1 is role, 2 is scope
    expect(textareas.length).toBeGreaterThanOrEqual(3);
    expect(textareas[1].element.value).toBe('SDR de teste');
    expect(textareas[2].element.value).toBe('Apenas agendamentos');

    const selects = populatedWrapper.findAll('select');
    expect(selects.length).toBeGreaterThanOrEqual(2);
    expect(selects[0].element.value).toBe('professional');
    expect(selects[1].element.value).toBe('thorough');

    const inputs = populatedWrapper.findAll('input');
    const greetingInput = inputs.find(
      i => i.element.value === 'Olá! Sou a Clara.'
    );
    expect(greetingInput).toBeDefined();
    expect(greetingInput.element.value).toBe('Olá! Sou a Clara.');

    const emptyWrapper = mountComponent({
      role: null,
      scope: null,
      greeting: null,
    });
    const emptyTextareas = emptyWrapper.findAll('textarea');
    expect(emptyTextareas[1].element.value).toBe('');
    expect(emptyTextareas[2].element.value).toBe('');
    expect(emptyWrapper.text()).toContain('0 / 500');
  });

  it('3. renders Tone select with exactly 5 options and Response Length with exactly 3 in contract order', () => {
    const wrapper = mountComponent();
    const selects = wrapper.findAll('select');
    // We expect Tone and Response Length selects
    expect(selects.length).toBeGreaterThanOrEqual(2);

    const toneSelect = selects[0];
    const toneOptions = toneSelect.findAll('option').map(o => o.element.value);
    expect(toneOptions).toEqual([
      'friendly',
      'neutral',
      'matter_of_fact',
      'professional',
      'humorous',
    ]);

    const lengthSelect = selects[1];
    const lengthOptions = lengthSelect
      .findAll('option')
      .map(o => o.element.value);
    expect(lengthOptions).toEqual(['concise', 'standard', 'thorough']);
  });

  it('4. sets maxlength="500" on Role/Scope and renders 500 / 500 for a 500-char value', () => {
    const text500 = 'a'.repeat(500);
    const wrapper = mountComponent({ role: text500, scope: text500 });
    const textareas = wrapper.findAll('textarea');

    expect(textareas[1].attributes('maxlength')).toBe('500');
    expect(textareas[2].attributes('maxlength')).toBe('500');
    expect(wrapper.text()).toContain('500 / 500');
  });

  it('5. calls ScoutAPI.update with the five keys and edited values, sending greeting: null when empty', async () => {
    const wrapper = mountComponent({
      role: 'Initial Role',
      scope: 'Initial Scope',
      tone: 'friendly',
      response_length: 'concise',
      greeting: 'Initial Greeting',
    });

    const textareas = wrapper.findAll('textarea');
    await textareas[1].setValue('Updated Role');
    await textareas[2].setValue('Updated Scope');

    const selects = wrapper.findAll('select');
    await selects[0].setValue('professional');
    await selects[1].setValue('thorough');

    // inputs: 0 is name, 1 is greeting (in the new section), then debounce and quota
    const inputs = wrapper.findAll('input');
    const greetingInput = inputs.find(
      i => i.element.value === 'Initial Greeting'
    );
    await greetingInput.setValue('');

    const saveButton = wrapper
      .findAll('button')
      .find(b => b.text().includes('Save Changes'));
    await saveButton.trigger('click');

    expect(ScoutAPI.update).toHaveBeenCalledWith(1, {
      name: 'Sales Qualifier',
      persona: 'Qualify leads according to BANT criteria.',
      debounce_delay_seconds: 5,
      responses_quota: -1,
      enabled: true,
      role: 'Updated Role',
      scope: 'Updated Scope',
      tone: 'professional',
      response_length: 'thorough',
      greeting: null,
    });
  });

  it('6. renders en hint texts asserting literal phrases with new version mentions and greeting advice', () => {
    const wrapper = mountComponent();
    const text = wrapper.text();

    expect(text).toContain(
      'Defines what the assistant does, its commercial objective, and target audience for the new version of the Scout.'
    );
    expect(text).toContain(
      'Defines topics the assistant may or may not address for the new version of the Scout.'
    );
    expect(text).toContain(
      'Sets the communication tone used by the new version of the Scout.'
    );
    expect(text).toContain(
      'Controls response conciseness for the new version of the Scout.'
    );
    expect(text).toContain(
      'Optional opening message for the first turn in the new version of the Scout. Leave blank if your inbox already sends an automated greeting.'
    );
  });

  it('7. renders Portuguese text from pt_BR/scout.json when locale is switched to pt_BR', async () => {
    i18n.global.locale.value = 'pt_BR';
    const wrapper = mountComponent();

    expect(wrapper.text()).toContain('Nova versão do Scout');
    expect(wrapper.text()).toContain('Papel e Objetivo');
    expect(wrapper.text()).toContain('Escopo e Limites');
    expect(wrapper.text()).toContain('Tom de Voz');
    expect(wrapper.text()).toContain('Tamanho da Resposta');
    expect(wrapper.text()).toContain('Saudação Inicial');

    const selects = wrapper.findAll('select');
    const toneOptionTexts = selects[0].findAll('option').map(o => o.text());
    expect(toneOptionTexts).toEqual([
      'Amigável',
      'Neutro',
      'Direto ao ponto',
      'Profissional',
      'Bem-humorado',
    ]);

    const lengthOptionTexts = selects[1].findAll('option').map(o => o.text());
    expect(lengthOptionTexts).toEqual(['Conciso', 'Padrão', 'Detalhado']);

    expect(wrapper.text()).toContain(
      'Mensagem de abertura opcional para a primeira resposta na nova versão do Scout. Deixe em branco se a caixa de entrada já enviar sua própria saudação.'
    );
  });
});
