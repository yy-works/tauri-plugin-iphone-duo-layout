import { calculateLayout } from './policy.js';
import type { LayoutConfig, LayoutMetrics, LayoutSnapshot } from './types.js';

export interface FrameScheduler { request(callback: () => void): number; cancel(id: number): void }

/** A single atomic commit per frame; optional trailing debounce is in the DOM observer. */
export function createLayoutStore(config: LayoutConfig, scheduler: FrameScheduler) {
  let options = config, latest: LayoutSnapshot | null = null, current: LayoutMetrics | null = null;
  let frame: number | null = null, disposed = false;
  const listeners = new Set<(metrics: LayoutMetrics) => void>();
  function queue() {
    if (disposed || frame !== null) return;
    frame = scheduler.request(() => {
      frame = null;
      if (!latest || disposed) return;
      current = calculateLayout(latest, options);
      for (const listener of [...listeners]) listener(current);
    });
  }
  return {
    getSnapshot: () => current,
    invalidate() {
      if (frame !== null) scheduler.cancel(frame);
      frame = null; latest = null; current = null;
    },
    push(snapshot: LayoutSnapshot): boolean {
      if (disposed || (latest && snapshot.revision <= latest.revision)) return false;
      calculateLayout(snapshot, options); // Validate before replacing the last good snapshot.
      latest = snapshot; queue(); return true;
    },
    configure(next: LayoutConfig) {
      if (disposed) return;
      const merged = { ...options, ...next };
      if (latest) calculateLayout(latest, merged);
      options = merged; queue();
    },
    subscribe(listener: (metrics: LayoutMetrics) => void): () => void {
      if (disposed) throw new Error('Layout store has been disposed');
      listeners.add(listener);
      if (current) listener(current);
      return () => { listeners.delete(listener); };
    },
    dispose() { disposed = true; if (frame !== null) scheduler.cancel(frame); frame = null; current = null; latest = null; listeners.clear(); },
  };
}
