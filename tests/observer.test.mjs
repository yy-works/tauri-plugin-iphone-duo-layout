import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { createLayoutObserver } from '../dist/index.js';

const css = readFileSync(new URL('../src/style.css', import.meta.url), 'utf8');
const snap = (revision = 1, safeRight = 84) => ({ revision, width: 466, height: 678,
  safeArea: { top: 0, right: safeRight, bottom: 34, left: 0 }, foldState: 'unknown', regions: [], source: 'native' });
function browser() {
  const dom = new JSDOM(`<!DOCTYPE html><style>${css}</style><main data-layout-root></main>`, { pretendToBeVisual: true });
  const win = dom.window, root = win.document.querySelector('main');
  let width = 466, height = 678, seq = 0; const pending = new Map();
  Object.defineProperties(win.document.documentElement, { clientWidth: { get: () => width }, clientHeight: { get: () => height } });
  win.requestAnimationFrame = fn => { pending.set(++seq, fn); return seq; };
  win.cancelAnimationFrame = id => pending.delete(id);
  return { win, root, dom, resize(w, h) { width = w; height = h; win.dispatchEvent(new win.Event('resize')); },
    flush() { const callbacks = [...pending.values()]; pending.clear(); callbacks.forEach(fn => fn()); } };
}
for (const delay of [0, 530]) test(`first visible frame uses valid native safe area, bridge delay=${delay}ms`, async () => {
  const b = browser(); let receive, removed = 0;
  const native = { async subscribe(cb) { receive = cb; return async () => { removed++; }; }, async read() { return null; } };
  const observer = createLayoutObserver({ root: b.root, native });
  try {
    await observer.start(); b.flush(); b.flush();
    assert.equal(b.win.getComputedStyle(b.root).visibility, 'hidden');
    assert.equal(observer.getSnapshot(), null);
    if (delay) await new Promise(resolve => setTimeout(resolve, delay));
    assert.equal(b.win.getComputedStyle(b.root).visibility, 'hidden');
    receive(snap()); b.flush();
    assert.equal(b.root.dataset.layoutReady, 'false');
    b.flush();
    assert.equal(b.root.style.getPropertyValue('--layout-width'), '382px');
    assert.equal(b.win.getComputedStyle(b.root).visibility, 'visible');
    receive(snap(2, 96)); b.flush(); b.flush();
    assert.equal(observer.getSnapshot().availableWidth, 370);
    receive(snap(1, 0)); b.flush(); b.flush();
    assert.equal(observer.getSnapshot().availableWidth, 370);
    b.resize(951, 669); b.flush(); b.flush();
    assert.equal(b.root.dataset.layoutReady, 'false');
    assert.equal(observer.getSnapshot(), null);
    receive({ ...snap(3), width: 951, height: 669 }); b.flush(); b.flush();
    assert.equal(observer.getSnapshot().mode, 'wide');
  } finally { await observer.dispose(); b.dom.window.close(); }
  assert.equal(removed, 1);
});
test('dispose during asynchronous subscribe removes the eventual native listener', async () => {
  const b = browser(); let release, removed = 0;
  const observer = createLayoutObserver({ root: b.root, native: {
    subscribe: () => new Promise(resolve => { release = () => resolve(async () => { removed++; }); }), read: async () => snap(),
  } });
  const started = observer.start(); await observer.dispose(); release(); await started;
  assert.equal(removed, 1); assert.equal(observer.getSnapshot(), null); b.dom.window.close();
});
test('CSS-only browser fallback explicitly reports unknown posture', async () => {
  const b = browser(), observer = createLayoutObserver({ root: b.root, config: { navigationWidth: 0 } });
  try { await observer.start(); b.flush(); b.flush();
    assert.equal(observer.getSnapshot().source, 'css'); assert.equal(observer.getSnapshot().foldState, 'unknown');
    b.resize(951, 669); b.flush(); b.flush(); assert.equal(observer.getSnapshot().mode, 'wide');
  } finally { await observer.dispose(); b.dom.window.close(); }
});
