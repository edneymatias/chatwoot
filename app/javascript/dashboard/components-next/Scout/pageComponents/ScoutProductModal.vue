<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  scoutId: {
    type: [Number, String],
    required: true,
  },
  product: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();

const dialogRef = ref(null);
const name = ref('');
const price = ref('');
const valueProposition = ref('');
const isSubmitting = ref(false);

const isEditing = computed(() => !!props.product);

watch(
  () => props.product,
  newVal => {
    if (newVal) {
      name.value = newVal.name || '';
      price.value = newVal.price || '';
      valueProposition.value = newVal.value_proposition || '';
    } else {
      name.value = '';
      price.value = '';
      valueProposition.value = '';
    }
  },
  { immediate: true }
);

const openModal = () => {
  dialogRef.value?.open();
};

const handleSave = async () => {
  if (!name.value.trim()) return;

  isSubmitting.value = true;
  try {
    const payload = {
      product: {
        name: name.value.trim(),
        price: price.value.trim(),
        value_proposition: valueProposition.value.trim(),
      },
    };

    if (isEditing.value) {
      await ScoutAPI.updateProductCatalogItem(
        props.scoutId,
        props.product.id,
        payload
      );
    } else {
      await ScoutAPI.addProductCatalogItem(props.scoutId, payload);
    }

    dialogRef.value?.close();
    emit('saved');
  } catch (error) {
    // Handled
  } finally {
    isSubmitting.value = false;
  }
};

defineExpose({
  openModal,
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isEditing
        ? t('SCOUT.PRODUCTS.MODAL.EDIT_TITLE')
        : t('SCOUT.PRODUCTS.MODAL.ADD_TITLE')
    "
    :description="t('SCOUT.PRODUCTS.MODAL.DESCRIPTION')"
    :confirm-button-label="t('SCOUT.PRODUCTS.MODAL.SUBMIT')"
    :cancel-button-label="t('SCOUT.PRODUCTS.MODAL.CANCEL')"
    :disable-confirm-button="!name.trim() || isSubmitting"
    :is-loading="isSubmitting"
    width="lg"
    @confirm="handleSave"
  >
    <form class="flex flex-col gap-4 py-2" @submit.prevent="handleSave">
      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ `${t('SCOUT.PRODUCTS.MODAL.NAME_LABEL')} *` }}
        </label>
        <Input
          v-model="name"
          :placeholder="t('SCOUT.PRODUCTS.MODAL.NAME_PLACEHOLDER')"
          autofocus
        />
      </div>

      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ t('SCOUT.PRODUCTS.MODAL.PRICE_LABEL') }}
        </label>
        <Input
          v-model="price"
          :placeholder="t('SCOUT.PRODUCTS.MODAL.PRICE_PLACEHOLDER')"
        />
      </div>

      <div>
        <label class="block text-xs font-medium text-n-slate-11 mb-1.5">
          {{ t('SCOUT.PRODUCTS.MODAL.VALUE_PROP_LABEL') }}
        </label>
        <TextArea
          v-model="valueProposition"
          :placeholder="t('SCOUT.PRODUCTS.MODAL.VALUE_PROP_PLACEHOLDER')"
          :max-length="2000"
          auto-height
        />
      </div>
    </form>
  </Dialog>
</template>
