import type { LayoutConfig, LayoutMetrics, LayoutSnapshot, Rect } from './types.js';

export const DEFAULTS = Object.freeze({ minWidth: 600, minHeight: 480, minMainWidth: 480, navigationWidth: 240, navigationSide: 'right' as const });

function nonnegative(n: number, name: string): number {
  if (!Number.isFinite(n) || n < 0) throw new RangeError(`${name} must be finite and nonnegative`);
  return n;
}

/** Subtract an active region. The resulting disjoint rectangles never cross it. */
function subtract(a: Rect, b: Rect): Rect[] {
  const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y);
  const r = Math.min(a.x + a.width, b.x + b.width), d = Math.min(a.y + a.height, b.y + b.height);
  if (x >= r || y >= d) return [a];
  return [
    { x: a.x, y: a.y, width: a.width, height: y - a.y },
    { x: a.x, y: d, width: a.width, height: a.y + a.height - d },
    { x: a.x, y, width: x - a.x, height: d - y },
    { x: r, y, width: a.x + a.width - r, height: d - y },
  ].filter(v => v.width > 0 && v.height > 0);
}

export function calculateLayout(snapshot: LayoutSnapshot, config: LayoutConfig = {}): LayoutMetrics {
  const c = { ...DEFAULTS, ...config };
  for (const key of ['minWidth', 'minHeight', 'minMainWidth', 'navigationWidth'] as const) nonnegative(c[key], key);
  if (c.navigationSide !== 'left' && c.navigationSide !== 'right') throw new TypeError('Invalid navigationSide');
  const { width, height, revision } = snapshot;
  if (nonnegative(width, 'width') === 0 || nonnegative(height, 'height') === 0) throw new RangeError('Viewport must be nonzero');
  if (!Number.isSafeInteger(revision) || revision < 0) throw new RangeError('Invalid revision');
  const safeArea = { ...snapshot.safeArea };
  for (const key of ['top', 'right', 'bottom', 'left'] as const) nonnegative(safeArea[key], `safeArea.${key}`);
  // Clamp impossible/transient oversized insets to empty space, never negative dimensions.
  const safeRect: Rect = { x: Math.min(width, safeArea.left), y: Math.min(height, safeArea.top),
    width: Math.max(0, width - safeArea.left - safeArea.right), height: Math.max(0, height - safeArea.top - safeArea.bottom) };
  let segments: Rect[] = safeRect.width && safeRect.height ? [safeRect] : [];
  const regions = snapshot.regions.map(region => {
    const rect = { ...region.rect };
    if (!Number.isFinite(rect.x) || !Number.isFinite(rect.y)) throw new RangeError('Invalid region origin');
    nonnegative(rect.width, 'region.width'); nonnegative(rect.height, 'region.height');
    if (region.active) segments = segments.flatMap(pane => subtract(pane, rect));
    return { ...region, rect };
  });
  segments.sort((a, b) => b.width * b.height - a.width * a.height || a.y - b.y || a.x - b.x);
  const pane = segments[0] ?? { x: safeRect.x, y: safeRect.y, width: 0, height: 0 };
  const wide = pane.width >= c.minWidth && pane.height >= c.minHeight && pane.width - c.navigationWidth >= c.minMainWidth;
  const navigationWidth = wide ? c.navigationWidth : 0;
  const contentRect = { x: pane.x + (c.navigationSide === 'left' ? navigationWidth : 0), y: pane.y,
    width: pane.width - navigationWidth, height: pane.height };
  const horizontal = contentRect.width >= contentRect.height;
  return { revision, source: snapshot.source, viewport: { x: 0, y: 0, width, height }, safeArea, safeRect, segments, pane, contentRect,
    availableWidth: contentRect.width, availableHeight: contentRect.height, navigationWidth, mode: wide ? 'wide' : 'compact',
    isSplit: wide && navigationWidth > 0, primaryAxis: horizontal ? 'horizontal' : 'vertical',
    primarySize: horizontal ? contentRect.width : contentRect.height, crossSize: horizontal ? contentRect.height : contentRect.width,
    foldState: snapshot.foldState, regions,
    overlayInsets: { top: contentRect.y, left: contentRect.x, right: width - contentRect.x - contentRect.width, bottom: height - contentRect.y - contentRect.height } };
}
