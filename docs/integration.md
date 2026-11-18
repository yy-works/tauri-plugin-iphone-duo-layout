# Detailed integration notes

A framework-independent TypeScript layout policy with an optional Tauri v2 iOS plugin.
It measures **the current container**, subtracts safe areas, active reserved regions and
app navigation, and publishes an atomic layout snapshot. It never infers physical posture
from a device model, a size class or a width threshold.

Local-only delivery. MIT licensed; no registry or remote publication has been performed.

## Install locally

```sh
cd /absolute/path/to/tauri-plugin-iphone-duo-layout
npm ci
npm test
npm run example

# From a frontend app, after building this package:
npm install /absolute/path/to/tauri-plugin-iphone-duo-layout
```

The root entry has no runtime dependency on React or Tauri. The optional `./tauri` entry
uses the app's `@tauri-apps/api` v2 peer dependency. Local installs require the package's
`dist/` output; a fresh clone is not a prebuilt npm artifact.

## Browser / desktop example

Import the CSS **before mounting** and keep a loading/retry UI outside the gated shell:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<div id="loading" role="status">Loading…</div>
<main id="shell" data-layout-root>
  <section class="layout-content-host"><!-- app content and its overlays --></section>
</main>
```

```ts
import 'tauri-plugin-iphone-duo-layout/style.css';
import { createLayoutObserver } from 'tauri-plugin-iphone-duo-layout';

const observer = createLayoutObserver({
  root: document.querySelector<HTMLElement>('#shell')!,
  config: { navigationWidth: 240, navigationSide: 'right' },
  onError(error) { /* keep loading UI visible; offer retry or recreate observer */ },
});
const unsubscribe = observer.subscribe(metrics => {
  document.querySelector<HTMLElement>('#loading')!.hidden = true;
  // Render a persistent sidebar when metrics.isSplit; otherwise use an app drawer.
  // Metrics and CSS custom properties already belong to the same animation-frame commit.
});
await observer.start();
// Navigation width changes are configuration, not physical fold events:
observer.configure({ navigationWidth: 96 });
// On unmount: unsubscribe(); await observer.dispose();
```

React can subscribe in an effect and dispose on cleanup. Create a new observer for each
mounted shell; do not recreate the app tree or use posture as a React `key`.

`examples/browser.html` is a standalone CSS-fallback demo. Build first, serve this package
directory over HTTP, open that file, and resize the window. It contains no fake fold API.

## API

```ts
calculateLayout(snapshot: LayoutSnapshot, config?: LayoutConfig): LayoutMetrics
createLayoutObserver(options?: ObserverOptions): {
  start(): Promise<void>;
  getSnapshot(): LayoutMetrics | null;
  subscribe(listener: (metrics: LayoutMetrics) => void): () => void;
  configure(config: LayoutConfig): void;
  dispose(): Promise<void>;
}
createTauriNativeSource(): NativeSource // optional ./tauri entry, iOS only
```

`start()` installs listeners; it does **not** mean the first valid snapshot has arrived.
`getSnapshot()` is null before readiness and while native/DOM dimensions disagree.
`LayoutSnapshot` includes revision, width/height, four safe-area insets, reserved regions,
physical `foldState` (`unknown | folded | half | expanded`) and source.

`LayoutMetrics` includes:

| Field | Meaning |
| --- | --- |
| `viewport`, `safeRect`, `safeArea` | Current local geometry, in CSS pixels |
| `segments`, `pane`, `regions` | Safe rectangles; the largest unobstructed rectangle is selected conservatively |
| `contentRect`, `availableWidth/Height` | Remaining area after **effective** app navigation |
| `mode`, `isSplit`, `navigationWidth` | Wide eligibility; whether persistent navigation is actually reserved |
| `primaryAxis`, `primarySize`, `crossSize` | Orientation and lengths of the remaining content rectangle |
| `overlayInsets` | Four viewport offsets enclosing the selected content area |
| `foldState`, `source`, `revision` | Observations and ordering; posture never selects the layout |

`wide` without navigation (`navigationWidth: 0`) has `isSplit: false`; a wide container
is not a command to split every business screen into columns.

## Default thresholds

| Setting | Default | Rule |
| --- | --- | --- |
| `minWidth` | 600px | Selected safe pane width must be at least this value |
| `minHeight` | 480px | Selected safe pane height must be at least this value |
| `minMainWidth` | 480px | Width remaining after requested navigation must meet this minimum |
| `navigationWidth` | 240px | Requested app-owned sidebar; explicitly use 0 when absent |
| `navigationSide` | right | Left is also supported |
| `debounceMs` | 0 | One-frame coalescing by default; optional trailing debounce |

Thus a 240px sidebar needs **720px of safe pane width**. Compact mode reserves zero
persistent navigation width; the app owns the drawer/bottom-navigation alternative.
These are configurable product defaults, not hardware detection or Tauri standards.
Native size classes and physical hinge state never override the geometry budget.

## Platform support matrix

| Platform | Measurement and policy | Physical posture |
| --- | --- | --- |
| Web, Tauri macOS/Windows/Linux | TS policy + CSS safe-area/viewport observer | `unknown`; no native hinge adapter |
| Tauri iOS 17–27.0 | TS policy + native view bounds/safe area | `unknown`; new UIKit API is skipped |
| Tauri iOS 27.1+ | Same policy + native reserved-region/hinge adapter | Official observation when provided; true three-state transitions not runtime-verified |
| Native SwiftUI iOS 17+ | Standalone Swift measurement package; app keeps its layout policy | Version-guarded observation, same limitations |
| Android | CSS/viewport fallback only in this MVP | `unknown`; no Kotlin fold adapter yet |

The iOS Tauri MVP targets a single host WebView. Native multi-scene/WebView routing is
not implemented; do not share one plugin snapshot across independent iOS windows.
Standalone Swift readers and frontend observers can each be scoped to their own container.

## Tauri iOS setup

Add a path dependency and register the plugin in the app's Rust builder:

```toml
[dependencies]
tauri-plugin-iphone-duo-layout = { path = "/absolute/path/to/tauri-plugin-iphone-duo-layout" }
```

```rust
tauri::Builder::default()
    .plugin(tauri_plugin_iphone_duo_layout::init());
