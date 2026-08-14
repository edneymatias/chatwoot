<script setup>
import { watch, onBeforeUnmount, computed } from 'vue';
import { useEditor, EditorContent } from '@tiptap/vue-3';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  modelValue: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue']);

const editor = useEditor({
  content: props.modelValue || '',
  editable: !props.disabled,
  extensions: [
    StarterKit.configure({
      heading: false,
      codeBlock: false,
      blockquote: false,
      horizontalRule: false,
    }),
    Underline,
  ],
  onUpdate: () => {
    if (!editor.value) return;
    if (editor.value.isEmpty) {
      emit('update:modelValue', '');
    } else {
      emit('update:modelValue', editor.value.getHTML());
    }
  },
});

watch(
  () => props.modelValue,
  newValue => {
    if (!editor.value) return;
    const isSame =
      (props.modelValue === '' && editor.value.isEmpty) ||
      editor.value.getHTML() === props.modelValue;
    if (!isSame) {
      editor.value.commands.setContent(newValue || '', false);
    }
  }
);

watch(
  () => props.disabled,
  newDisabled => {
    if (!editor.value) return;
    editor.value.setEditable(!newDisabled);
  }
);

onBeforeUnmount(() => {
  if (editor.value) {
    editor.value.destroy();
  }
});

const isEmpty = computed(() => editor.value?.isEmpty ?? true);

defineExpose({
  isEmpty,
  editor,
});
</script>

<template>
  <div
    class="w-full border border-n-weak rounded-md bg-n-surface-1 text-n-slate-12 text-sm overflow-hidden focus-within:ring-1 focus-within:ring-n-brand-9 focus-within:border-n-brand-9 transition-colors"
  >
    <div
      v-if="editor"
      class="flex items-center gap-1 p-1.5 border-b border-n-weak bg-n-surface-2 text-n-slate-11"
    >
      <button
        type="button"
        :title="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.BOLD')"
        :aria-label="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.BOLD')"
        class="p-1 rounded transition-colors flex items-center justify-center hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="{
          'bg-n-alpha-3 text-n-brand-9 font-semibold': editor.isActive('bold'),
        }"
        :disabled="disabled"
        @click="editor.chain().focus().toggleBold().run()"
      >
        <Icon icon="i-lucide-bold" class="size-4" />
      </button>

      <button
        type="button"
        :title="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.ITALIC')"
        :aria-label="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.ITALIC')"
        class="p-1 rounded transition-colors flex items-center justify-center hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="{
          'bg-n-alpha-3 text-n-brand-9 font-semibold':
            editor.isActive('italic'),
        }"
        :disabled="disabled"
        @click="editor.chain().focus().toggleItalic().run()"
      >
        <Icon icon="i-lucide-italic" class="size-4" />
      </button>

      <button
        type="button"
        :title="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.STRIKE')"
        :aria-label="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.STRIKE')"
        class="p-1 rounded transition-colors flex items-center justify-center hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="{
          'bg-n-alpha-3 text-n-brand-9 font-semibold':
            editor.isActive('strike'),
        }"
        :disabled="disabled"
        @click="editor.chain().focus().toggleStrike().run()"
      >
        <Icon icon="i-lucide-strikethrough" class="size-4" />
      </button>

      <button
        type="button"
        :title="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.UNDERLINE')"
        :aria-label="
          $t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.UNDERLINE')
        "
        class="p-1 rounded transition-colors flex items-center justify-center hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="{
          'bg-n-alpha-3 text-n-brand-9 font-semibold':
            editor.isActive('underline'),
        }"
        :disabled="disabled"
        @click="editor.chain().focus().toggleUnderline().run()"
      >
        <Icon icon="i-lucide-underline" class="size-4" />
      </button>

      <div class="h-4 w-px bg-n-weak mx-1" />

      <button
        type="button"
        :title="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.ORDERED_LIST')"
        :aria-label="
          $t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.ORDERED_LIST')
        "
        class="p-1 rounded transition-colors flex items-center justify-center hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="{
          'bg-n-alpha-3 text-n-brand-9 font-semibold':
            editor.isActive('orderedList'),
        }"
        :disabled="disabled"
        @click="editor.chain().focus().toggleOrderedList().run()"
      >
        <Icon icon="i-lucide-list-ordered" class="size-4" />
      </button>

      <button
        type="button"
        :title="$t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.BULLET_LIST')"
        :aria-label="
          $t('PIPELINE_STAGES_MGMT.FORM.DESCRIPTION_EDITOR.BULLET_LIST')
        "
        class="p-1 rounded transition-colors flex items-center justify-center hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="{
          'bg-n-alpha-3 text-n-brand-9 font-semibold':
            editor.isActive('bulletList'),
        }"
        :disabled="disabled"
        @click="editor.chain().focus().toggleBulletList().run()"
      >
        <Icon icon="i-lucide-list" class="size-4" />
      </button>
    </div>

    <EditorContent
      :editor="editor"
      class="min-h-[90px] max-h-48 overflow-y-auto px-3 py-2 text-sm text-n-slate-12 [&_.tiptap]:outline-none [&_.tiptap]:min-h-[74px] [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5 [&_p]:mb-1 [&_p:last-child]:mb-0 [&_s]:line-through [&_u]:underline"
    />
  </div>
</template>
