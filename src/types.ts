/** Every frontend distance is in CSS px. Native snapshots use view-local points. */
export interface Insets { readonly top: number; readonly right: number; readonly bottom: number; readonly left: number }
export interface Rect { readonly x: number; readonly y: number; readonly width: number; readonly height: number }
export type FoldState = 'unknown' | 'folded' | 'half' | 'expanded';
export interface ReservedRegion {
  readonly kind: 'division' | 'occlusion';
  /** Includes the OS margins already; do not add them a second time. */
  readonly rect: Rect;
  readonly active: boolean;
}
export interface LayoutSnapshot {
  readonly revision: number;
  readonly width: number;
  readonly height: number;
  readonly safeArea: Insets;
  readonly foldState: FoldState;
  readonly regions: readonly ReservedRegion[];
  readonly source: 'native' | 'css' | 'synthetic';
}
export interface LayoutConfig {
  readonly minWidth?: number;
  readonly minHeight?: number;
  readonly minMainWidth?: number;
  /** Requested persistent navigation width, not already included in OS safeArea. */
  readonly navigationWidth?: number;
  readonly navigationSide?: 'left' | 'right';
}
export interface LayoutMetrics {
  readonly revision: number;
  readonly source: LayoutSnapshot['source'];
  readonly viewport: Rect;
  readonly safeArea: Insets;
  readonly safeRect: Rect;
  readonly segments: readonly Rect[];
  /** Largest unobstructed segment. Physical posture never selects the layout. */
  readonly pane: Rect;
  readonly contentRect: Rect;
  readonly availableWidth: number;
  readonly availableHeight: number;
  readonly navigationWidth: number;
  readonly mode: 'compact' | 'wide';
  readonly isSplit: boolean;
  readonly primaryAxis: 'horizontal' | 'vertical';
  readonly primarySize: number;
  readonly crossSize: number;
  readonly foldState: FoldState;
  readonly regions: readonly ReservedRegion[];
  /** Full viewport offsets for an overlay host; includes safe area and app navigation. */
  readonly overlayInsets: Insets;
}
export interface NativeSource {
  /** Subscribe before read. Must also start the native observer. */
  subscribe(listener: (snapshot: LayoutSnapshot) => void): Promise<() => Promise<void>>;
  read(): Promise<LayoutSnapshot | null>;
}