```

Add `"iphone-duo-layout:default"` to the intended window's Tauri capability permissions.
Then supply the iOS adapter to the same observer:

```ts
import { createTauriNativeSource } from 'tauri-plugin-iphone-duo-layout/tauri';
const observer = createLayoutObserver({ root, native: createTauriNativeSource() });
```

Choose this entry using the app's existing platform routing. It is **iOS only**;
do not infer iOS from `isTauri()` alone. Desktop and Android use the CSS source for now.
Missing plugin/ACL permission is reported as an error and does not silently reveal
the iOS shell with zero insets.

The Rust build helper supplies `.tauri/tauri-api` for the Swift package. The frontend
subscribes before reading. In this extracted version, the native reader attaches at
WebView load and remains active for that WebView lifetime to support direct DOM
injection even without an IPC subscription. `stop` decrements IPC subscribers but
does not detach the native reader; frontend `dispose` removes frontend listeners.
Layout/safe callbacks sample immediately; a 10Hz native poll catches reserved-region
changes without a resize. Unchanged values do not produce duplicate events.

### SDK and deployment target are different

Build the native source with **Xcode/iOS SDK 27.1+**. Keep the app deployment target
unchanged: this package's native minimum is iOS 17; host apps keep their own targets.
`if #available(iOS 27.1, *)` guards `UIHingeInteraction` and
`UIView.ReservedRegion`. Old systems use bounds and safe-area measurement. New systems
without a hinge report `unknown`, not `expanded`. The same TS policy handles both paths.
An older SDK cannot compile unknown types just because they have availability guards.

All geometry is local to the observed view. Use the viewport meta above at layout scale
1 and a host WebView that covers the app's intended layout container. The MVP compares
native point dimensions with DOM layout-viewport dimensions (1px tolerance) and waits
if they differ; it never divides by devicePixelRatio or combines a stale native size
with a new DOM size. Arbitrary page zoom/custom viewport scaling is not supported yet.
`visualViewport`/keyboard occlusion is not used as the main-layout breakpoint signal;
keyboard-aware accessory positioning remains with the app.

### Native SwiftUI apps

A native SwiftUI host does not need the npm package or the Tauri bridge. Add the local
Swift package `native/LayoutMetricsNative`, import `LayoutMetricsNative`, retain one
`LayoutSnapshotReader`, set `onChange`, and `attach(to:)` the existing UIKit container
(or a `UIViewRepresentable` host). Call `detach()` on teardown. Its snapshots are in
local points and can feed the app's existing `.adaptive` / split-layout calculation.
This MVP shares the native **measurement**, not a second Swift rendering framework;
the packaged threshold policy is TypeScript.

