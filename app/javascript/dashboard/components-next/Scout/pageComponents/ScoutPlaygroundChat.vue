<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ScoutAPI from 'dashboard/api/scout';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  scout: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const messages = ref([]);
const inputMessage = ref('');
const isSending = ref(false);

const handleResetSession = () => {
  messages.value = [];
  inputMessage.value = '';
};

const handleSendMessage = async () => {
  const content = inputMessage.value.trim();
  if (!content || isSending.value) return;

  messages.value.push({
    role: 'user',
    content,
    timestamp: new Date().toLocaleTimeString(),
  });

  inputMessage.value = '';
  isSending.value = true;

  try {
    const { data } = await ScoutAPI.sendPlaygroundMessage(props.scout.id, {
      message: content,
    });

    messages.value.push({
      role: 'assistant',
      content: data.reply || '',
      tool_calls: data.tool_calls || [],
      error: data.error || null,
      timestamp: new Date().toLocaleTimeString(),
    });
  } catch (error) {
    messages.value.push({
      role: 'assistant',
      content: t('SCOUT.PLAYGROUND.ERROR_REPLY'),
      error: error?.message,
      timestamp: new Date().toLocaleTimeString(),
    });
  } finally {
    isSending.value = false;
  }
};

const handleKeydown = event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    handleSendMessage();
  }
};
</script>

