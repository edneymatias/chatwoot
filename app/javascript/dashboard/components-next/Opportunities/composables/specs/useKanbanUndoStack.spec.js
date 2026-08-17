import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { useKanbanUndoStack } from '../useKanbanUndoStack';

describe('useKanbanUndoStack', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('initializes with an empty toast list', () => {
    const { toasts } = useKanbanUndoStack();
    expect(toasts.value).toEqual([]);
  });

  it('pushes a toast and auto-dismisses after 5 seconds', () => {
    const { toasts, pushToast } = useKanbanUndoStack();
    pushToast({ message: 'Moved card', onUndo: vi.fn() });

    expect(toasts.value.length).toBe(1);
    expect(toasts.value[0].message).toBe('Moved card');

    vi.advanceTimersByTime(4999);
    expect(toasts.value.length).toBe(1);

    vi.advanceTimersByTime(1);
    expect(toasts.value.length).toBe(0);
  });

  it('evicts the oldest toast when pushed beyond the 3-item capacity', () => {
    const { toasts, pushToast } = useKanbanUndoStack();

    pushToast({ message: 'Toast 1', onUndo: vi.fn() });
    pushToast({ message: 'Toast 2', onUndo: vi.fn() });
    pushToast({ message: 'Toast 3', onUndo: vi.fn() });

    expect(toasts.value.length).toBe(3);
    expect(toasts.value.map(t => t.message)).toEqual([
      'Toast 1',
      'Toast 2',
      'Toast 3',
    ]);

    pushToast({ message: 'Toast 4', onUndo: vi.fn() });

    expect(toasts.value.length).toBe(3);
    expect(toasts.value.map(t => t.message)).toEqual([
      'Toast 2',
      'Toast 3',
      'Toast 4',
    ]);
  });

  it('executes onUndo callback and dismisses toast immediately on undoToast', () => {
    const { toasts, pushToast, undoToast } = useKanbanUndoStack();
    const onUndo = vi.fn();

    const id = pushToast({ message: 'Moved card', onUndo });
    expect(toasts.value.length).toBe(1);

    undoToast(id);

    expect(onUndo).toHaveBeenCalledTimes(1);
    expect(toasts.value.length).toBe(0);
  });

  it('dismisses toast without executing callback on dismissToast', () => {
    const { toasts, pushToast, dismissToast } = useKanbanUndoStack();
    const onUndo = vi.fn();

    const id = pushToast({ message: 'Moved card', onUndo });
    expect(toasts.value.length).toBe(1);

    dismissToast(id);

    expect(onUndo).not.toHaveBeenCalled();
    expect(toasts.value.length).toBe(0);
  });

  it('pauses and resumes timers on hover without resetting duration', () => {
    const { toasts, pushToast, pauseAll, resumeAll } = useKanbanUndoStack();

    pushToast({ message: 'Toast 1', onUndo: vi.fn() });

    // Advance 2 seconds
    vi.advanceTimersByTime(2000);
    expect(toasts.value.length).toBe(1);

    // Pause on hover
    pauseAll();

    // Advance another 10 seconds while paused
    vi.advanceTimersByTime(10000);
    expect(toasts.value.length).toBe(1);

    // Resume countdown
    resumeAll();

    // Advance 2.9 seconds (total unpaused time = 4.9s) -> still active
    vi.advanceTimersByTime(2900);
    expect(toasts.value.length).toBe(1);

    // Advance 200ms -> should dismiss
    vi.advanceTimersByTime(200);
    expect(toasts.value.length).toBe(0);
  });

  it('clears all active timers on clearAll', () => {
    const { toasts, pushToast, clearAll } = useKanbanUndoStack();

    pushToast({ message: 'Toast 1', onUndo: vi.fn() });
    pushToast({ message: 'Toast 2', onUndo: vi.fn() });
    expect(toasts.value.length).toBe(2);

    clearAll();
    expect(toasts.value.length).toBe(0);

    vi.advanceTimersByTime(10000);
    expect(toasts.value.length).toBe(0);
  });
});
