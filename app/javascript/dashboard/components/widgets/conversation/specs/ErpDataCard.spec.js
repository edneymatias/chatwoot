import { vi, describe, it, expect, beforeEach } from 'vitest';
import { config, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ErpDataCard from '../ErpDataCard.vue';
import ErpAPI from 'dashboard/api/integrations/erp';
import enMessages from 'dashboard/i18n/locale/en/conversation.json';
import ptBrMessages from 'dashboard/i18n/locale/pt_BR/conversation.json';

withFullI18n('pt_BR');

vi.mock('dashboard/api/integrations/erp', () => ({
  default: {
    get: vi.fn(),
  },
}));

config.global.stubs = {
  ...config.global.stubs,
  WootButton: true,
  FluentIcon: true,
};

describe('ErpDataCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // T017: Whitelist filtering and friendly labels
  describe('Whitelist filtering and friendly labels (T017, FR-015, FR-016, FR-017)', () => {
    it('strictly excludes 21 technical keys verbatim from rendering', async () => {
      const technicalKeysPayload = {
        nmPessoa: 'Maria Silva',
        idPessoa: 98421,
        idEmpresa: 1,
        pessoaTipo: 'F',
        tpPessoa: 'F',
        nmPaispessoa: 'Brasil',
        idProfpessoa: 12,
        idUsuario: 34,
        idEspecpessoa: 56,
        dtUltacesso: '2026-09-01T10:00:00',
        stTermo: 1,
        stCadastro: 'A',
        stPessoa: 'A',
        idConvenio: 99,
        nmConvenio: 'Convenio X',
        idPerfil: 3,
        observacoes: 'Obs interna',
        origemPessoa: 'Web',
        nrConselho: '12345',
        siglaConselho: 'CRM',
        ufConselho: 'PR',
        indClientePadrao: 0,
      };

      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: technicalKeysPayload,
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const text = wrapper.text();
      const technicalKeys = [
        'idPessoa',
        'idEmpresa',
        'pessoaTipo',
        'tpPessoa',
        'nmPaispessoa',
        'idProfpessoa',
        'idUsuario',
        'idEspecpessoa',
        'dtUltacesso',
        'stTermo',
        'stCadastro',
        'stPessoa',
        'idConvenio',
        'nmConvenio',
        'idPerfil',
        'observacoes',
        'origemPessoa',
        'nrConselho',
        'siglaConselho',
        'ufConselho',
        'indClientePadrao',
      ];

      technicalKeys.forEach(key => {
        expect(text).not.toContain(key);
      });

      // Renders whitelisted name
      expect(text).toContain('Nome');
      expect(text).toContain('Maria Silva');
    });

    it('suppresses unmapped extra fields per strict whitelist policy', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            unmappedInternalField: 'should-not-render',
            randomExtraKey: 'hidden-value',
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const text = wrapper.text();
      expect(text).not.toContain('unmappedInternalField');
      expect(text).not.toContain('should-not-render');
      expect(text).not.toContain('randomExtraKey');
      expect(text).not.toContain('hidden-value');
    });

    it('renders nrFicha with friendly label Prontuário and positions nrRgpessoa immediately adjacent to nrCpfcnpjpessoa', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nrCpfcnpjpessoa: '12345678900',
            nrRgpessoa: '987654321',
            nrFicha: 'F-48291',
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const rows = wrapper.findAll('[data-testid="erp-attribute-row"]');
      const rowTexts = rows.map(r => r.text());

      // nrFicha labeled as Prontuário
      const fichaRow = rowTexts.find(t => t.includes('Prontuário'));
      expect(fichaRow).toBeDefined();
      expect(fichaRow).toContain('F-48291');

      // RG immediately follows CPF
      const cpfIndex = rowTexts.findIndex(t => t.includes('CPF'));
      const rgIndex = rowTexts.findIndex(t => t.includes('RG'));
      expect(cpfIndex).toBeGreaterThan(-1);
      expect(rgIndex).toBe(cpfIndex + 1);
    });

    it('omits null, undefined, and empty string attributes', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            emailPessoa: null,
            dsProfissao: '',
            compEndpessoa: '   ',
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const rows = wrapper.findAll('[data-testid="erp-attribute-row"]');
      expect(rows.length).toBe(1);
      expect(rows[0].text()).toContain('Nome');
      expect(rows[0].text()).toContain('Maria Silva');
    });
  });

  // T018: Value formatting and masks
  describe('Value formatting and masks (T018, FR-018, FR-022)', () => {
    it('applies Brazilian masks to CPF, CNPJ, CEP, and phones, with safe fallback on irregular values', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nrCpfcnpjpessoa: '12345678900', // 11 digits CPF
            nrCeppessoa: '80010000', // 8 digits CEP
            nrTelcelpessoa: '41996937898', // 11 digits mobile
            nrTelrespessoa: '4133334444', // 10 digits landline
            nrTelcompessoa: '999', // irregular
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const text = wrapper.text();
      expect(text).toContain('123.456.789-00');
      expect(text).toContain('80010-000');
      expect(text).toContain('(41) 99693-7898');
      expect(text).toContain('(41) 3333-4444');
      expect(text).toContain('999'); // Fallback to raw value
    });

    it('applies CNPJ mask when nrCpfcnpjpessoa has 14 digits', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Empresa ABC',
            nrCpfcnpjpessoa: '12345678000195',
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      expect(wrapper.text()).toContain('12.345.678/0001-95');
    });

    it('formats dtNascpessoa without time and highlights birthday badge when today is contact birthday', async () => {
      const today = new Date();
      const month = String(today.getMonth() + 1).padStart(2, '0');
      const day = String(today.getDate()).padStart(2, '0');
      const birthdayIso = `1990-${month}-${day}`;

      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            dtNascpessoa: birthdayIso,
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const birthdayBadge = wrapper.find('[data-testid="erp-birthday-badge"]');
      expect(birthdayBadge.exists()).toBe(true);
      expect(birthdayBadge.text()).toContain('🎂 Aniversariante hoje');

      // Date formatted without time
      expect(wrapper.text()).toContain(`${day}/${month}/1990`);
    });

    it('does not render birthday badge when today is not contact birthday', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            dtNascpessoa: '1990-01-01',
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      // Unless today happens to be Jan 1st, birthday badge does not show
      const today = new Date();
      if (today.getMonth() !== 0 || today.getDate() !== 1) {
        expect(
          wrapper.find('[data-testid="erp-birthday-badge"]').exists()
        ).toBe(false);
      }
    });
  });

  // T019: Structured sub-objects and footnotes
  describe('Structured sub-objects and footnotes (T019, FR-019, FR-020, FR-021)', () => {
    it('renders appointments section with ultimo, proximo, and confirmation badge', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            atendimentos: {
              ultimo: {
                dataHora: '2026-08-15T14:30:00',
                comQuem: 'Dra. Paula Oliveira',
                compareceu: true,
              },
              proximo: {
                dataHora: '2026-09-25T10:00:00',
                comQuem: 'Dr. Fernando Costa',
                confirmado: true,
              },
            },
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(
          wrapper.find('[data-testid="erp-appointments-section"]').exists()
        ).toBe(true);
      });

      const apptSection = wrapper.find(
        '[data-testid="erp-appointments-section"]'
      );
      expect(apptSection.text()).toContain('Dra. Paula Oliveira');
      expect(apptSection.text()).toContain('Dr. Fernando Costa');

      // Confirmation badge
      const confirmedBadge = apptSection.find(
        '[data-testid="erp-appointment-confirmed-badge"]'
      );
      expect(confirmedBadge.exists()).toBe(true);
      expect(confirmedBadge.text()).toContain('Confirmado');
    });

    it('renders empty indicators when appointments are null or empty', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            atendimentos: {
              ultimo: null,
              proximo: null,
            },
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(
          wrapper.find('[data-testid="erp-appointments-section"]').exists()
        ).toBe(true);
      });

      const text = wrapper
        .find('[data-testid="erp-appointments-section"]')
        .text();
      expect(text).toContain('Nenhum');
      expect(text).toContain('Nenhum agendamento futuro');
    });

    it('renders financial section with debtor badge, oldest overdue installment, and currency totals', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            financeiro: {
              devedor: true,
              parcelaVencida: {
                dtVencimento: '2026-07-10',
                valor: 250.0,
                valorCorrigido: 278.45,
              },
              proximaParcela: {
                dtVencimento: '2026-10-10',
                valor: 250.0,
              },
              totalFinanceiro: 3000.0,
              totalRecebido: 2000.0,
              totalAberto: 1000.0,
              totalDevedor: 500.0,
            },
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(
          wrapper.find('[data-testid="erp-financial-section"]').exists()
        ).toBe(true);
      });

      const finSection = wrapper.find('[data-testid="erp-financial-section"]');

      // Debtor badge
      const debtorBadge = finSection.find('[data-testid="erp-debtor-badge"]');
      expect(debtorBadge.exists()).toBe(true);
      expect(debtorBadge.text()).toContain('Devedor');

      // Oldest overdue installment
      const overdueInst = finSection.find(
        '[data-testid="erp-oldest-overdue-installment"]'
      );
      expect(overdueInst.exists()).toBe(true);
      expect(overdueInst.text()).toContain('Parcela vencida mais antiga');
      expect(overdueInst.text()).toContain('278,45');

      // Totals
      expect(finSection.text()).toContain('3.000,00');
      expect(finSection.text()).toContain('500,00');
    });

    it('renders audit footnotes in italics at the bottom of the card', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            dtCadpessoa: '2024-01-10T09:00:00',
            dtUltaltpessoa: '2026-09-01T14:20:00',
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(
          wrapper.find('[data-testid="erp-audit-footnotes"]').exists()
        ).toBe(true);
      });

      const footnotes = wrapper.find('[data-testid="erp-audit-footnotes"]');
      expect(footnotes.classes()).toContain('italic');
      expect(footnotes.text()).toContain('Data de cadastro');
      expect(footnotes.text()).toContain('Data de atualização');
      expect(footnotes.text()).toContain('10/01/2024');
      expect(footnotes.text()).toContain('01/09/2026');
    });
  });

  // T020: Card controls and lifecycle
  describe('Card controls and lifecycle (T020, SC-004, SC-005)', () => {
    it('displays loading spinner while fetching customer data from ERP', async () => {
      let resolvePromise;
      ErpAPI.get.mockReturnValue(
        new Promise(resolve => {
          resolvePromise = resolve;
        })
      );

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: {
            id: 101,
            phone_number: '+5511987654321',
          },
        },
      });

      expect(wrapper.find('[data-testid="erp-loading-spinner"]').exists()).toBe(
        true
      );

      resolvePromise({
        data: {
          status: 'found',
          data: { nmPessoa: 'Maria Silva' },
          multiple_matches: false,
        },
      });

      await vi.waitFor(() => {
        expect(
          wrapper.find('[data-testid="erp-loading-spinner"]').exists()
        ).toBe(false);
      });
    });

    it('renders multiple matches badge when multiple_matches is true', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: { nmPessoa: 'Maria Silva' },
          multiple_matches: true,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: {
            id: 101,
            phone_number: '+5511987654321',
          },
        },
      });

      await vi.waitFor(() => {
        expect(
          wrapper.find('[data-testid="erp-multiple-matches-badge"]').exists()
        ).toBe(true);
      });
    });

    it('renders error alert and retry button on API failure, and retries fetch on click', async () => {
      ErpAPI.get.mockRejectedValueOnce({
        response: {
          data: { error: 'ERP connection timed out' },
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: {
            id: 101,
            phone_number: '+5511987654321',
          },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-error-state"]').exists()).toBe(
          true
        );
      });

      expect(wrapper.text()).toContain('ERP connection timed out');
      const retryBtn = wrapper.find('[data-testid="erp-retry-button"]');
      expect(retryBtn.exists()).toBe(true);

      ErpAPI.get.mockResolvedValueOnce({
        data: {
          status: 'found',
          data: { nmPessoa: 'Maria Silva' },
          multiple_matches: false,
        },
      });

      await retryBtn.trigger('click');

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });
      expect(ErpAPI.get).toHaveBeenCalledTimes(2);
    });

    it('exposes fetchErpData for external invocation', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: { nmPessoa: 'Maria Silva' },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: {
            id: 101,
            phone_number: '+5511987654321',
          },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.vm.fetchErpData).toBeDefined();
      });

      expect(typeof wrapper.vm.fetchErpData).toBe('function');
      await wrapper.vm.fetchErpData();
      expect(ErpAPI.get).toHaveBeenCalledTimes(2);
    });

    it('discards stale in-flight responses on rapid contact switch', async () => {
      let resolveFirst;
      let resolveSecond;

      ErpAPI.get
        .mockReturnValueOnce(
          new Promise(resolve => {
            resolveFirst = resolve;
          })
        )
        .mockReturnValueOnce(
          new Promise(resolve => {
            resolveSecond = resolve;
          })
        );

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await wrapper.setProps({
        contactId: 202,
        contact: { id: 202, phone_number: '+5511999998888' },
      });

      resolveFirst({
        data: {
          status: 'found',
          data: { nmPessoa: 'Stale Contact' },
          multiple_matches: false,
        },
      });

      resolveSecond({
        data: {
          status: 'found',
          data: { nmPessoa: 'Fresh Contact' },
          multiple_matches: false,
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.text()).toContain('Fresh Contact');
      });

      expect(wrapper.text()).not.toContain('Stale Contact');
    });
  });

  // T032: Empty states
  describe('Empty states (T032, FR-012, SC-005)', () => {
    it('renders empty state for missing phone without dispatching API request', async () => {
      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: null },
        },
      });

      await vi.waitFor(() => {
        expect(
          wrapper.find('[data-testid="erp-no-phone-state"]').exists()
        ).toBe(true);
      });

      expect(ErpAPI.get).not.toHaveBeenCalled();
    });

    it('renders friendly empty state suggesting registration when contact not found in ERP', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'not_found',
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      await vi.waitFor(() => {
        expect(
          wrapper.find('[data-testid="erp-not-found-state"]').exists()
        ).toBe(true);
      });

      expect(wrapper.text()).toContain('Nenhum cliente encontrado');
    });
  });

  // T033 & T035: Localization parity
  describe('Localization parity (T033, T035, FR-014, SC-007)', () => {
    it('has identical localization keys in English and Portuguese', () => {
      const enErp = enMessages.CONVERSATION_SIDEBAR.ERP_DATA;
      const ptErp = ptBrMessages.CONVERSATION_SIDEBAR.ERP_DATA;

      expect(enErp).toBeDefined();
      expect(ptErp).toBeDefined();

      const topKeys = [
        'LOADING',
        'MULTIPLE_MATCHES_BADGE',
        'NO_PHONE',
        'NOT_FOUND_TITLE',
        'NOT_FOUND_DESC',
        'ERROR_TITLE',
        'ERROR_DESC',
        'RETRY_BUTTON',
        'REFRESH',
        'BIRTHDAY_BADGE',
        'EMPTY_VALUE',
      ];

      topKeys.forEach(k => {
        expect(enErp[k]).toBeDefined();
        expect(ptErp[k]).toBeDefined();
      });

      const fieldKeys = [
        'NM_PESSOA',
        'NR_CPFCNPJPESSOA',
        'NR_RGPESSOA',
        'NM_ENDPESSOA',
        'NR_ENDPESSOA',
        'COMP_ENDPESSOA',
        'NM_BAIPESSOA',
        'NM_CIDPESSOA',
        'UF_ENDPESSOA',
        'NR_CEPPESSOA',
        'NR_TELRESPESSOA',
        'NR_TELCELPESSOA',
        'NR_TELCOMPESSOA',
        'EMAIL_PESSOA',
        'TP_SXPESSOA',
        'DT_NASCPESSOA',
        'NM_NACPESSOA',
        'DS_CONVENIO',
        'NR_CONVENIO',
        'NR_FICHA',
        'DS_PROFISSAO',
        'DESCRICAO_ORIGEM',
      ];

      fieldKeys.forEach(k => {
        expect(enErp.FIELDS[k]).toBeDefined();
        expect(ptErp.FIELDS[k]).toBeDefined();
      });

      const apptKeys = [
        'TITLE',
        'LAST_VISIT',
        'NEXT_VISIT',
        'PROFESSIONAL',
        'ATTENDED',
        'DID_NOT_ATTEND',
        'CONFIRMED',
        'NOT_CONFIRMED',
        'NO_PAST_APPOINTMENTS',
        'NO_FUTURE_APPOINTMENTS',
      ];

      apptKeys.forEach(k => {
        expect(enErp.APPOINTMENTS[k]).toBeDefined();
        expect(ptErp.APPOINTMENTS[k]).toBeDefined();
      });

      const finKeys = [
        'TITLE',
        'DEBTOR_BADGE',
        'OLDEST_OVERDUE_INSTALLMENT',
        'NEXT_INSTALLMENT',
        'DUE_DATE',
        'ORIGINAL_VALUE',
        'CORRECTED_VALUE',
        'TOTAL_FINANCIAL',
        'TOTAL_RECEIVED',
        'TOTAL_OPEN',
        'TOTAL_OVERDUE',
        'NO_OVERDUE_INSTALLMENTS',
        'NO_NEXT_INSTALLMENT',
      ];

      finKeys.forEach(k => {
        expect(enErp.FINANCIAL[k]).toBeDefined();
        expect(ptErp.FINANCIAL[k]).toBeDefined();
      });

      const footnoteKeys = ['CREATED_AT', 'UPDATED_AT'];
      footnoteKeys.forEach(k => {
        expect(enErp.FOOTNOTES[k]).toBeDefined();
        expect(ptErp.FOOTNOTES[k]).toBeDefined();
      });
    });
  });
});