<template>
  <div
    class="flex flex-col h-full rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden shadow-sm"
  >
    <!-- SubHeader / Toolbar -->
    <div
      class="flex items-center justify-between px-5 py-3 border-b border-n-weak bg-n-surface-1"
    >
      <div class="flex items-center gap-2">
        <span class="size-2.5 rounded-full bg-emerald-500 animate-pulse" />
        <span class="text-xs font-medium text-n-slate-12">
          {{ t('SCOUT.PLAYGROUND.STATUS_READY') }}
        </span>
      </div>
      <Button
        :label="t('SCOUT.PLAYGROUND.RESET_SESSION')"
        variant="ghost"
        color="slate"
        size="xs"
        @click="handleResetSession"
      />
    </div>

    <!-- Message Stream -->
    <div class="flex-1 p-5 overflow-y-auto space-y-4">
      <div
        v-if="messages.length === 0"
        class="h-full flex flex-col items-center justify-center text-center text-n-slate-11 py-12"
      >
        <div
          class="flex items-center justify-center size-12 rounded-xl bg-n-alpha-1 text-n-brand mb-3"
        >
          <span class="i-lucide-message-square size-6" />
        </div>
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('SCOUT.PLAYGROUND.EMPTY_CHAT_TITLE') }}
        </p>
        <p class="text-xs text-n-slate-10 mt-1 max-w-sm">
          {{ t('SCOUT.PLAYGROUND.EMPTY_CHAT_DESC') }}
        </p>
      </div>

      <template v-for="(msg, index) in messages" :key="index">
        <!-- User Message -->
        <div v-if="msg.role === 'user'" class="flex justify-end">
          <div
            class="max-w-lg rounded-2xl rounded-tr-sm bg-n-brand text-white px-4 py-3 shadow-sm text-sm"
          >
            <p class="whitespace-pre-wrap leading-relaxed">{{ msg.content }}</p>
            <span class="block text-[10px] text-white/70 text-right mt-1.5">{{
              msg.timestamp
            }}</span>
          </div>
        </div>

        <!-- Assistant Message -->
        <div v-else class="flex flex-col items-start gap-2 max-w-2xl">
          <div class="flex items-center gap-2">
            <div
              class="flex items-center justify-center size-6 rounded-lg bg-n-alpha-1 text-n-brand"
            >
              <span class="i-lucide-bot size-3.5" />
            </div>
            <span class="text-xs font-medium text-n-slate-12">{{
              scout.name
            }}</span>
            <span class="text-[10px] text-n-slate-10">{{ msg.timestamp }}</span>
          </div>

          <!-- Tool Invocations Box -->
          <div
            v-if="msg.tool_calls && msg.tool_calls.length > 0"
            class="w-full space-y-2 mb-1"
          >
            <div
              v-for="(tool, tIndex) in msg.tool_calls"
              :key="tIndex"
              class="rounded-xl border border-n-weak bg-n-surface-1 p-3.5 text-xs text-n-slate-12 shadow-sm"
            >
              <div class="flex items-center justify-between gap-2 mb-2">
                <div class="flex items-center gap-2">
                  <span class="i-lucide-wrench size-3.5 text-n-brand" />
                  <span class="font-medium text-n-brand">{{
                    tool.tool_name
                  }}</span>
                </div>
                <span
                  class="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-medium"
                  :class="
                    tool.simulated
                      ? 'bg-amber-500/10 text-amber-600 dark:text-amber-400'
                      : 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                  "
                >
                  {{
                    tool.simulated
                      ? t('SCOUT.PLAYGROUND.SIMULATED_BADGE')
                      : t('SCOUT.PLAYGROUND.LIVE_BADGE')
                  }}
                </span>
              </div>

              <!-- Arguments -->
              <div v-if="tool.arguments" class="mt-2 text-[11px]">
                <span class="text-n-slate-10 block mb-1 font-medium">
                  {{ `${t('SCOUT.PLAYGROUND.ARGUMENTS_LABEL')}:` }}
                </span>
                <div
                  class="bg-n-solid-2 p-2 rounded-lg text-n-slate-12 font-mono overflow-x-auto text-[11px] whitespace-pre-wrap"
                >
                  {{ JSON.stringify(tool.arguments, null, 2) }}
                </div>
              </div>

              <!-- Result -->
              <div v-if="tool.result" class="mt-2 text-[11px]">
                <span class="text-n-slate-10 block mb-1 font-medium">
                  {{ `${t('SCOUT.PLAYGROUND.RESULT_LABEL')}:` }}
                </span>
                <div
                  class="bg-n-solid-2 p-2 rounded-lg text-n-slate-12 font-mono overflow-x-auto text-[11px] whitespace-pre-wrap"
                >
                  {{ tool.result }}
                </div>
              </div>

              <!-- Error -->
              <div v-if="tool.error" class="mt-2 text-[11px]">
                <span class="text-n-ruby-9 block mb-1 font-medium">
                  {{ `${t('SCOUT.PLAYGROUND.ERROR_LABEL')}:` }}
                </span>
                <div
                  class="bg-n-ruby-2 text-n-ruby-9 p-2 rounded-lg font-mono overflow-x-auto text-[11px] whitespace-pre-wrap"
                >
                  {{ tool.error }}
                </div>
              </div>
            </div>
          </div>

          <!-- Assistant Text Bubble -->
          <div
            class="rounded-2xl rounded-tl-sm bg-n-surface-1 border border-n-weak text-n-slate-12 px-4 py-3 shadow-sm text-sm"
          >
            <p class="whitespace-pre-wrap leading-relaxed">{{ msg.content }}</p>
          </div>
        </div>
      </template>

      <!-- Loading / Typing Indicator -->
      <div
        v-if="isSending"
        class="flex items-center gap-2 text-xs text-n-slate-11"
      >
        <Spinner />
        <span>{{ t('SCOUT.PLAYGROUND.THINKING') }}</span>
      </div>
    </div>

    <!-- Input Bar -->
    <div class="p-4 border-t border-n-weak bg-n-surface-1">
      <div
        class="flex items-end gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-2 focus-within:border-n-brand focus-within:ring-1 focus-within:ring-n-brand transition-all"
      >
        <textarea
          v-model="inputMessage"
          rows="2"
          class="flex-1 bg-transparent border-0 resize-none text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-0 p-1"
          :placeholder="t('SCOUT.PLAYGROUND.INPUT_PLACEHOLDER')"
          @keydown="handleKeydown"
        />
        <Button
          icon="i-lucide-send"
          color="blue"
          size="sm"
          :disabled="!inputMessage.trim() || isSending"
          @click="handleSendMessage"
        />
      </div>
      <p class="text-[11px] text-n-slate-10 text-center mt-2">
        {{ t('SCOUT.PLAYGROUND.DISCLAIMER') }}
      </p>
    </div>
  </div>
</template>
