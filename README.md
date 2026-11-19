# tauri-plugin-iphone-duo-layout

iPhone Duo is an Apple product name. This is a third-party adaptation with no affiliation with Apple.
iPhone is a trademark of Apple Inc.; the package name identifies its compatibility target and does not imply Apple endorsement or authorization.

[简体中文](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/README.zh-CN.md) · [Integration details](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/docs/integration.md)

## Overview

MIT licensed. A Tauri v2 iOS plugin, frontend measurement helpers and a standalone Swift package.

A web page knows its viewport size, but that alone does not identify the active
Duo display, its native safe area, its corner shape, or its hinge state. CSS
`env(safe-area-inset-*)` can expose insets in some host configurations; it is not a
complete replacement for a native measurement bridge. Earlier app adaptation work
encountered controls under the right system area, a bottom bar flush with the
screen edge, and backgrounds extending past a display corner.

This package supplies those measurements and a configurable frontend policy. The
app still owns its navigation, columns, spacing and interaction design.

## How it works

```text
UIKit view in its current window
  bounds + safeAreaInsets + corners + hinge/reserved regions
                         |
             Swift snapshot / JSON bridge
                         |
  window.__duoMetrics + duo-metrics event   (or Tauri change + get_snapshot)
                         |
  frontend observer -> CSS variables / layout snapshot -> app applies its UI
```

### Read the view that is actually on screen

UIKit is iOS's native view system. The reader attaches to the host `WKWebView`
(the native view containing the page) and reads its `bounds` for local size and
`safeAreaInsets` for the top/right/bottom/left space the system asks content to
avoid. These distances are in **points**, iOS's logical units, not screenshot pixels.
The SwiftUI helper uses the same reader through a UIKit view; it does not invent a
second set of safe-area values.

The window containing that view identifies its display through `view.window.screen`.
The code does **not** pick a display called `LCD` or `LCD-1`, or assume that the
first screen is active. Those names belong to the simulator capture tooling: LCD
was the outer display and LCD-1 the inner display in the historical runs. A change
of window, screen identity or window size invalidates the cached corner measurement.
The reported width/height are the view's bounds, not an assertion that the app fills
the entire physical display.

For corners, iOS 26+ supplies a public measurement path: place a temporary,
window-sized view with `containerConcentric()` corner configuration, then read
`effectiveRadius(corner:)` separately for all four corners. “Concentric” means the
probe follows the containing display's curve. `cornerRadii` preserves each corner;
`cornerRadius` is their maximum for older consumers. A zero-radius corner is valid.
On iOS 27.1+, `UIHingeInteraction` observes closed/partially-open/fully-open state;
reserved regions describe creases or obstructed rectangles, including whether they
currently block content. A width threshold cannot distinguish half-open from open.

### Deliver changes to the page

Tauri calls the Swift plugin's `load(webview:)`; the plugin schedules attachment on
the main UI thread. The reader waits until its probe has laid out, belongs to a
window, and has nonzero bounds. Each changed snapshot is sent through
`evaluateJavaScript`: it assigns **`window.__duoMetrics`** and dispatches
**`duo-metrics`**, with that same object in `event.detail`. The object includes the
native snapshot plus `adjustedInsets` (space already consumed by the WebView's
scroll container) and `viewportWidth/Height` (bounds minus those consumed insets).

This is **not a document-start script**, and it is not scheduled by `DOMContentLoaded`.
It can run before or after frontend setup; injection before the first page script
is not guaranteed. `observeDuoSafeArea()` reads an existing global immediately and
then listens for changes. Navigation/reload has no dedicated reinjection hook;
a page can miss the global until a later native change. For the full observer path,
`createTauriNativeSource()` subscribes to Tauri's `change` event before calling
`start`, then reads `get_snapshot`, so it need not rely on the initial DOM event.

Hinge updates, native layout and safe-area callbacks sample again. A display link
(an iOS timer tied to screen updates), limited to 10Hz here, catches other changes.
Only changed native values get a new revision and another notification; the app is
not remounted when the hinge moves. Native sampling remains attached for the
WebView lifetime; `stop` currently changes the IPC subscriber count only.

### Let the app apply the result

`observeDuoSafeArea()` publishes `--duo-*` CSS variables; it does not add app padding.
App CSS should reserve only the inset **not already consumed** by UIKit, rather
than adding the system inset twice. `createLayoutObserver()` is the optional policy
path: subtract safe areas, active reserved regions and declared navigation, then
publish content bounds and compact/wide mode. Its supplied gate CSS hides the shell
until geometry is ready. With native measurement, it waits for native/DOM dimensions
to agree within 1px; an error keeps the loading/retry UI visible.

