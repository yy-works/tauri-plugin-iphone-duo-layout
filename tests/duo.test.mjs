import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { applyDuoSafeArea, observeDuoSafeArea } from '../dist/index.js';

test('applyDuoSafeArea sets CSS custom properties and datasets correctly', () => {
  const dom = new JSDOM('<!DOCTYPE html><html><body><div id="root"></div></body></html>');
  const doc = dom.window.document;
  const root = doc.getElementById('root');

  const metrics = {
    width: 466,
    height: 678,
    viewportWidth: 382,
    viewportHeight: 644,
    safeArea: { top: 0, right: 84, bottom: 34, left: 0 },
    adjustedInsets: { top: 0, right: 84, bottom: 34, left: 0 },
    cornerRadius: 59,
    cornerRadiusSource: 'containerConcentric',
    foldState: 'folded',
  };

  applyDuoSafeArea(root, metrics);

  const html = doc.documentElement;
  assert.equal(html.style.getPropertyValue('--duo-r'), '59px');
  const expectedClearance = 59 * (1 - 1 / Math.SQRT2);
  assert.equal(html.style.getPropertyValue('--duo-corner-clearance'), `${expectedClearance}px`);
  assert.equal(html.style.getPropertyValue('--duo-viewport-width'), '382px');
  assert.equal(html.style.getPropertyValue('--duo-viewport-height'), '644px');
  assert.equal(html.style.getPropertyValue('--duo-native-right'), '84px');
  assert.equal(html.style.getPropertyValue('--duo-consumed-right'), '84px');
  assert.equal(html.dataset.duoCornerSource, 'containerConcentric');
  assert.equal(html.dataset.duoSafeArea, 'native');
  assert.equal(html.dataset.duoFoldState, 'folded');
});

test('observeDuoSafeArea listens to duo-metrics custom events', () => {
  const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
  const win = dom.window;
  globalThis.window = win;
  globalThis.document = win.document;

  win.__duoMetrics = {
    width: 951,
    height: 669,
    viewportWidth: 867,
    viewportHeight: 635,
    safeArea: { top: 0, right: 84, bottom: 34, left: 0 },
    adjustedInsets: { top: 0, right: 84, bottom: 34, left: 0 },
    cornerRadius: 55,
    cornerRadiusSource: 'containerConcentric',
    foldState: 'expanded',
  };

  let calledMetrics = null;
  const dispose = observeDuoSafeArea(win.document.documentElement, {
    onChange: m => { calledMetrics = m; }
  });

  assert.equal(calledMetrics?.foldState, 'expanded');
  assert.equal(win.document.documentElement.dataset.duoFoldState, 'expanded');
  assert.equal(win.document.documentElement.style.getPropertyValue('--duo-r'), '55px');

  dispose();
  assert.equal(win.document.documentElement.dataset.duoSafeArea, undefined);

  delete globalThis.window;
  delete globalThis.document;
});
