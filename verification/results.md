# MVP verification — 2026-11-12 (Asia/Shanghai)

These are implementation checks of this package, not business-app acceptance or
physical hinge measurements. No app layout code was changed and nothing was published.

## Frontend and policy

`npm test`: TypeScript compilation passed; **11 tests passed, 0 failed**.
See [frontend-tests.log](frontend-tests.log) and [matrix.json](matrix.json).
The matrix invokes the built `calculateLayout` function and asserts exact results.
Safe-area order below is top/right/bottom/left. Available size is after safe areas
and the effective app-owned navigation. Navigation disappears in compact mode.

| Viewport | Safe area | Requested navigation | Available content | Mode | Persistent split |
| --- | --- | ---: | --- | --- | --- |
| 466×678 | 32/84/34/0 | 0 | 382×612 | compact | false |
| 466×678 | 32/84/34/0 | 96 | 382×612 | compact | false |
| 466×678 | 56/96/40/12 | 0 | 358×582 | compact | false |
| 466×678 | 56/96/40/12 | 96 | 358×582 | compact | false |
| 951×669 | 32/84/34/0 | 0 | 867×603 | wide | false |
| 951×669 | 32/84/34/0 | 96 | 771×603 | wide | true |
| 951×669 | 56/96/40/12 | 0 | 843×573 | wide | false |
| 951×669 | 56/96/40/12 | 96 | 747×573 | wide | true |

Additional assertions cover inclusive 600×480 boundaries, default 240px navigation
requiring 720px safe width, custom thresholds, left/right navigation, active/inactive
reserved regions, invalid geometry, zero insets, stale revisions, safe-only changes,
frame coalescing, disposal, CSS fallback and official Tauri IPC mock command ordering.
DOM tests with bridge delays of 0 and 530ms keep the shell hidden before a snapshot;
the first visible frame has 382px content width, never a visible zero-inset layout.
These are JSDOM/synthetic tests, not a new WKWebView run or an elapsed-time guarantee.

## Native compile

Machine: local macOS build host. Xcode 27.2 / iOS SDK 27.2.
The actual Tauri Swift plugin and the standalone native reader compiled together via
`xcodebuildmcp simulator build`, using the fixture in this directory.

Final result: **SUCCEEDED**, `didError: false`, **0 errors, 0 warnings** in the final
incremental build (3279ms). Deployment target was explicitly **iOS 17.0**; native
compile commands contained `-target arm64-apple-ios17.0-simulator`.
No simulator was booted and no application was installed or launched.

- [Final build output](native-check-final.log)
- Tauri Rust API checked with `cargo check --offline`: passed (Tauri 2.12.5).
- `cargo fmt --check`: passed. Frontend peer API used in tests: 2.12.0.

The first successful native build exposed a Codable warning in this package, fixed
by making the outgoing snapshot Encodable-only. The final run above compiled the corrected source. An upstream Tauri
warning appeared in the first build and was not emitted in the incremental final run.

## Limits

Physical closed/half/open transitions, real reserved-region geometry, native runtime
bridge invocation, full iOS Rust/Swift app linking, iOS 17 runtime execution and
business UI/animation acceptance remain unverified in this delivery. The standalone
reader is compiled with availability guards, not claimed as tested on every OS.
The Tauri iOS adapter supports one host WebView; Android has CSS fallback only.
SwiftUI apps can reuse measurement, but the threshold implementation is TypeScript.