Source: [native sampling](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/native/LayoutMetricsNative/Sources/LayoutMetricsNative/LayoutSnapshotReader.swift#L98),
[corner reader](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/native/LayoutMetricsNative/Sources/LayoutMetricsNative/DisplayCornerRadius.swift#L23),
[JSON injection](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/ios/Sources/LayoutMetricsPlugin.swift#L42), [Duo CSS helper](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/src/duo.ts#L73),
[IPC adapter](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/src/tauri.ts#L5), [frontend observer](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/src/observer.ts#L54).

### Observed geometry, with evidence boundaries

These are **historical simulator runtime measurements**, not copied hardware
specifications or physical-device test results. Dimensions and insets vary with
orientation, host configuration and OS version; they are examples, not constants
the native reader uses to recognize a Duo.

| Observation | Historical value (pt) | Evidence / remaining check |
| --- | --- | --- |
| Closed outer view / capture display | 466×678 / LCD | Historical native demo reading; raw capture data is not included |
| Half-open / open inner view | 951×669 / LCD-1 | Earlier application-adapter simulator receipt; current package needs both states repeated |
| Outer maximum corner radius | 59 | Historical public-API sample: TL/TR/BL/BR = **8/59/8/59**, not four 59pt corners |
| Inner corner radius | 55 | Earlier adapter reports scalar public-API reading; simulator profile lists four 55pt corners; current package's inner per-corner sample is pending |
| Right safe inset / outer safe line | 84 / **466−84=382** | System-reported inset; the width budget ends at x=382 before app navigation |
| Bottom safe inset | 34 | System value; a demo's optional 8pt bottom reserve is an app policy, not a measured system inset |

These values come from historical simulator runs of this package's native reader.
The earlier adapter reported the same 34pt bottom and 84pt right inset in all three
states. This does not establish that every host consumes those insets in the same way.

## Design notes

- **Facts before layout.** Native measurement is reusable across design systems.
  Fold state is metadata; available space determines the optional compact/wide
  policy. Apps can use just the measurements and supply their own policy. The
  current bridge also makes the WebView transparent and clips it using the scalar
  radius; this native appearance side effect is separate from app layout.
- **Unknown is not expanded.** Until a view has laid out, there is no snapshot.
  No hinge API/data means `unknown` in the raw snapshot; the SwiftUI classifier
  can use division regions, otherwise reports `notFoldable`. All-zero safe insets
  are valid and do not mean measurement failed.
- **Different fallbacks serve different consumers.** The Swift corner reader
  returns no corner value if neither the public API nor an allowed private
  fallback supplies one. Native geometry then retains system safe areas without
  inventing a radius. The legacy JS helper instead uses a configurable radius,
  or 59pt when the right inset is at least 64pt, otherwise 0. Set
  `fallbackCornerRadius: 0` to disable that guess. It does not choose 55pt from
  an inner-screen model: missing inner data can therefore use 59pt if that
  legacy fallback condition holds.

## Install the Rust plugin

The Rust plugin is available on [crates.io](https://crates.io/crates/tauri-plugin-iphone-duo-layout).
From your app's Rust project (usually `src-tauri`), run:

```sh
cargo add tauri-plugin-iphone-duo-layout
```

The npm package has **not been published**. Clone this repository and use the
locally built path/tarball dependency below for the frontend bindings.

## Build and demo

Prerequisites: Node.js 20+, npm, Python 3 (demo server). Rust/Cargo is needed only for
the optional Tauri host check; native iOS compilation requires Xcode/iOS SDK 27.1+.

```sh
cd /absolute/path/to/tauri-plugin-iphone-duo-layout
npm ci
npm test
npm run example
npm run demo
```

Open <http://127.0.0.1:8765/examples/browser.html> and resize the browser.
The demo uses real browser geometry and generic UI text. The matrix command uses
synthetic geometry. Neither verifies physical hinge transitions.

## One dependency and a small initialization

Build a portable npm artifact (the prepack hook builds `dist/` automatically):

```sh
cd /absolute/path/to/tauri-plugin-iphone-duo-layout
npm pack
```

From a frontend app, install in one line:

```sh
npm install /absolute/path/to/tauri-plugin-iphone-duo-layout/tauri-plugin-iphone-duo-layout-0.1.1.tgz
```

With a bundler, import before mounting:

```ts
import 'tauri-plugin-iphone-duo-layout/style.css';
import { createLayoutObserver } from 'tauri-plugin-iphone-duo-layout';

const observer = createLayoutObserver({ root: document.querySelector<HTMLElement>('#shell')! });
const unsubscribe = observer.subscribe(metrics => renderLayout(metrics)); // app callback
await observer.start();
// On unmount: unsubscribe(); await observer.dispose();
```

Use `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`,
`<main id="shell" data-layout-root>` and a child `.layout-content-host` for constrained content.
Keep a loading/error UI outside the gated shell. `start()` installs listeners; the first
valid snapshot sets `data-layout-ready="true"`. Default navigation reservation is 240px;
set `config: { navigationWidth: 0 }` if your app reserves navigation itself.

For an existing `window.__duoMetrics` bridge, one initialization handles CSS tokens:

```ts
import { observeDuoSafeArea } from 'tauri-plugin-iphone-duo-layout';
const dispose = observeDuoSafeArea(document.documentElement);
// On unmount: dispose();
```

This helper consumes bridge values; it does not install the native bridge. It emits
`--duo-*` tokens for app CSS. See the integration notes for all injected fields and tokens.

## Optional Tauri iOS adapter

The frontend-only path needs no Rust dependency. For native iOS measurement add:

```toml
[dependencies]
tauri-plugin-iphone-duo-layout = "0.1"
```

Register `.plugin(tauri_plugin_iphone_duo_layout::init())` in the existing Rust builder,
and add `"iphone-duo-layout:default"` to the intended window's capability permissions.
Then initialize on the app's **iOS route only**:

```ts
import { createTauriNativeSource } from 'tauri-plugin-iphone-duo-layout/tauri';
const observer = createLayoutObserver({ root, native: createTauriNativeSource() });
await observer.start();
```

The Swift plugin emits `change` and injects `window.__duoMetrics` plus `duo-metrics`.
iOS 17 is the plugin deployment minimum; newer SDK types are availability guarded.
Desktop/Android use CSS measurements, with fold state `unknown`.
Tauri requires both frontend installation and native registration/ACL; a single npm
dependency alone does not enable native measurement.

Native SwiftUI hosts can add local package `native/LayoutMetricsNative`, import
`LayoutMetricsNative`, and apply `.duoSafeArea()` at their root. This is independent
of the npm/Tauri bridge. Details and private corner fallback options are in the integration notes.

## Verify from a clean directory

```sh
source_dir=/absolute/path/to/tauri-plugin-iphone-duo-layout
check_dir=$(mktemp -d /tmp/iphone-duo-layout-clean.XXXXXX)
cd "$source_dir"
git archive HEAD | tar -x -C "$check_dir"
cd "$check_dir"
npm ci
npm test
npm run example
npm pack
mkdir consumer
cd consumer
npm init -y
npm install ../tauri-plugin-iphone-duo-layout-0.1.1.tgz
node --input-type=module -e "import {calculateLayout} from 'tauri-plugin-iphone-duo-layout'; console.log(typeof calculateLayout)"
cd ..
npm run demo
```

Open the same demo URL. For the optional Rust path run `cargo check --locked` in
the clean package directory. Native iOS compile instructions and historical evidence
are in [verification](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/verification/results.md); the current clean-run scope is recorded
in [clean-room results](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/verification/clean-room.md). No simulator launch is needed for
frontend/package checks.

## Limitations

- The plugin and Swift package require iOS 17+. Public corner measurement needs
  iOS 26+, and hinge/reserved-region APIs need iOS 27.1+; building the current
  source requires an iOS SDK that contains those newer APIs.
- This extracted package has not completed native three-state revalidation or
  physical-device testing. The inner-screen per-corner sample remains pending;
  a scalar or the legacy 59pt fallback can over-reserve smaller corners.
- Other foldables, Android native hinge measurement, arbitrary viewport zoom and
  native multi-window routing are unverified or unsupported here. Browser/desktop/
  Android CSS fallback reports `unknown` posture and zero insets when CSS provides none.
- The corner reader has an optional private `UIScreen._displayCornerRadius`
  fallback. In the current implementation, `allowPrivateCornerFallback = false`
  prevents choosing that value but still performs the private query. Avoiding the
  query entirely requires a code fix before claiming a public-API-only build.
- There is no document-start/reload reinjection guarantee. The scalar native
  WebView clip and lifetime-long native sampling also need app-level acceptance.
- The Rust crate is published; npm publication is pending. MIT licensing and local installability do
  not by themselves mean this package is ready for public release.

See [integration details](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/docs/integration.md).
