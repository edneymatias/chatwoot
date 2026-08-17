import { ref, onBeforeUnmount, getCurrentInstance } from 'vue';

const MAX_STACK_SIZE = 3;
const DEFAULT_TIMEOUT = 5000;

export function useKanbanUndoStack() {
  const toasts = ref([]);
  let isPaused = false;

  const dismissToast = id => {
    const index = toasts.value.findIndex(t => t.id === id);
    if (index !== -1) {
      const [removed] = toasts.value.splice(index, 1);
      if (removed.timerId) {
        clearTimeout(removed.timerId);
      }
    }
  };

  const startTimer = toast => {
    if (isPaused) {
      toast.endTime = null;
      return;
    }
    toast.endTime = Date.now() + toast.remainingTime;
    toast.timerId = setTimeout(() => {
      dismissToast(toast.id);
    }, toast.remainingTime);
  };

  const pushToast = ({ message, onUndo, timeout = DEFAULT_TIMEOUT }) => {
    const id = `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

    if (toasts.value.length >= MAX_STACK_SIZE) {
      const oldest = toasts.value.shift();
      if (oldest && oldest.timerId) {
        clearTimeout(oldest.timerId);
      }
    }

    const toast = {
      id,
      message,
      onUndo,
      timeout,
      remainingTime: timeout,
      endTime: null,
      timerId: null,
    };

    toasts.value.push(toast);
    startTimer(toast);

    return id;
  };

  const undoToast = id => {
    const item = toasts.value.find(t => t.id === id);
    if (item) {
      const callback = item.onUndo;
      dismissToast(id);
      if (typeof callback === 'function') {
        callback();
      }
    }
  };

  const pauseAll = () => {
    isPaused = true;
    toasts.value.forEach(toast => {
      if (toast.timerId) {
        clearTimeout(toast.timerId);
        toast.timerId = null;
      }
      if (toast.endTime) {
        toast.remainingTime = Math.max(0, toast.endTime - Date.now());
      }
    });
  };

  const resumeAll = () => {
    isPaused = false;
    // Iterate over a copy in case any item has remainingTime <= 0 and gets dismissed immediately
    [...toasts.value].forEach(toast => {
      if (toast.remainingTime <= 0) {
        dismissToast(toast.id);
      } else {
        startTimer(toast);
      }
    });
  };

  const clearAll = () => {
    toasts.value.forEach(toast => {
      if (toast.timerId) {
        clearTimeout(toast.timerId);
      }
    });
    toasts.value = [];
    isPaused = false;
  };

  if (getCurrentInstance()) {
    onBeforeUnmount(() => {
      clearAll();
    });
  }

  return {
    toasts,
    pushToast,
    undoToast,
    dismissToast,
    pauseAll,
    resumeAll,
    clearAll,
  };
}
