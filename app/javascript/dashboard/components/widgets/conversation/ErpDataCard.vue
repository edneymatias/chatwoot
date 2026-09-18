<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFunctionGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpAPI from 'dashboard/api/integrations/erp';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
  contact: {
    type: Object,
    default: () => ({}),
  },
});

const { locale } = useI18n();
const currentLocale = computed(() => {
  const loc = locale?.value || 'pt_BR';
  return loc.replace('_', '-');
});

const storeContact = useFunctionGetter(
  'contacts/getContact',
  () => props.contactId
);

const activeContact = computed(() => {
  if (props.contact && Object.keys(props.contact).length > 0) {
    return props.contact;
  }
  return storeContact.value || {};
});

const status = ref('loading');
const loading = ref(false);
const error = ref('');
const customerData = ref(null);
const multipleMatches = ref(false);

let currentRequestId = 0;

const WHITELIST_FIELDS = [
  {
    key: 'nmPessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_PESSOA',
  },
  {
    key: 'nrCpfcnpjpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_CPFCNPJPESSOA',
    mask: 'cpf_cnpj',
  },
  {
    key: 'nrRgpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_RGPESSOA',
  },
  {
    key: 'nmEndpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_ENDPESSOA',
  },
  {
    key: 'nrEndpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_ENDPESSOA',
  },
  {
    key: 'compEndpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.COMP_ENDPESSOA',
  },
  {
    key: 'nmBaipessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_BAIPESSOA',
  },
  {
    key: 'nmCidpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_CIDPESSOA',
  },
  {
    key: 'ufEndpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.UF_ENDPESSOA',
  },
  {
    key: 'nrCeppessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_CEPPESSOA',
    mask: 'cep',
  },
  {
    key: 'nrTelrespessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELRESPESSOA',
    mask: 'phone',
  },
  {
    key: 'nrTelcelpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELCELPESSOA',
    mask: 'phone',
  },
  {
    key: 'nrTelcompessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELCOMPESSOA',
    mask: 'phone',
  },
  {
    key: 'emailPessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.EMAIL_PESSOA',
  },
  {
    key: 'tpSxpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.TP_SXPESSOA',
  },
  {
    key: 'dtNascpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.DT_NASCPESSOA',
    mask: 'date',
  },
  {
    key: 'nmNacpessoa',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NM_NACPESSOA',
  },
  {
    key: 'dsConvenio',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.DS_CONVENIO',
  },
  {
    key: 'nrConvenio',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_CONVENIO',
  },
  { key: 'nrFicha', labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_FICHA' },
  {
    key: 'dsProfissao',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.DS_PROFISSAO',
  },
  {
    key: 'descricaoOrigem',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.DESCRICAO_ORIGEM',
  },
];

const maskCpfCnpj = val => {
  if (!val) return '';
  const digits = String(val).replace(/\D/g, '');
  if (digits.length === 11) {
    return digits.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4');
  }
  if (digits.length === 14) {
    return digits.replace(
      /(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/,
      '$1.$2.$3/$4-$5'
    );
  }
  return String(val);
};

const maskCep = val => {
  if (!val) return '';
  const digits = String(val).replace(/\D/g, '');
  if (digits.length === 8) {
    return digits.replace(/(\d{5})(\d{3})/, '$1-$2');
  }
  return String(val);
};

const maskPhone = val => {
  if (!val) return '';
  let digits = String(val).replace(/\D/g, '');
  if (digits.startsWith('55') && digits.length >= 12) {
    digits = digits.slice(2);
  }
  if (digits.length === 11) {
    return digits.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  }
  if (digits.length === 10) {
    return digits.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
  }
  return String(val);
};

const formatDateWithoutTime = val => {
  if (!val) return '-';
  const str = String(val).trim();
  const match = str.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (match) {
    const [, year, month, day] = match;
    const date = new Date(Number(year), Number(month) - 1, Number(day));
    return new Intl.DateTimeFormat(currentLocale.value, {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    }).format(date);
  }
  const date = new Date(str);
  if (Number.isNaN(date.getTime())) return str;
  return new Intl.DateTimeFormat(currentLocale.value, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(date);
};

const formatDateTime = val => {
  if (!val) return '-';
  const date = new Date(val);
  if (Number.isNaN(date.getTime())) return String(val);
  return new Intl.DateTimeFormat(currentLocale.value, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
};

const formatCurrency = val => {
  if (val === null || val === undefined || val === '') return '-';
  const num = Number(val);
  if (Number.isNaN(num)) return String(val);
  return new Intl.NumberFormat(currentLocale.value, {
    style: 'currency',
    currency: 'BRL',
  }).format(num);
};
const isBirthdayToday = computed(() => {
  const dtNasc = customerData.value?.dtNascpessoa;
  if (!dtNasc) return false;
  const str = String(dtNasc).trim();
  const match = str.match(/^(\d{4})-(\d{2})-(\d{2})/);
  const today = new Date();
  const todayMonth = today.getMonth() + 1;
  const todayDay = today.getDate();

  if (match) {
    const birthMonth = Number(match[2]);
    const birthDay = Number(match[3]);

    if (birthMonth === 2 && birthDay === 29) {
      const isCurrentYearLeap =
        new Date(today.getFullYear(), 1, 29).getMonth() === 1;
      if (!isCurrentYearLeap) {
        return todayMonth === 2 && todayDay === 28;
      }
    }
    return birthMonth === todayMonth && birthDay === todayDay;
  }
  return false;
});

const customerAttributes = computed(() => {
  if (!customerData.value) return [];
  const results = [];
  WHITELIST_FIELDS.forEach(field => {
    const rawVal = customerData.value[field.key];
    if (rawVal === null || rawVal === undefined) return;
    const strVal = String(rawVal).trim();
    if (strVal.length === 0) return;

    let formattedValue = strVal;
    if (field.mask === 'cpf_cnpj') {
      formattedValue = maskCpfCnpj(rawVal);
    } else if (field.mask === 'cep') {
      formattedValue = maskCep(rawVal);
    } else if (field.mask === 'phone') {
      formattedValue = maskPhone(rawVal);
    } else if (field.mask === 'date') {
      formattedValue = formatDateWithoutTime(rawVal);
    }

    results.push({
      key: field.key,
      labelKey: field.labelKey,
      value: formattedValue,
    });
  });
  return results;
});

const fetchErpData = async () => {
  const phone = activeContact.value?.phone_number;

  if (!phone || !String(phone).trim()) {
    status.value = 'no_phone';
    loading.value = false;
    return;
  }
  currentRequestId += 1;
  const requestId = currentRequestId;
  const activeId = props.contactId;

  try {
    status.value = 'loading';
    loading.value = true;
    error.value = '';

    const response = await ErpAPI.get(props.contactId);

    if (requestId !== currentRequestId || activeId !== props.contactId) {
      return;
    }

    if (response.data?.status === 'found') {
      customerData.value = response.data.data || {};
      multipleMatches.value = Boolean(response.data.multiple_matches);
      status.value = 'found';
    } else {
      customerData.value = null;
      status.value = 'not_found';
    }
  } catch (err) {
    if (requestId !== currentRequestId || activeId !== props.contactId) {
      return;
    }
    status.value = 'error';
    error.value = err.response?.data?.error || '';
  } finally {
    if (requestId === currentRequestId && activeId === props.contactId) {
      loading.value = false;
    }
  }
};

watch(
  [() => props.contactId, () => activeContact.value?.phone_number],
  ([newContactId, newPhone], [oldContactId, oldPhone] = []) => {
    if (newContactId !== oldContactId || newPhone !== oldPhone) {
      fetchErpData();
    }
  },
  { immediate: true }
);

defineExpose({
  fetchErpData,
});
</script>

<template>
  <div class="px-4 py-2 text-n-slate-12">
    <!-- Loading spinner -->
    <div
      v-if="status === 'loading'"
      data-testid="erp-loading-spinner"
      class="flex flex-col items-center justify-center py-6 gap-2 text-n-slate-11"
    >
      <Spinner :size="24" class="text-n-brand" />
      <span class="text-xs">
        {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.LOADING') }}
      </span>
    </div>

    <!-- Missing phone empty state -->
    <div
      v-else-if="status === 'no_phone'"
      data-testid="erp-no-phone-state"
      class="p-4 text-center text-xs text-n-slate-11"
    >
      {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.NO_PHONE') }}
    </div>

    <!-- Not found in ERP empty state -->
    <div
      v-else-if="status === 'not_found'"
      data-testid="erp-not-found-state"
      class="p-4 text-center"
    >
      <p class="text-sm font-medium text-n-slate-12 mb-1">
        {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.NOT_FOUND_TITLE') }}
      </p>
      <p class="text-xs text-n-slate-11 mb-0">
        {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.NOT_FOUND_DESC') }}
      </p>
    </div>

    <!-- Error state -->
    <div
      v-else-if="status === 'error'"
      data-testid="erp-error-state"
      class="p-4 text-center"
    >
      <p class="text-sm font-medium text-n-ruby-11 mb-1">
        {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.ERROR_TITLE') }}
      </p>
      <p class="text-xs text-n-slate-11 mb-3">
        {{ error || $t('CONVERSATION_SIDEBAR.ERP_DATA.ERROR_DESC') }}
      </p>
      <woot-button
        data-testid="erp-retry-button"
        size="small"
        variant="hollow"
        color-scheme="secondary"
        @click="fetchErpData"
      >
        {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.RETRY_BUTTON') }}
      </woot-button>
    </div>

    <!-- Found customer data -->
    <div
      v-else-if="status === 'found' && customerData"
      data-testid="erp-found-data"
      class="py-1"
    >
      <!-- Multiple matches badge -->
      <div
        v-if="multipleMatches"
        data-testid="erp-multiple-matches-badge"
        class="mb-3 px-2 py-1.5 rounded bg-n-amber-3 border border-n-amber-6 text-xs text-n-amber-11 flex items-center gap-1.5"
      >
        <fluent-icon icon="info" size="14" class="flex-shrink-0" />
        <span>
          {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.MULTIPLE_MATCHES_BADGE') }}
        </span>
      </div>

      <!-- Birthday badge -->
      <div
        v-if="isBirthdayToday"
        data-testid="erp-birthday-badge"
        class="mb-3 px-2 py-1 rounded bg-n-brand/10 border border-n-brand/20 text-xs font-semibold text-n-brand flex items-center justify-center gap-1"
      >
        <span>{{ $t('CONVERSATION_SIDEBAR.ERP_DATA.BIRTHDAY_BADGE') }}</span>
      </div>

      <!-- Curated whitelisted personal attributes aligned by ':' -->
      <div class="flex flex-col divide-y divide-n-weak">
        <div
          v-for="attr in customerAttributes"
          :key="attr.key"
          data-testid="erp-attribute-row"
          class="grid grid-cols-[1fr_auto_1fr] items-baseline gap-2 py-1.5 text-xs"
        >
          <span
            class="font-medium text-n-slate-11 text-right truncate"
            :title="$t(attr.labelKey)"
          >
            {{ $t(attr.labelKey) }}
          </span>
          <span class="text-n-slate-10 select-none font-semibold">:</span>
          <span class="text-n-slate-12 break-all text-left">
            {{ attr.value }}
          </span>
        </div>
      </div>

      <!-- Structured Appointments Section (atendimentos) -->
      <div
        v-if="customerData.atendimentos"
        data-testid="erp-appointments-section"
        class="mt-4 pt-3 border-t border-n-weak"
      >
        <h4 class="text-xs font-semibold text-n-slate-12 mb-2">
          {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.TITLE') }}
        </h4>

        <!-- Last appointment -->
        <div
          class="p-2 mb-2 rounded bg-n-alpha-1 border border-n-weak text-xs flex flex-col gap-1"
        >
          <span class="font-medium text-n-slate-11">
            {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.LAST_VISIT') }}
          </span>
          <template v-if="customerData.atendimentos.ultimo">
            <div class="flex justify-between text-n-slate-12">
              <span>{{
                formatDateTime(customerData.atendimentos.ultimo.dataHora)
              }}</span>
              <span class="text-n-slate-11">
                {{
                  customerData.atendimentos.ultimo.compareceu
                    ? $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.ATTENDED')
                    : $t(
                        'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.DID_NOT_ATTEND'
                      )
                }}
              </span>
            </div>
            <div
              v-if="customerData.atendimentos.ultimo.comQuem"
              class="text-n-slate-11"
            >
              <span
                >{{
                  $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.PROFESSIONAL')
                }}{{ ': ' }}</span
              >
              <span class="text-n-slate-12">{{
                customerData.atendimentos.ultimo.comQuem
              }}</span>
            </div>
          </template>
          <span v-else class="text-n-slate-10">
            {{
              $t(
                'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NO_PAST_APPOINTMENTS'
              )
            }}
          </span>
        </div>

        <!-- Next appointment -->
        <div
          class="p-2 rounded bg-n-alpha-1 border border-n-weak text-xs flex flex-col gap-1"
        >
          <div class="flex items-center justify-between">
            <span class="font-medium text-n-slate-11">
              {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NEXT_VISIT') }}
            </span>
            <template v-if="customerData.atendimentos.proximo">
              <span
                v-if="customerData.atendimentos.proximo.confirmado"
                data-testid="erp-appointment-confirmed-badge"
                class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-teal-3 text-n-teal-11 border border-n-teal-6"
              >
                {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.CONFIRMED') }}
              </span>
              <span
                v-else
                class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-slate-3 text-n-slate-11"
              >
                {{
                  $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NOT_CONFIRMED')
                }}
              </span>
            </template>
          </div>
          <template v-if="customerData.atendimentos.proximo">
            <div class="text-n-slate-12">
              {{ formatDateTime(customerData.atendimentos.proximo.dataHora) }}
            </div>
            <div
              v-if="customerData.atendimentos.proximo.comQuem"
              class="text-n-slate-11"
            >
              <span
                >{{
                  $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.PROFESSIONAL')
                }}{{ ': ' }}</span
              >
              <span class="text-n-slate-12">{{
                customerData.atendimentos.proximo.comQuem
              }}</span>
            </div>
          </template>
          <span v-else class="text-n-slate-10">
            {{
              $t(
                'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NO_FUTURE_APPOINTMENTS'
              )
            }}
          </span>
        </div>
      </div>

      <!-- Structured Financial Section (financeiro) -->
      <div
        v-if="customerData.financeiro"
        data-testid="erp-financial-section"
        class="mt-4 pt-3 border-t border-n-weak"
      >
        <div class="flex items-center justify-between mb-2">
          <h4 class="text-xs font-semibold text-n-slate-12">
            {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.TITLE') }}
          </h4>
          <span
            v-if="customerData.financeiro.devedor"
            data-testid="erp-debtor-badge"
            class="px-2 py-0.5 rounded text-xs font-semibold bg-n-ruby-3 text-n-ruby-11 border border-n-ruby-6 flex items-center gap-1"
          >
            {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.DEBTOR_BADGE') }}
          </span>
        </div>

        <!-- Oldest overdue installment -->
        <div
          v-if="customerData.financeiro.parcelaVencida"
          data-testid="erp-oldest-overdue-installment"
          class="p-2 mb-2 rounded bg-n-ruby-2 border border-n-ruby-4 text-xs flex flex-col gap-1"
        >
          <span class="font-medium text-n-ruby-11">
            {{
              $t(
                'CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.OLDEST_OVERDUE_INSTALLMENT'
              )
            }}
          </span>
          <div class="flex justify-between text-n-slate-11">
            <span
              >{{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.DUE_DATE')
              }}{{ ':' }}</span
            >
            <span class="text-n-slate-12 font-medium">
              {{
                formatDateWithoutTime(
                  customerData.financeiro.parcelaVencida.dtVencimento
                )
              }}
            </span>
          </div>
          <div class="flex justify-between text-n-slate-11">
            <span
              >{{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.ORIGINAL_VALUE')
              }}{{ ':' }}</span
            >
            <span>{{
              formatCurrency(customerData.financeiro.parcelaVencida.valor)
            }}</span>
          </div>
          <div class="flex justify-between text-n-slate-11">
            <span
              >{{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.CORRECTED_VALUE')
              }}{{ ':' }}</span
            >
            <span class="font-semibold text-n-ruby-11">
              {{
                formatCurrency(
                  customerData.financeiro.parcelaVencida.valorCorrigido ||
                    customerData.financeiro.parcelaVencida.valor
                )
              }}
            </span>
          </div>
        </div>
        <div v-else class="text-xs text-n-slate-11 mb-2">
          <span
            >{{
              $t(
                'CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.OLDEST_OVERDUE_INSTALLMENT'
              )
            }}{{ ': ' }}</span
          >
          <span class="text-n-slate-10">
            {{
              $t(
                'CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.NO_OVERDUE_INSTALLMENTS'
              )
            }}
          </span>
        </div>

        <!-- Next installment -->
        <div
          v-if="customerData.financeiro.proximaParcela"
          class="p-2 mb-2 rounded bg-n-alpha-1 border border-n-weak text-xs flex flex-col gap-1"
        >
          <span class="font-medium text-n-slate-12">
            {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.NEXT_INSTALLMENT') }}
          </span>
          <div class="flex justify-between text-n-slate-11">
            <span
              >{{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.DUE_DATE')
              }}{{ ':' }}</span
            >
            <span class="text-n-slate-12">
              {{
                formatDateWithoutTime(
                  customerData.financeiro.proximaParcela.dtVencimento
                )
              }}
            </span>
          </div>
          <div class="flex justify-between text-n-slate-11">
            <span
              >{{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.ORIGINAL_VALUE')
              }}{{ ':' }}</span
            >
            <span class="text-n-slate-12 font-medium">
              {{ formatCurrency(customerData.financeiro.proximaParcela.valor) }}
            </span>
          </div>
        </div>

        <!-- Totals summary -->
        <div class="grid grid-cols-2 gap-1.5 pt-1 text-xs">
          <div
            v-if="customerData.financeiro.totalFinanceiro !== undefined"
            class="p-1.5 rounded bg-n-alpha-1 border border-n-weak flex flex-col"
          >
            <span class="text-[10px] text-n-slate-10 truncate">
              {{
                $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.TOTAL_FINANCIAL')
              }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ formatCurrency(customerData.financeiro.totalFinanceiro) }}
            </span>
          </div>
          <div
            v-if="customerData.financeiro.totalRecebido !== undefined"
            class="p-1.5 rounded bg-n-alpha-1 border border-n-weak flex flex-col"
          >
            <span class="text-[10px] text-n-slate-10 truncate">
              {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.TOTAL_RECEIVED') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ formatCurrency(customerData.financeiro.totalRecebido) }}
            </span>
          </div>
          <div
            v-if="customerData.financeiro.totalAberto !== undefined"
            class="p-1.5 rounded bg-n-alpha-1 border border-n-weak flex flex-col"
          >
            <span class="text-[10px] text-n-slate-10 truncate">
              {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.TOTAL_OPEN') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ formatCurrency(customerData.financeiro.totalAberto) }}
            </span>
          </div>
          <div
            v-if="customerData.financeiro.totalDevedor !== undefined"
            class="p-1.5 rounded bg-n-alpha-1 border border-n-weak flex flex-col"
          >
            <span class="text-[10px] text-n-slate-10 truncate">
              {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FINANCIAL.TOTAL_OVERDUE') }}
            </span>
            <span
              class="font-medium"
              :class="
                Number(customerData.financeiro.totalDevedor) > 0
                  ? 'text-n-ruby-11'
                  : 'text-n-slate-12'
              "
            >
              {{ formatCurrency(customerData.financeiro.totalDevedor) }}
            </span>
          </div>
        </div>
      </div>

      <!-- Audit Footnotes -->
      <div
        v-if="customerData.dtCadpessoa || customerData.dtUltaltpessoa"
        data-testid="erp-audit-footnotes"
        class="mt-4 pt-2 border-t border-n-weak text-[10px] text-n-slate-10 italic flex flex-col gap-0.5"
      >
        <span v-if="customerData.dtCadpessoa">
          {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FOOTNOTES.CREATED_AT') }}{{ ': '
          }}{{ formatDateTime(customerData.dtCadpessoa) }}
        </span>
        <span v-if="customerData.dtUltaltpessoa">
          {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FOOTNOTES.UPDATED_AT') }}{{ ': '
          }}{{ formatDateTime(customerData.dtUltaltpessoa) }}
        </span>
      </div>
    </div>
  </div>
</template>
