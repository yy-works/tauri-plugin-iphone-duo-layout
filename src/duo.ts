export interface DuoMetrics {
  revision?: number;
  width: number;
  height: number;
  viewportWidth: number;
  viewportHeight: number;
  safeArea: { top: number; right: number; bottom: number; left: number };
  adjustedInsets?: { top: number; right: number; bottom: number; left: number };
  cornerRadius?: number | null;
  cornerRadii?: {
    topLeft: number;
    topRight: number;
    bottomLeft: number;
    bottomRight: number;
  } | null;
  cornerRadiusSource?: string;
  foldState?: 'unknown' | 'folded' | 'half' | 'expanded';
  hingeAngle?: number | null;
}

declare global {
  interface Window {
    __duoMetrics?: DuoMetrics;
  }
}

/**
 * 将 Duo / 折叠屏度量写入 DOM 根元素（CSS 自定义属性与 dataset）
 *
 * 计算规则：
 * - 只有 UIKit 未消费的安全区才由 CSS 补充，避免双重边距
 * - 默认圆角避让边距按 R * (1 - 1 / sqrt(2)) 计算
 * - 若无法从系统取得真实圆角，且右侧安全区 >= 64pt（外屏标志），可回退 59pt 或传参数自定义
 */
export function applyDuoSafeArea(
  root: HTMLElement = document.documentElement,
  metrics: DuoMetrics,
  options?: { fallbackCornerRadius?: number }
) {
  if (!(metrics.viewportWidth > 0 && metrics.viewportHeight > 0)) return;
  const html = root.ownerDocument ? root.ownerDocument.documentElement : root;
  const radius =
    metrics.cornerRadius ??
    (options?.fallbackCornerRadius !== undefined
      ? options.fallbackCornerRadius
      : metrics.safeArea.right >= 64
      ? 59
      : 0);

  html.style.setProperty('--duo-r', `${radius}px`);
  html.style.setProperty('--duo-corner-clearance', `${radius * (1 - 1 / Math.SQRT2)}px`);
  html.style.setProperty('--duo-viewport-width', `${metrics.viewportWidth}px`);
  html.style.setProperty('--duo-viewport-height', `${metrics.viewportHeight}px`);

  const safe = metrics.safeArea;
  const consumed = metrics.adjustedInsets ?? { top: 0, right: 0, bottom: 0, left: 0 };

  for (const edge of ['top', 'right', 'bottom', 'left'] as const) {
    html.style.setProperty(`--duo-native-${edge}`, `${safe[edge]}px`);
    html.style.setProperty(`--duo-consumed-${edge}`, `${consumed[edge]}px`);
  }

  html.dataset.duoCornerSource = metrics.cornerRadius != null ? metrics.cornerRadiusSource : 'fallback';
  html.dataset.duoSafeArea = 'native';
  if (metrics.foldState) {
    html.dataset.duoFoldState = metrics.foldState;
  }
}

/**
 * 监听 `duo-metrics` 事件并在挂载/变更时自动同步 CSS 变量
 */
export function observeDuoSafeArea(
  root: HTMLElement = document.documentElement,
  options?: { fallbackCornerRadius?: number; onChange?: (metrics: DuoMetrics) => void }
): () => void {
  const apply = () => {
    if (typeof window !== 'undefined' && window.__duoMetrics) {
      applyDuoSafeArea(root, window.__duoMetrics, options);
      options?.onChange?.(window.__duoMetrics);
    }
  };
  apply();
  if (typeof window !== 'undefined') {
    window.addEventListener('duo-metrics', apply);
    return () => {
      window.removeEventListener('duo-metrics', apply);
      const html = root.ownerDocument ? root.ownerDocument.documentElement : root;
      delete html.dataset.duoSafeArea;
    };
  }
  return () => {};
}
