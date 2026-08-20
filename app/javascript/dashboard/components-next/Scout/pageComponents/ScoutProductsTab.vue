<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Button from 'dashboard/components-next/button/Button.vue';
import ScoutProductModal from './ScoutProductModal.vue';

const props = defineProps({
  scout: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['updated']);
const { t } = useI18n();

const productModalRef = ref(null);
const editingProduct = ref(null);
const isDeleting = ref(false);

const products = computed(() => {
  const catalog = props.scout.product_catalog;
  if (!catalog) return [];
  if (Array.isArray(catalog)) return catalog;
  if (Array.isArray(catalog.items)) return catalog.items;
  return [];
});

const handleOpenAdd = () => {
  editingProduct.value = null;
  nextTick(() => {
    productModalRef.value?.openModal();
  });
};

const handleOpenEdit = product => {
  editingProduct.value = product;
  nextTick(() => {
    productModalRef.value?.openModal();
  });
};

const handleDelete = async productId => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('SCOUT.PRODUCTS.CONFIRM_DELETE'))) return;

  isDeleting.value = true;
  try {
    await ScoutAPI.deleteProductCatalogItem(props.scout.id, productId);
    emit('updated');
  } catch (error) {
    // Handled
  } finally {
    isDeleting.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex items-center justify-between pb-4">
      <div>
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('SCOUT.PRODUCTS.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11 mt-0.5">
          {{ t('SCOUT.PRODUCTS.SUBTITLE') }}
        </p>
      </div>
      <Button
        :label="t('SCOUT.PRODUCTS.ADD_BUTTON')"
        color="blue"
        size="sm"
        @click="handleOpenAdd"
      />
    </div>

    <!-- Products Grid -->
    <div
      v-if="products.length > 0"
      class="grid grid-cols-1 md:grid-cols-2 gap-4"
    >
      <div
        v-for="item in products"
        :key="item.id"
        class="flex flex-col justify-between p-4 rounded-xl border border-n-weak bg-n-surface-1 shadow-sm hover:border-n-brand/40 transition-all duration-200"
      >
        <div>
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-3">
              <div
                class="flex items-center justify-center size-9 rounded-lg bg-n-alpha-1 text-n-brand"
              >
                <span class="i-lucide-package size-4" />
              </div>
              <div>
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ item.name }}
                </h3>
                <span
                  v-if="item.price"
                  class="text-xs font-semibold text-emerald-600 dark:text-emerald-400"
                >
                  {{ item.price }}
                </span>
              </div>
            </div>

            <div class="flex items-center gap-1">
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="xs"
                @click="handleOpenEdit(item)"
              />
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="xs"
                @click="handleDelete(item.id)"
              />
            </div>
          </div>

          <p
            v-if="item.value_proposition"
            class="text-xs text-n-slate-11 mt-3 line-clamp-3 leading-relaxed"
          >
            {{ item.value_proposition }}
          </p>
        </div>
      </div>
    </div>

    <div
      v-else
      class="py-12 flex flex-col items-center justify-center text-center text-n-slate-11 border border-dashed border-n-weak rounded-xl"
    >
      <span class="i-lucide-package size-8 text-n-slate-10 mb-2" />
      <p class="text-sm font-medium text-n-slate-12">
        {{ t('SCOUT.PRODUCTS.EMPTY_TITLE') }}
      </p>
      <p class="text-xs text-n-slate-10 mt-1 max-w-sm">
        {{ t('SCOUT.PRODUCTS.EMPTY_DESC') }}
      </p>
    </div>
    <!-- Product Modal -->
    <ScoutProductModal
      ref="productModalRef"
      :scout-id="scout.id"
      :product="editingProduct"
      @saved="emit('updated')"
    />
  </div>
</template>
