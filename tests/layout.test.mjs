import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateLayout, createLayoutStore } from '../dist/index.js';
import { matrix } from '../examples/matrix.mjs';

const snapshot = (overrides = {}) => ({ revision: 1, width: 720, height: 600,
  safeArea: { top: 0, right: 0, bottom: 0, left: 0 }, foldState: 'unknown', regions: [], source: 'synthetic', ...overrides });
function frames() {
  let seq = 0; const callbacks = new Map();
  return { request(fn) { callbacks.set(++seq, fn); return seq; }, cancel(id) { callbacks.delete(id); },
    flush() { const pending = [...callbacks.values()]; callbacks.clear(); pending.forEach(fn => fn()); } };
}
test('eight input combinations: exact modes, split flags and content sizes', () => {
  assert.equal(matrix.length, 8);
  assert.deepEqual(matrix.map(m => m.content), ['382x612', '382x612', '358x582', '358x582', '867x603', '771x603', '843x573', '747x573']);
});
test('default 240 sidebar requires 720; height and width thresholds are inclusive', () => {
  assert.equal(calculateLayout(snapshot({ width: 719.99 })).mode, 'compact');
  assert.equal(calculateLayout(snapshot()).availableWidth, 480);
  assert.equal(calculateLayout(snapshot()).isSplit, true);
  for (const [width, height, mode] of [[599.99, 480, 'compact'], [600, 479.99, 'compact'], [600, 480, 'wide']]) {
    assert.equal(calculateLayout(snapshot({ width, height }), { navigationWidth: 96 }).mode, mode);
  }
  assert.equal(calculateLayout(snapshot(), { minWidth: 800 }).mode, 'compact');
});
test('physical state never changes layout; navigation is reserved once on either side', () => {
  for (const foldState of ['folded', 'half', 'expanded', 'unknown']) {
    const m = calculateLayout(snapshot({ foldState }));
    assert.equal(m.mode, 'wide'); assert.equal(m.foldState, foldState);
    assert.equal(m.overlayInsets.right, 240);
  }
  const left = calculateLayout(snapshot(), { navigationSide: 'left' });
  assert.equal(left.contentRect.x, 240); assert.equal(left.overlayInsets.right, 0);
});
test('active internal regions are excluded, inactive creases are metadata only', () => {
  const region = { kind: 'division', active: true, rect: { x: 490, y: 0, width: 20, height: 700 } };
  const input = snapshot({ width: 1000, height: 700, regions: [region] });
  const m = calculateLayout(input, { navigationWidth: 0 });
  assert.equal(m.segments.length, 2); assert.equal(m.availableWidth, 490); assert.equal(m.mode, 'compact');
  assert.equal(calculateLayout({ ...input, regions: [{ ...region, active: false }] }).mode, 'wide');
  const covered = calculateLayout(snapshot({ regions: [{ ...region, rect: { x: 0, y: 0, width: 1000, height: 1000 } }] }));
  assert.equal(covered.availableWidth, 0);
});
test('invalid geometry is rejected; legitimate zero safe area is accepted', () => {
  assert.equal(calculateLayout(snapshot()).safeRect.width, 720);
  for (const input of [snapshot({ width: NaN }), snapshot({ height: 0 }), snapshot({ safeArea: {} }), snapshot({ revision: -1 })]) {
    assert.throws(() => calculateLayout(input), RangeError);
  }
  assert.throws(() => calculateLayout(snapshot(), { navigationWidth: -1 }), RangeError);
  assert.equal(calculateLayout(snapshot({ safeArea: { top: 0, right: 900, bottom: 0, left: 0 } })).availableWidth, 0);
});
test('store merges bursts, rejects stale snapshots and applies safe-only changes', () => {
  const scheduler = frames(), store = createLayoutStore({}, scheduler), output = [];
  store.subscribe(m => output.push(m));
  store.push(snapshot()); store.push(snapshot({ revision: 2, width: 900 }));
  assert.equal(store.push(snapshot()), false); assert.equal(store.getSnapshot(), null);
  scheduler.flush(); assert.equal(output.length, 1); assert.equal(output[0].availableWidth, 660);
  store.push(snapshot({ revision: 3, width: 900, safeArea: { top: 0, right: 200, bottom: 0, left: 0 } }));
  scheduler.flush(); assert.equal(output[1].mode, 'compact');
  store.configure({ navigationWidth: 96 }); scheduler.flush(); assert.equal(output[2].mode, 'wide');
  assert.equal(output[2].availableWidth, 604);
  store.invalidate(); assert.equal(store.getSnapshot(), null);
  store.configure({ navigationWidth: 0 }); scheduler.flush(); assert.equal(output.length, 3);
  store.push(snapshot({ revision: 4 })); store.dispose(); scheduler.flush(); assert.equal(output.length, 3);
});
