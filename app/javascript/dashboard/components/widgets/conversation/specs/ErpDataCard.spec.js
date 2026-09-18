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
      expect(wrapper.text()).toContain('123.456.789-00');
      expect(wrapper.text()).toContain('80010-000');
      expect(wrapper.text()).toContain('(41) 99693-7898');

      const toggle = wrapper.find('[data-testid="erp-phone-expand-toggle"]');
      if (toggle.exists()) {
        await toggle.trigger('click');
      }

      const text = wrapper.text();
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
        'PHONE_TOGGLE_MORE',
        'PHONE_TOGGLE_LESS',
      ];

      topKeys.forEach(k => {
        expect(enErp[k]).toBeDefined();
        expect(ptErp[k]).toBeDefined();
      });

      const fieldKeys = [
        'ADDRESS',
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

  // Phase 2: Foundational tests (T003, T004, FR-001..FR-006)
  describe('Foundational helpers (T003, T004, FR-001..FR-006)', () => {
    it('formats address cleanly across all permutations and edge cases (T003, FR-001, FR-002, FR-003)', () => {
      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+5511987654321' },
        },
      });

      expect(typeof wrapper.vm.formatAddress).toBe('function');

      // Full address
      const full = {
        nmEndpessoa: 'Rua XV',
        nrEndpessoa: '100',
        compEndpessoa: 'Sl 4',
        nmBaipessoa: 'Centro',
        nmCidpessoa: 'Curitiba',
        ufEndpessoa: 'PR',
        nrCeppessoa: '80000000',
      };
      expect(wrapper.vm.formatAddress(full)).toBe(
        'Rua XV, 100, Sl 4, Centro, Curitiba/PR - 80000-000'
      );

      // Missing complement
      const noComp = {
        nmEndpessoa: 'Rua XV',
        nrEndpessoa: '100',
        compEndpessoa: null,
        nmBaipessoa: 'Centro',
        nmCidpessoa: 'Curitiba',
        ufEndpessoa: 'PR',
        nrCeppessoa: '80000000',
      };
      expect(wrapper.vm.formatAddress(noComp)).toBe(
        'Rua XV, 100, Centro, Curitiba/PR - 80000-000'
      );

      // City and state only
      const cityState = {
        nmCidpessoa: 'Curitiba',
        ufEndpessoa: 'PR',
      };
      expect(wrapper.vm.formatAddress(cityState)).toBe('Curitiba/PR');

      // Standalone CEP
      const cepOnly = {
        nrCeppessoa: '80000000',
      };
      expect(wrapper.vm.formatAddress(cepOnly)).toBe('80000-000');

      // Null / empty fields
      expect(wrapper.vm.formatAddress({})).toBeNull();
      expect(wrapper.vm.formatAddress(null)).toBeNull();
      expect(
        wrapper.vm.formatAddress({ nmEndpessoa: '', nrCeppessoa: '   ' })
      ).toBeNull();
    });

    it('prioritizes cell phone and tracks secondary phones and expansion state (T004, FR-004, FR-005, FR-006)', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Carlos Silva',
            nrTelcelpessoa: '11987654321',
            nrTelrespessoa: '1134567890',
            nrTelcompessoa: '1133334444',
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

      expect(wrapper.vm.primaryPhone).toBeDefined();
      expect(wrapper.vm.primaryPhone.key).toBe('nrTelcelpessoa');
      expect(wrapper.vm.primaryPhone.formattedValue).toBe('(11) 98765-4321');
      expect(wrapper.vm.secondaryPhones.length).toBe(2);
      expect(wrapper.vm.hasMultiplePhones).toBe(true);
      expect(wrapper.vm.isPhonesExpanded).toBe(false);

      // Toggle expansion
      wrapper.vm.isPhonesExpanded = true;
      expect(wrapper.vm.isPhonesExpanded).toBe(true);

      // Changing contactId resets isPhonesExpanded
      await wrapper.setProps({ contactId: 102 });
      expect(wrapper.vm.isPhonesExpanded).toBe(false);
    });

    it('falls back to residential phone when cell phone is absent (T004, FR-004)', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Carlos Silva',
            nrTelrespessoa: '1134567890',
            nrTelcompessoa: '1133334444',
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 103,
          contact: { id: 103, phone_number: '+551134567890' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      expect(wrapper.vm.primaryPhone).toBeDefined();
      expect(wrapper.vm.primaryPhone.key).toBe('nrTelrespessoa');
      expect(wrapper.vm.secondaryPhones.length).toBe(1);
      expect(wrapper.vm.secondaryPhones[0].key).toBe('nrTelcompessoa');
      expect(wrapper.vm.hasMultiplePhones).toBe(true);
    });
  });

  // Phase 3: User Story 1 - Single-Line Consolidated Address (T007, US1, FR-001, FR-002, FR-003, SC-001, SC-003)
  describe('User Story 1 - Single-Line Consolidated Address (T007, US1, FR-001, FR-002, FR-003)', () => {
    it('renders a single consolidated Endereço attribute row and strictly excludes discrete raw address rows', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nmEndpessoa: 'Rua XV de Novembro',
            nrEndpessoa: '1500',
            compEndpessoa: 'Bloco B, Ap 204',
            nmBaipessoa: 'Centro',
            nmCidpessoa: 'Curitiba',
            ufEndpessoa: 'PR',
            nrCeppessoa: '80000000',
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
      const addressRow = rows.find(r => r.text().includes('Endereço'));
      expect(addressRow).toBeDefined();
      expect(addressRow.text()).toContain(
        'Rua XV de Novembro, 1500, Bloco B, Ap 204, Centro, Curitiba/PR - 80000-000'
      );

      // Raw individual fields must NOT appear as separate rows
      const text = wrapper.text();
      expect(text).not.toContain('Logradouro');
      expect(text).not.toContain('Número');
      expect(text).not.toContain('Complemento');
      expect(text).not.toContain('Bairro');
      expect(text).not.toContain('Cidade');
      expect(text).not.toContain('UF');
      expect(text).not.toContain('CEP');
    });

    it('formats cleanly without double commas when complement is absent', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nmEndpessoa: 'Rua XV de Novembro',
            nrEndpessoa: '1500',
            compEndpessoa: null,
            nmBaipessoa: 'Centro',
            nmCidpessoa: 'Curitiba',
            ufEndpessoa: 'PR',
            nrCeppessoa: '80000000',
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
      const addressRow = rows.find(r => r.text().includes('Endereço'));
      expect(addressRow).toBeDefined();
      expect(addressRow.text()).toContain(
        'Rua XV de Novembro, 1500, Centro, Curitiba/PR - 80000-000'
      );
      expect(addressRow.text()).not.toContain(',,');
    });

    it('renders city and state only without trailing separators', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nmCidpessoa: 'Curitiba',
            ufEndpessoa: 'PR',
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
      const addressRow = rows.find(r => r.text().includes('Endereço'));
      expect(addressRow).toBeDefined();
      expect(addressRow.text()).toContain('Curitiba/PR');
      expect(addressRow.text()).not.toContain('-');
    });

    it('renders standalone CEP without leading hyphen', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nrCeppessoa: '80000000',
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
      const addressRow = rows.find(r => r.text().includes('Endereço'));
      expect(addressRow).toBeDefined();
      expect(addressRow.text()).toContain('80000-000');
      expect(addressRow.text()).not.toContain('- 80000-000');
    });

    it('omits Endereço row completely when all address fields are absent or empty', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
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
      const addressRow = rows.find(r => r.text().includes('Endereço'));
      expect(addressRow).toBeUndefined();
    });
  });

  // Phase 4: User Story 2 - Primary Phone Display with Expansion for Additional Numbers (T009, US2, FR-004, FR-005, FR-006, SC-002)
  describe('User Story 2 - Primary Phone Display with Expansion (T009, US2, FR-004, FR-005, FR-006)', () => {
    it('renders cell phone as primary with no toggle when only one phone is present', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nrTelcelpessoa: '11987654321',
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

      const primaryRow = wrapper.find('[data-testid="erp-primary-phone-row"]');
      expect(primaryRow.exists()).toBe(true);
      expect(primaryRow.text()).toContain('Celular');
      expect(primaryRow.text()).toContain('(11) 98765-4321');

      const toggle = wrapper.find('[data-testid="erp-phone-expand-toggle"]');
      expect(toggle.exists()).toBe(false);

      const secondaryRows = wrapper.findAll(
        '[data-testid="erp-secondary-phone-row"]'
      );
      expect(secondaryRows.length).toBe(0);
    });

    it('renders ellipsis toggle when multiple phones exist and expands/collapses secondary numbers inline on click', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nrTelcelpessoa: '11987654321',
            nrTelrespessoa: '1134567890',
            nrTelcompessoa: '1133334444',
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

      // Initially only primary phone is visible with toggle button
      const primaryRow = wrapper.find('[data-testid="erp-primary-phone-row"]');
      expect(primaryRow.exists()).toBe(true);
      expect(primaryRow.text()).toContain('(11) 98765-4321');

      const toggle = wrapper.find('[data-testid="erp-phone-expand-toggle"]');
      expect(toggle.exists()).toBe(true);

      // Secondary rows collapsed initially
      let secondaryRows = wrapper.findAll(
        '[data-testid="erp-secondary-phone-row"]'
      );
      expect(secondaryRows.length).toBe(0);

      // Click toggle to expand
      await toggle.trigger('click');

      secondaryRows = wrapper.findAll(
        '[data-testid="erp-secondary-phone-row"]'
      );
      expect(secondaryRows.length).toBe(2);
      expect(secondaryRows[0].text()).toContain('Telefone residencial');
      expect(secondaryRows[0].text()).toContain('(11) 3456-7890');
      expect(secondaryRows[1].text()).toContain('Telefone comercial');
      expect(secondaryRows[1].text()).toContain('(11) 3333-4444');

      // Click toggle again to collapse
      await toggle.trigger('click');
      secondaryRows = wrapper.findAll(
        '[data-testid="erp-secondary-phone-row"]'
      );
      expect(secondaryRows.length).toBe(0);
    });

    it('falls back to residential as primary phone when cell is missing and displays toggle for remaining secondary phones', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nrTelrespessoa: '1134567890',
            nrTelcompessoa: '1133334444',
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 101,
          contact: { id: 101, phone_number: '+551134567890' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const primaryRow = wrapper.find('[data-testid="erp-primary-phone-row"]');
      expect(primaryRow.exists()).toBe(true);
      expect(primaryRow.text()).toContain('Telefone residencial');
      expect(primaryRow.text()).toContain('(11) 3456-7890');

      const toggle = wrapper.find('[data-testid="erp-phone-expand-toggle"]');
      expect(toggle.exists()).toBe(true);

      await toggle.trigger('click');
      const secondaryRows = wrapper.findAll(
        '[data-testid="erp-secondary-phone-row"]'
      );
      expect(secondaryRows.length).toBe(1);
      expect(secondaryRows[0].text()).toContain('Telefone comercial');
      expect(secondaryRows[0].text()).toContain('(11) 3333-4444');
    });

    it('resets phone expansion state when contactId changes', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            nrTelcelpessoa: '11987654321',
            nrTelrespessoa: '1134567890',
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

      const toggle = wrapper.find('[data-testid="erp-phone-expand-toggle"]');
      await toggle.trigger('click');
      expect(
        wrapper.findAll('[data-testid="erp-secondary-phone-row"]').length
      ).toBe(1);

      await wrapper.setProps({ contactId: 102 });
      expect(
        wrapper.findAll('[data-testid="erp-secondary-phone-row"]').length
      ).toBe(0);
    });
  });

  // Phase 5: User Story 3 - Redesigned Appointments Presentation (T011, US3, FR-007, SC-004)
  describe('User Story 3 - Redesigned Appointments Presentation (T011, US3, FR-007)', () => {
    it('renders clean integrated list without dark container box frames', async () => {
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

      const section = wrapper.find('[data-testid="erp-appointments-section"]');

      // Removal of dark boxed container classes
      expect(section.html()).not.toContain('bg-n-alpha-1');

      // Test IDs for ultimo and proximo rows
      const ultimoRow = section.find('[data-testid="erp-appointment-ultimo"]');
      expect(ultimoRow.exists()).toBe(true);
      expect(ultimoRow.text()).toContain('Dra. Paula Oliveira');
      expect(ultimoRow.text()).toContain('Compareceu');

      const proximoRow = section.find(
        '[data-testid="erp-appointment-proximo"]'
      );
      expect(proximoRow.exists()).toBe(true);
      expect(proximoRow.text()).toContain('Dr. Fernando Costa');
      expect(proximoRow.text()).toContain('Confirmado');
      expect(
        proximoRow
          .find('[data-testid="erp-appointment-confirmed-badge"]')
          .exists()
      ).toBe(true);
    });

    it('renders subtle empty indicator when next appointment is null without empty box container', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            atendimentos: {
              ultimo: {
                dataHora: '2026-08-15T14:30:00',
                comQuem: 'Dra. Paula Oliveira',
                compareceu: false,
              },
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

      const section = wrapper.find('[data-testid="erp-appointments-section"]');
      const ultimoRow = section.find('[data-testid="erp-appointment-ultimo"]');
      expect(ultimoRow.text()).toContain('Não compareceu');

      const proximoRow = section.find(
        '[data-testid="erp-appointment-proximo"]'
      );
      expect(proximoRow.exists()).toBe(true);
      expect(proximoRow.text()).toContain('Nenhum agendamento futuro');
      expect(section.html()).not.toContain('bg-n-alpha-1');
    });

    it('omits appointments section when atendimentos is null', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            atendimentos: null,
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

      expect(
        wrapper.find('[data-testid="erp-appointments-section"]').exists()
      ).toBe(false);
    });

    it('supports "quando" field from Younus ERP for appointment date/time', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Sandro Marquetti',
            atendimentos: {
              ultimo: {
                quando: '2022-11-08T14:00:00+00:00',
                comQuem: 'Cristiano Rosa',
                compareceu: true,
              },
              proximo: null,
            },
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 129,
          contact: { id: 129, phone_number: '+5541996937898' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const ultimoRow = wrapper.find('[data-testid="erp-appointment-ultimo"]');
      expect(ultimoRow.text()).toContain('Cristiano Rosa');
      expect(ultimoRow.text()).toMatch(/08\/11\/2022/);
    });

    it('supports "data" field from Younus ERP for overdue installment due date', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Sandro Marquetti',
            financeiro: {
              devedor: true,
              parcelaVencida: {
                data: '2022-11-18T03:00:00',
                valor: 208.33,
                valorCorrigido: 309.72,
              },
              totalFinanceiro: 874.99,
              totalRecebido: 250,
              totalAberto: 624.99,
              totalDevedor: 624.99,
            },
          },
          multiple_matches: false,
        },
      });

      const wrapper = mount(ErpDataCard, {
        props: {
          contactId: 129,
          contact: { id: 129, phone_number: '+5541996937898' },
        },
      });

      await vi.waitFor(() => {
        expect(wrapper.find('[data-testid="erp-found-data"]').exists()).toBe(
          true
        );
      });

      const finSection = wrapper.find('[data-testid="erp-financial-section"]');
      expect(finSection.text()).toContain('18/11/2022');
      expect(finSection.text()).toContain('208,33');
      expect(finSection.text()).toContain('309,72');
    });
  });

  // Phase 6: User Story 4 - Centered and Responsive Registration Audit Timestamps (T013, US4, FR-008..FR-011, SC-005)
  describe('User Story 4 - Centered and Responsive Audit Footnotes (T013, US4, FR-008..FR-011)', () => {
    it('centers footer and displays bullet dot separator when both timestamps are present', async () => {
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
      expect(footnotes.classes()).toContain('text-center');

      const createdAt = footnotes.find('[data-testid="erp-audit-created-at"]');
      expect(createdAt.exists()).toBe(true);
      expect(createdAt.text()).toContain('Data de cadastro');

      const separator = footnotes.find('[data-testid="erp-audit-separator"]');
      expect(separator.exists()).toBe(true);
      expect(separator.text().trim()).toBe('•');

      const updatedAt = footnotes.find('[data-testid="erp-audit-updated-at"]');
      expect(updatedAt.exists()).toBe(true);
      expect(updatedAt.text()).toContain('Data de atualização');
    });

    it('centers single timestamp without bullet dot separator when only one timestamp is present', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            dtCadpessoa: '2024-01-10T09:00:00',
            dtUltaltpessoa: null,
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
      expect(footnotes.classes()).toContain('text-center');

      const createdAt = footnotes.find('[data-testid="erp-audit-created-at"]');
      expect(createdAt.exists()).toBe(true);

      const separator = footnotes.find('[data-testid="erp-audit-separator"]');
      expect(separator.exists()).toBe(false);

      const updatedAt = footnotes.find('[data-testid="erp-audit-updated-at"]');
      expect(updatedAt.exists()).toBe(false);
    });

    it('omits audit footnotes section completely when both timestamps are null per FR-011', async () => {
      ErpAPI.get.mockResolvedValue({
        data: {
          status: 'found',
          data: {
            nmPessoa: 'Maria Silva',
            dtCadpessoa: null,
            dtUltaltpessoa: null,
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

      expect(wrapper.find('[data-testid="erp-audit-footnotes"]').exists()).toBe(
        false
      );
    });
  });
});
