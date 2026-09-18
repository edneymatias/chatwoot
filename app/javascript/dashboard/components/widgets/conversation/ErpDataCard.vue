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
    key: 'address',
    labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.ADDRESS',
  },
  {
    key: 'phones',
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

const formatAddress = data => {
  if (!data) return null;
  const logradouro = (data.nmEndpessoa || '').trim();
  const numero = (data.nrEndpessoa || '').trim();
  const complemento = (data.compEndpessoa || '').trim();
  const bairro = (data.nmBaipessoa || '').trim();
  const cidade = (data.nmCidpessoa || '').trim();
  const uf = (data.ufEndpessoa || '').trim();
  const cep = (data.nrCeppessoa || '').trim();

  const streetSegment = [logradouro, numero, complemento]
    .filter(Boolean)
    .join(', ');

  const neighborhoodSegment = bairro;

  let cityStateSegment = '';
  if (cidade && uf) {
    cityStateSegment = `${cidade}/${uf}`;
  } else if (cidade) {
    cityStateSegment = cidade;
  } else if (uf) {
    cityStateSegment = uf;
  }

  const locationPrefix = [streetSegment, neighborhoodSegment, cityStateSegment]
    .filter(Boolean)
    .join(', ');

  const postalCodeSegment = cep ? maskCep(cep) : '';

  if (locationPrefix && postalCodeSegment) {
    return `${locationPrefix} - ${postalCodeSegment}`;
  }
  if (locationPrefix) {
    return locationPrefix;
  }
  if (postalCodeSegment) {
    return postalCodeSegment;
  }
  return null;
};

const isPhonesExpanded = ref(false);

const resolvedPhones = computed(() => {
  if (!customerData.value) {
    return {
      primaryPhone: null,
      secondaryPhones: [],
      hasMultiplePhones: false,
    };
  }

  const phoneKeys = [
    {
      key: 'nrTelcelpessoa',
      labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELCELPESSOA',
    },
    {
      key: 'nrTelrespessoa',
      labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELRESPESSOA',
    },
    {
      key: 'nrTelcompessoa',
      labelKey: 'CONVERSATION_SIDEBAR.ERP_DATA.FIELDS.NR_TELCOMPESSOA',
    },
  ];

  const available = [];
  phoneKeys.forEach(p => {
    const raw = customerData.value[p.key];
    if (raw !== null && raw !== undefined) {
      const str = String(raw).trim();
      if (str.length > 0) {
        available.push({
          key: p.key,
          labelKey: p.labelKey,
          rawValue: str,
          formattedValue: maskPhone(str),
        });
      }
    }
  });

  const primary = available.length > 0 ? available[0] : null;
  const secondary = available.length > 1 ? available.slice(1) : [];

  return {
    primaryPhone: primary,
    secondaryPhones: secondary,
    hasMultiplePhones: secondary.length > 0,
  };
});

const primaryPhone = computed(() => resolvedPhones.value.primaryPhone);
const secondaryPhones = computed(() => resolvedPhones.value.secondaryPhones);
const hasMultiplePhones = computed(
  () => resolvedPhones.value.hasMultiplePhones
);
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
    if (field.key === 'address') {
      const formattedAddress = formatAddress(customerData.value);
      if (formattedAddress) {
        results.push({
          key: 'address',
          labelKey: field.labelKey,
          value: formattedAddress,
        });
      }
      return;
    }
    if (field.key === 'phones') {
      if (primaryPhone.value) {
        results.push({
          key: 'phones',
        });
      }
      return;
    }
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
    if (newContactId !== oldContactId) {
      isPhonesExpanded.value = false;
    }
    if (newContactId !== oldContactId || newPhone !== oldPhone) {
      fetchErpData();
    }
  },
  { immediate: true }
);