### SwiftUI Duo 安全区层（`LayoutMetricsNative`，iOS 17+）

接入：Xcode 里 Add Package → Local → `native/LayoutMetricsNative`，target 依赖 `LayoutMetricsNative`。
（也可以把 `Sources/LayoutMetricsNative/` 的 4 个文件直接拷进 app，它们只依赖 SwiftUI / UIKit。）

```swift
import LayoutMetricsNative
WindowGroup {
  RootView()
    .duoSafeArea(bottom: .homeIndicator(reserve: 8))   // 根视图挂一次：安全区 ∩ 屏幕圆角
    .background(Color.paper.ignoresSafeArea())          // 背景照常铺满
}
// 贴近屏幕角的胶囊 / 卡片：Text("Example").padding(8).background(.red, in: Capsule()).duoCornerClipped()
// 按形态排版：@Environment(\.duoLayout) var duo → duo?.state == .half ? 两栏 : 单栏
```

| API | 用在哪 | 做什么 |
| --- | --- | --- |
| `.duoSafeArea(bottom:cornerTolerance:metrics:)` | 根视图（铺满窗口）一次 | 测系统安全区和屏幕圆角，只把**超出系统安全区的部分**（圆角避让）用 `safeAreaPadding` 追加。ScrollView 的 adjustedContentInset、`safeAreaInset(edge: .bottom)` 输入栏和键盘仍各算一次，不会重复计入。`bottom: .homeIndicator(reserve:)` 把系统底边换成 reserve |
| `.duoCornerClipped()` | 贴屏幕角的背景（胶囊、卡片、整页底色） | 按视图在窗口中的位置，算出与屏幕圆角同心的四角半径（R − 离角距离），再用 `UnevenRoundedRectangle(.continuous)` 裁切；测不到圆角时退回 `ContainerRelativeShape` |
| `DuoLayoutMetrics` / `@Environment(\.duoLayout)` | 需要按形态改排版的页面 | `state`（folded / half / expanded / notFoldable）、四边 `safeArea`、`cornerRadius`、`contentInsets(bottom:)`、`stateBasis`（判定依据） |

**圆角（逐角）**：取值用 iOS 26 公开 API。在窗口里临时放一个铺满窗口、`cornerConfiguration = .corners(radius: .containerConcentric())` 的视图，**逐角**读 `effectiveRadius(corner:)`，结果在 `DuoLayout.cornerRadii`。折叠屏各角不同：Duo 外屏实测铰链侧 8pt、外侧 59pt，设备 profile 写明内屏四角 55pt。取最大值会在铰链侧多让出约 17pt，所以只有 `cornerRadius`（最大值）是为了兼容而保留。iOS 17–25 用 `UIScreen._displayCornerRadius` 兜底（先 `responds(to:)` 再取；传 `DuoLayoutMetrics(allowPrivateCornerFallback: false)` 可禁止采用私有值；当前实现仍会查询该属性，要完全避免私有查询尚需修正代码）。都取不到时为 nil，此时不做圆角避让。代码里没有写死任何机型数值。

**圆角避让规则**：如果安全区矩形某个角越过**该角自己的**圆弧超过 `cornerTolerance`（默认 6pt），就把这个角相邻的两条边都至少抬到 R·(1−1/√2)。这样算出的边距只会比系统安全区大，不会更小（底边策略除外）。

**三态判定（只看运行时观测，不看机型）**：
1. iOS 27.1 `UIHingeInteraction`：closed → folded，partiallyOpen → half，fullyOpen → expanded；
2. 没有铰链状态、但窗口里有 division 保留区（折痕）：保留区 active → half，否则 expanded；
3. 两者都没有 → `notFoldable`。

尺寸、宽高比和保留区数量只写进 `stateBasis` 供核对。实测半开和展开的窗口几何完全相同（都是 951×669、安全区 T0/L0/B34/R84），所以单靠几何区分不了这两态。

**非折叠设备的退化**：`notFoldable` 时不改排版逻辑。普通 iPhone 竖屏底角只越过圆弧约 4pt，小于容差，结果等于系统安全区。

