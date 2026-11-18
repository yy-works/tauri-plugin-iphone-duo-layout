import { createLayoutStore } from './store.js';
import type { LayoutConfig, LayoutMetrics, LayoutSnapshot, NativeSource } from './types.js';

export interface ObserverOptions {
  readonly root?: HTMLElement;
  readonly config?: LayoutConfig;
  readonly native?: NativeSource;
  /** Default 0: merge into animation frames without a fixed trailing wait. */
  readonly debounceMs?: number;
  readonly onError?: (error: unknown) => void;
}

/** Native adapters must provide local CSS-pixel geometry at viewport scale 1. */
export function nativeMatchesViewport(snapshot: LayoutSnapshot, width: number, height: number): boolean {
  return Math.abs(snapshot.width - width) <= 1 && Math.abs(snapshot.height - height) <= 1;
}

export function applyLayout(root: HTMLElement, metrics: LayoutMetrics): void {
  const { contentRect: r, overlayInsets: o, safeArea: safe } = metrics;
  const values = { left: r.x, top: r.y, width: r.width, height: r.height,
    right: o.right, bottom: o.bottom, 'navigation-width': metrics.navigationWidth,
    'safe-top': safe.top, 'safe-right': safe.right, 'safe-bottom': safe.bottom, 'safe-left': safe.left };
  for (const [key, value] of Object.entries(values)) root.style.setProperty(`--layout-${key}`, `${value}px`);
  root.dataset.layout = metrics.mode;
  root.dataset.layoutState = 'ready';
  root.dataset.layoutReady = 'true'; // Last write, after all geometry, in the same frame.
}

/** One observer per shell/WebView lifetime. No DOM access until this function is called. */
export function createLayoutObserver(options: ObserverOptions = {}) {
  const win = options.root?.ownerDocument.defaultView ?? window;
  if (!win) throw new Error('A browser window is required');
  const doc = win.document, root = options.root;
  const debounce = options.debounceMs ?? 0;
  if (!Number.isFinite(debounce) || debounce < 0) throw new RangeError('Invalid debounceMs');
  const store = createLayoutStore(options.config ?? {}, {
    request: callback => win.requestAnimationFrame(callback), cancel: id => win.cancelAnimationFrame(id),
  });
  let stopped = false, started = false, nativeLatest: LayoutSnapshot | null = null;
  let nativeRevision = -1, revision = 0, signature = '';
  let timer: number | undefined, poll: number | undefined, deadline: number | undefined, frame: number | undefined;
  let removeNative: (() => Promise<void>) | undefined, starting: Promise<void> | undefined;
  let probe: HTMLDivElement | undefined, resizeObserver: ResizeObserver | undefined;
  let reading = false;
  const report = (error: unknown) => {
    if (root) root.dataset.layoutState = 'error';
    options.onError?.(error);
  };
  function pending() {
    signature = ''; store.invalidate();
    if (root) { root.dataset.layoutReady = 'false'; root.dataset.layoutState = 'pending'; }
  }
  function measure() {
    frame = undefined;
    if (stopped) return;
    const width = doc.documentElement.clientWidth || win.innerWidth;
    const height = doc.documentElement.clientHeight || win.innerHeight;
    let input: LayoutSnapshot;
    if (options.native) {
      if (!nativeLatest || !nativeMatchesViewport(nativeLatest, width, height)) { pending(); return; }
      input = nativeLatest;
    } else {
      if (!probe || width <= 0 || height <= 0) return;
      const css = win.getComputedStyle(probe);
      input = { revision: 0, width, height, source: 'css', foldState: 'unknown', regions: [],
        safeArea: { top: parseFloat(css.paddingTop) || 0, right: parseFloat(css.paddingRight) || 0,
          bottom: parseFloat(css.paddingBottom) || 0, left: parseFloat(css.paddingLeft) || 0 } };
    }
    const next = JSON.stringify({ ...input, revision: 0 });
    if (next === signature) return;
    try { store.push({ ...input, revision: ++revision }); signature = next; }
    catch (error) { report(error); }
  }
  function schedule() {
    if (stopped) return;
    if (timer !== undefined) win.clearTimeout(timer);
    const request = () => { if (frame === undefined) frame = win.requestAnimationFrame(measure); };
    if (debounce > 0) timer = win.setTimeout(request, debounce); else request();
  }
  function receive(snapshot: LayoutSnapshot) {
    if (stopped || snapshot.revision <= nativeRevision) return;
    nativeRevision = snapshot.revision; nativeLatest = snapshot; schedule();
  }
  async function readNative() {
    if (stopped || reading || !options.native) return;
    reading = true;
    try { const snapshot = await options.native.read(); if (snapshot) receive(snapshot); }
    catch (error) { if (!stopped) report(error); }
    finally { reading = false; }
  }
  const onResize = () => { if (options.native) pending(); schedule(); void readNative(); };
  const apply = store.subscribe(metrics => {
    if (root) applyLayout(root, metrics);
    if (deadline !== undefined) { win.clearTimeout(deadline); deadline = undefined; }
  });
  return {
    getSnapshot: store.getSnapshot,
    subscribe: store.subscribe,
    configure(config: LayoutConfig) { store.configure(config); },
    start(): Promise<void> {
      if (stopped) return Promise.reject(new Error('Observer is disposed; create another observer'));
      if (starting) return starting;
      started = true;
      if (root) root.setAttribute('data-layout-root', '');
      pending();
      win.addEventListener('resize', onResize);
      win.addEventListener('orientationchange', onResize);
      if (typeof ResizeObserver !== 'undefined') {
        resizeObserver = new ResizeObserver(onResize); resizeObserver.observe(doc.documentElement);
      }
      // CSS env may change without resize. Native events also cover inset-only updates.
      poll = win.setInterval(schedule, 100);
      deadline = win.setTimeout(() => { if (!store.getSnapshot()) report(new Error('No valid layout snapshot after 5s; keep loading UI visible and offer retry')); }, 5000);
      starting = (async () => {
        try {
          if (options.native) {
            const remove = await options.native.subscribe(receive);
            if (stopped) { await remove(); return; }
            removeNative = remove;
            await readNative(); // Subscribe first: no lost initial update.
          } else {
            probe = doc.createElement('div');
            probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;width:0;height:0;padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';
            doc.documentElement.append(probe);
          }
          schedule();
        } catch (error) { if (!stopped) report(error); throw error; }
      })();
      return starting;
    },
    async dispose() {
      if (stopped) return;
      stopped = true;
      if (root) { root.dataset.layoutReady = 'false'; root.dataset.layoutState = 'disposed'; }
      if (frame !== undefined) win.cancelAnimationFrame(frame);
      if (timer !== undefined) win.clearTimeout(timer);
      if (poll !== undefined) win.clearInterval(poll);
      if (deadline !== undefined) win.clearTimeout(deadline);
      if (started) { win.removeEventListener('resize', onResize); win.removeEventListener('orientationchange', onResize); }
      resizeObserver?.disconnect(); probe?.remove(); apply(); store.dispose();
      await removeNative?.();
    },
  };
}