defineExpose({
  fetchErpData,
  formatAddress,
  primaryPhone,
  secondaryPhones,
  hasMultiplePhones,
  isPhonesExpanded,
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
        <template v-for="attr in customerAttributes" :key="attr.key">
          <!-- Primary and expandable secondary phones -->
          <template v-if="attr.key === 'phones'">
            <div
              v-if="primaryPhone"
              data-testid="erp-primary-phone-row"
              class="grid grid-cols-[1fr_auto_1fr] items-baseline gap-2 py-1.5 text-xs"
            >
              <span
                class="font-medium text-n-slate-11 text-right truncate"
                :title="$t(primaryPhone.labelKey)"
              >
                {{ $t(primaryPhone.labelKey) }}
              </span>
              <span class="text-n-slate-10 select-none font-semibold">:</span>
              <div
                class="flex items-center gap-1.5 text-left text-n-slate-12 break-all"
              >
                <span>{{ primaryPhone.formattedValue }}</span>
                <button
                  v-if="hasMultiplePhones"
                  type="button"
                  data-testid="erp-phone-expand-toggle"
                  :title="
                    isPhonesExpanded
                      ? $t('CONVERSATION_SIDEBAR.ERP_DATA.PHONE_TOGGLE_LESS')
                      : $t('CONVERSATION_SIDEBAR.ERP_DATA.PHONE_TOGGLE_MORE')
                  "
                  class="inline-flex items-center justify-center px-1 py-0.5 text-[10px] font-bold leading-none rounded hover:bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12 cursor-pointer select-none"
                  @click="isPhonesExpanded = !isPhonesExpanded"
                >
                  ...
                </button>
              </div>
            </div>

            <!-- Secondary phones inline accordion -->
            <template v-if="isPhonesExpanded">
              <div
                v-for="sec in secondaryPhones"
                :key="sec.key"
                data-testid="erp-secondary-phone-row"
                class="grid grid-cols-[1fr_auto_1fr] items-baseline gap-2 py-1.5 text-xs"
              >
                <span
                  class="font-medium text-n-slate-11 text-right truncate"
                  :title="$t(sec.labelKey)"
                >
                  {{ $t(sec.labelKey) }}
                </span>
                <span class="text-n-slate-10 select-none font-semibold">:</span>
                <span class="text-n-slate-12 break-all text-left">
                  {{ sec.formattedValue }}
                </span>
              </div>
            </template>
          </template>

          <!-- Standard personal attributes -->
          <div
            v-else
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
        </template>
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

        <div class="flex flex-col divide-y divide-n-weak">
          <!-- Last appointment -->
          <div
            data-testid="erp-appointment-ultimo"
            class="py-2 text-xs flex flex-col gap-1"
          >
            <div class="flex items-center justify-between">
              <span class="font-medium text-n-slate-11">
                {{
                  $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.LAST_VISIT')
                }}
              </span>
              <template v-if="customerData.atendimentos.ultimo">
                <span
                  class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-slate-3 text-n-slate-11"
                >
                  {{
                    customerData.atendimentos.ultimo.compareceu
                      ? $t(
                          'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.ATTENDED'
                        )
                      : $t(
                          'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.DID_NOT_ATTEND'
                        )
                  }}
                </span>
              </template>
            </div>
            <template v-if="customerData.atendimentos.ultimo">
              <div class="text-n-slate-12">
                {{
                  formatDateTime(
                    customerData.atendimentos.ultimo.quando ||
                      customerData.atendimentos.ultimo.dataHora ||
                      customerData.atendimentos.ultimo.data
                  )
                }}
              </div>
              <div
                v-if="customerData.atendimentos.ultimo.comQuem"
                class="text-n-slate-11"
              >
                <span>
                  {{
                    $t(
                      'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.PROFESSIONAL'
                    )
                  }}:
                </span>
                <span class="text-n-slate-12">
                  {{ customerData.atendimentos.ultimo.comQuem }}
                </span>
              </div>
            </template>
            <span v-else class="text-n-slate-10 italic">
              {{
                $t(
                  'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NO_PAST_APPOINTMENTS'
                )
              }}
            </span>
          </div>

          <!-- Next appointment -->
          <div
            data-testid="erp-appointment-proximo"
            class="py-2 text-xs flex flex-col gap-1"
          >
            <div class="flex items-center justify-between">
              <span class="font-medium text-n-slate-11">
                {{
                  $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NEXT_VISIT')
                }}
              </span>
              <template v-if="customerData.atendimentos.proximo">
                <span
                  v-if="customerData.atendimentos.proximo.confirmado"
                  data-testid="erp-appointment-confirmed-badge"
                  class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-teal-3 text-n-teal-11 border border-n-teal-6"
                >
                  {{
                    $t('CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.CONFIRMED')
                  }}
                </span>
                <span
                  v-else
                  class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-n-slate-3 text-n-slate-11"
                >
                  {{
                    $t(
                      'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NOT_CONFIRMED'
                    )
                  }}
                </span>
              </template>
            </div>
            <template v-if="customerData.atendimentos.proximo">
              <div class="text-n-slate-12">
                {{
                  formatDateTime(
                    customerData.atendimentos.proximo.quando ||
                      customerData.atendimentos.proximo.dataHora ||
                      customerData.atendimentos.proximo.data
                  )
                }}
              </div>
              <div
                v-if="customerData.atendimentos.proximo.comQuem"
                class="text-n-slate-11"
              >
                <span>
                  {{
                    $t(
                      'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.PROFESSIONAL'
                    )
                  }}:
                </span>
                <span class="text-n-slate-12">
                  {{ customerData.atendimentos.proximo.comQuem }}
                </span>
              </div>
            </template>
            <span v-else class="text-n-slate-10 italic">
              {{
                $t(
                  'CONVERSATION_SIDEBAR.ERP_DATA.APPOINTMENTS.NO_FUTURE_APPOINTMENTS'
                )
              }}
            </span>
          </div>
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
                  customerData.financeiro.parcelaVencida.data ||
                    customerData.financeiro.parcelaVencida.dtVencimento ||
                    customerData.financeiro.parcelaVencida.dtVencimentoparcela
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
                  customerData.financeiro.proximaParcela.data ||
                    customerData.financeiro.proximaParcela.dtVencimento ||
                    customerData.financeiro.proximaParcela.dtVencimentoparcela
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
        class="mt-4 pt-2 border-t border-n-weak text-center text-[10px] text-n-slate-10 italic leading-normal"
      >
        <span
          v-if="customerData.dtCadpessoa"
          data-testid="erp-audit-created-at"
        >
          {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FOOTNOTES.CREATED_AT') }}:
          {{ formatDateTime(customerData.dtCadpessoa) }}
        </span>
        <span
          v-if="customerData.dtCadpessoa && customerData.dtUltaltpessoa"
          data-testid="erp-audit-separator"
          class="mx-1 select-none"
        >
          •
        </span>
        <span
          v-if="customerData.dtUltaltpessoa"
          data-testid="erp-audit-updated-at"
        >
          {{ $t('CONVERSATION_SIDEBAR.ERP_DATA.FOOTNOTES.UPDATED_AT') }}:
          {{ formatDateTime(customerData.dtUltaltpessoa) }}
        </span>
      </div>
    </div>
  </div>
</template>