**不要**：子视图里再 `.padding(safeArea)`；底部输入栏用 `.padding(.bottom, safeArea.bottom)` 叠加（应该用 `.safeAreaInset(edge: .bottom)`）；在 `.duoSafeArea()` 之外使用 `.duoCornerClipped()`。

纯几何断言在 macOS 上直接跑，不需要模拟器：
`swiftc -parse-as-library native/LayoutMetricsNative/Sources/LayoutMetricsNative/DuoGeometry.swift verification/duo/DuoGeometryCheck.swift -o /tmp/duo-geo && /tmp/duo-geo`。
Duo 实机验证样例和截图在 `verification/duo/`（见其 `results.md`）。

## First frame, updates and overlays

The CSS keeps `[data-layout-root]` hidden before JavaScript runs. With the iOS adapter,
no CSS-zero-inset fallback is rendered while waiting for a valid native layout snapshot.
In one animation-frame commit, the observer publishes all geometry CSS variables and
only then sets `data-layout-ready="true"`. A 530ms bridge delay is a test case, never
a production timeout or a claim that UIKit settles within three frames.

Legitimate all-zero native insets are valid. Readiness means attached, nonzero native
layout matching the DOM, not “some inset must be nonzero”. A later safe-area change
publishes another snapshot. After 5s without an initial valid snapshot, `onError` is
called and the shell stays gated; the app must offer a loading/retry/error UI.
CSS-only mode is explicitly best effort: CSS has no authoritative native-ready signal.

Resize, orientation and ResizeObserver signals are merged, with a 100ms CSS poll for
inset-only changes. Insets can change without width/height changes. Dispose removes all
listeners, timers, pending frames and native subscriptions. Expensive graph work can
debounce downstream; there is no mandatory 300/530ms layout wait.

Place floating buttons, bottom toolbars, toasts and drawers inside the content host
(or constrain a portal with `contentRect`/`overlayInsets`). Keep the sidebar in its own
`pane` slot. Do not add safe-area padding again inside already-constrained components.
OS navigation already represented by safeArea must not also be passed as app navigation.
Active regions are subtracted once; inactive creases remain metadata. The largest-pane
policy is conservative and does not implement a multi-pane spanning UI.

## Scope and verification

Shared: measurement, snapshot ordering, safe-area/reserved-area subtraction, configurable
thresholds, event coalescing, first-frame gate and geometry tokens.
App-owned: navigation content/width declaration, columns, graph rendering, conversations,
drawer behavior, focus/scroll preservation, keyboard controls and visual acceptance.

```sh
npm test          # policy, boundary, ordering, lifecycle, delayed-native and IPC tests
npm run example   # 8 exact numeric scenarios
cargo check      # host Rust plugin registration and generated permissions
```

The delayed tests use a DOM harness and synthetic snapshots; they are not WKWebView or
real hinge tests. The Swift compile fixture is in `verification/`; it builds the actual
Tauri Swift bridge and native reader with an **iOS 17 deployment target**, without
signing, linking a business app, installing or launching anything.

On an isolated Mac build copy with XcodeGen and XcodeBuildMCP installed:

```sh
export TAURI_IOS_API_PATH=/path/to/tauri-2.x/mobile/ios-api
export LAYOUT_SIMULATOR_ID=<available-simulator-uuid>
bash verification/check-native.sh
```

See [verification/results.md](verification/results.md) for the actual results and limits.
True closed/half/open transitions and real-device reserved-region behavior remain
unverified; this library does not turn earlier synthetic data into physical evidence.

## Example integration outline (not performed)

For a Tauri/React shell (`<your-app>`): add the local package to `package.json` and its
lockfile; initialize/dispose in the app entry component; import the initial gate CSS in
the existing global CSS entry; constrain portals and overlays using the shared content
boundary. Its desktop path needs no iOS bridge.
For a future Tauri iOS host, also add the Cargo path dependency, builder registration
and the capability permission above. Do not edit generated Apple project files by hand.
For a native SwiftUI app: add the Swift package to the Xcode project, add a small
retained measurement host near the app root, and feed its geometry into the root view.
Keep the app's existing adaptive layout.

References: [Tauri mobile plugin development](https://v2.tauri.app/develop/plugins/develop-mobile/),
[UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction),
[UIView.ReservedRegion](https://developer.apple.com/documentation/uikit/uiview/reservedregion).
Public API declarations were also checked against the installed iOS SDK headers.
