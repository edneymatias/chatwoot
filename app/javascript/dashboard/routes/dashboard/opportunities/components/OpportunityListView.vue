<script setup>
import { computed, defineComponent, h, toRef, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Spinner from 'shared/components/Spinner.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useOpportunityCardFields } from 'dashboard/composables/useOpportunityCardFields';
import { formatCurrencyAmount } from 'dashboard/constants/pipelineCurrency';
import StartOpportunityConversationButton from './StartOpportunityConversationButton.vue';

const props = defineProps({
  filters: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['rowClick']);
const store = useStore();
const allCards = computed(() => store.getters['opportunities/allCards']);
const isFetching = computed(() => store.getters['opportunities/isFetchingAll']);
const totalCount = computed(
  () => store.state.opportunities.pagination.all?.totalCount || 0
);
const currentPage = computed(
  () => store.state.opportunities.pagination.all?.page || 1
);

const handleRowClick = opportunity => {
  emit('rowClick', opportunity);
};

const updateCurrentPage = page => {
  store.dispatch('opportunities/fetchAll', { page, filters: props.filters });
};

watch(
  () => props.filters,
  () => {
    store.dispatch('opportunities/fetchAll', {
      page: 1,
      filters: props.filters,
    });
  },
  { deep: true }
);

onMounted(async () => {
  store.dispatch('opportunities/fetchAll', { page: 1, filters: props.filters });
});

const OpportunityCardRow = defineComponent({
  props: {
    opportunity: {
      type: Object,
      required: true,
    },
  },
  setup(rowProps) {
    const oppRef = toRef(rowProps, 'opportunity');
    const { statusBadgeClass, isStale, timestampLabel, campaignAttribution } =
      useOpportunityCardFields(oppRef);
    const { t } = useI18n();

    return () => {
      const opp = rowProps.opportunity;
      const contact = opp.contact;
      const assignee = opp.assignee;
      const currencyCode = store.getters['pipelineCurrencySetting/getCurrency'];
      const formattedValue = formatCurrencyAmount(
        opp.value,
        currencyCode,
        true
      );
      const stage = store.getters['pipelineStages/stageById'](
        opp.pipeline_stage_id
      );

      const avatar = contact
        ? h(Avatar, { name: contact.name, src: contact.avatar_url, size: 42 })
        : h('div', { class: 'w-[42px] h-[42px]' });

      const titleInner = [h('span', { class: 'truncate' }, opp.title)];
      if (campaignAttribution.value) {
        titleInner.unshift(
          h('span', {
            class: [
              'size-4 shrink-0 text-n-slate-11',
              campaignAttribution.value.icon,
            ],
            title: campaignAttribution.value.label,
          })
        );
      }

      const titleBlock = h('div', { class: 'flex flex-col min-w-0' }, [
        h(
          'span',
          {
            class:
              'text-n-slate-12 font-medium text-base truncate leading-snug flex items-center gap-1.5',
            title: opp.title,
          },
          titleInner
        ),
        h(
          'span',
          {
            class:
              'text-n-slate-11 text-[13px] truncate flex items-center gap-1 mt-0.5',
          },
          [
            contact ? contact.name : '-',
            h('span', { class: 'text-n-slate-9 mx-1' }, '•'),
            `#${opp.id}`,
          ]
        ),
      ]);

      const leftSection = h(
        'div',
        { class: 'flex items-center gap-4 flex-1 overflow-hidden' },
        [avatar, titleBlock]
      );

      const valueBlock = h(
        'div',
        { class: 'flex flex-col items-end w-28 shrink-0' },
        [
          h(
            'span',
            { class: 'text-n-slate-12 font-medium text-sm' },
            formattedValue
          ),
          h(
            'span',
            {
              class:
                'text-n-slate-11 text-xs truncate w-full text-right mt-0.5',
            },
            stage?.name || '-'
          ),
        ]
      );

      const statusBlock = h(
        'div',
        { class: 'w-24 flex justify-end shrink-0' },
        [
          opp.status && opp.status !== 'open'
            ? // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
              h(
                'span',
                {
                  class: [
                    'text-[10px] px-2 py-0.5 rounded-full capitalize font-medium',
                    statusBadgeClass.value,
                  ],
                },
                // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
                t(`OPPORTUNITIES.BOARD.STATUS.${opp.status.toUpperCase()}`)
              )
            : h('span', { class: 'text-n-slate-9 text-sm' }, '-'),
        ]
      );

      const assigneeBlock = h(
        'div',
        { class: 'w-40 flex items-center gap-2 shrink-0 pl-2' },
        [
          assignee
            ? h(Avatar, {
                name: assignee.name,
                src: assignee.avatar_url,
                size: 24,
              })
            : null,
          h(
            'span',
            { class: 'truncate text-sm text-n-slate-11' },
            assignee?.name || '-'
          ),
        ]
      );

      const timeBlock = h('div', { class: 'w-24 text-right shrink-0' }, [
        h(
          'span',
          {
            class: [
              'text-[11px] font-medium leading-4',
              isStale.value
                ? 'bg-n-amber-3 text-n-amber-11 px-1.5 py-0.5 rounded-sm'
                : 'text-n-slate-10',
            ],
          },
          timestampLabel.value
        ),
      ]);

      const rightSection = h(
        'div',
        { class: 'flex items-center gap-4 shrink-0' },
        [valueBlock, statusBlock, assigneeBlock, timeBlock]
      );

      return h('div', { class: 'flex items-center justify-between w-full' }, [
        leftSection,
        rightSection,
      ]);
    };
  },
});
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-surface-1 relative">
    <main class="flex-1 overflow-y-auto px-6 pt-4 w-full">
      <div class="w-full mx-auto max-w-5xl pb-6">
        <div class="flex flex-col gap-3">
          <div v-for="card in allCards" :key="card.id" class="relative group">
            <CardLayout
              layout="row"
              class="transition-colors"
              :class="[
                card.origin_conversation_id
                  ? 'cursor-pointer hover:bg-n-alpha-1 hover:border-n-slate-4'
                  : 'cursor-default grayscale border-dashed bg-n-surface-1/50',
              ]"
              @click="handleRowClick(card)"
            >
              <OpportunityCardRow :opportunity="card" />
            </CardLayout>
            <div
              v-if="!card.origin_conversation_id"
              class="absolute right-4 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 transition-opacity bg-n-surface-1 rounded-md shadow-sm"
            >
              <StartOpportunityConversationButton :opportunity="card" />
            </div>
          </div>
        </div>

        <!-- Loading State -->
        <div
          v-if="isFetching"
          class="flex justify-center items-center py-6 w-full mt-2"
        >
          <Spinner />
        </div>

        <!-- Empty State -->
        <div
          v-else-if="allCards.length === 0"
          class="flex flex-col items-center justify-center py-12 w-full mt-8"
        >
          <p class="text-n-slate-11 text-base mb-4">
            {{ $t('OPPORTUNITIES.LIST.EMPTY_STATE') }}
          </p>
          <Button
            size="small"
            color-scheme="primary"
            @click="
              store.dispatch('opportunities/fetchAll', {
                page: 1,
                filters: props.filters,
              })
            "
          >
            {{ $t('OPPORTUNITIES.LIST.RETRY') }}
          </Button>
        </div>
      </div>
    </main>

    <footer
      v-if="totalCount > 0"
      class="sticky bottom-0 z-10 bg-n-surface-1 border-t border-n-weak"
    >
      <PaginationFooter
        current-page-info="CONTACTS_LAYOUT.PAGINATION_FOOTER.SHOWING"
        :current-page="currentPage"
        :total-items="totalCount"
        class="max-w-[67rem] mx-auto px-6"
        :items-per-page="15"
        @update:current-page="updateCurrentPage"
      />
    </footer>
  </div>
</template>
