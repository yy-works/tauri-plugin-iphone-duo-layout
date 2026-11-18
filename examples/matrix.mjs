import assert from 'node:assert/strict';
import { calculateLayout } from '../dist/index.js';

export const matrix = [];
for (const [width, height] of [[466, 678], [951, 669]]) {
  for (const safeArea of [{ top: 32, right: 84, bottom: 34, left: 0 }, { top: 56, right: 96, bottom: 40, left: 12 }]) {
    for (const navigationWidth of [0, 96]) {
      const m = calculateLayout({ revision: 1, width, height, safeArea, foldState: 'unknown', regions: [], source: 'synthetic' }, { navigationWidth });
      const expectedMode = width === 466 ? 'compact' : 'wide';
      const expectedWidth = width - safeArea.left - safeArea.right - (expectedMode === 'wide' ? navigationWidth : 0);
      assert.equal(m.mode, expectedMode);
      assert.equal(m.availableWidth, expectedWidth);
      assert.equal(m.isSplit, expectedMode === 'wide' && navigationWidth > 0);
      matrix.push({ input: `${width}x${height}`, safe: Object.values(safeArea).join('/'), nav: navigationWidth,
        mode: m.mode, split: m.isSplit, content: `${m.availableWidth}x${m.availableHeight}` });
    }
  }
}
if (process.argv[1]?.endsWith('/matrix.mjs')) console.table(matrix);
