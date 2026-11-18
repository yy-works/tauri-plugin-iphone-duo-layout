# tauri-plugin-iphone-duo-layout

iPhone Duo 是 Apple 的产品名，本包为第三方适配，与 Apple 无关联。
iPhone 是 Apple Inc. 的商标；本包名称用于说明适配目标，不表示 Apple 认可或授权。

[English](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/README.md) · [详细接入](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/docs/integration.md)

## 概览

采用 MIT 许可，包含 Tauri v2 iOS 插件、前端度量辅助函数与独立 Swift 包。

网页能知道自己的视口尺寸，但仅凭这个数，无法可靠知道 Duo 当前使用哪块屏、屏幕圆角、
原生安全区或转轴状态。CSS 的 `env(safe-area-inset-*)` 在部分宿主配置下能提供边距，
却不能代替完整的原生测量桥。早期应用适配实际遇到过：按钮被右侧系统区域压住、
底栏贴到屏幕底边，以及背景伸出屏幕圆角。

本包提供度量和可选的前端布局策略。导航、分栏、留白及交互仍由 app 自己决定。

## 工作原理

```text
当前窗口中的 UIKit 原生视图
  尺寸 + 安全区 + 圆角 + 转轴/保留区
                  |
          Swift 快照 / JSON 桥
                  |
  window.__duoMetrics + duo-metrics 事件（或 Tauri change + get_snapshot）
                  |
  前端观测器 -> CSS 变量 / 布局快照 -> app 应用到自己的界面
```

### 测当前真正显示的视图

UIKit 是 iOS 的原生界面系统。测量器挂到 `WKWebView`（承载网页的原生视图）上，
从它的 `bounds` 读本地尺寸，从 `safeAreaInsets` 读上、右、下、左四边需要避让的空间。
数值单位是 **pt（点，iOS 的逻辑尺寸）**，不是截图像素。SwiftUI 辅助层也通过 UIKit 视图
使用同一测量器，没有另造一份安全区。

当前屏幕跟随这个视图所在的窗口，即 `view.window.screen`；代码不按 `LCD` / `LCD-1`
名称选屏，也不假定第一块屏就是激活屏。这两个名字来自模拟器截图工具：历史回执中 LCD
对应外屏，LCD-1 对应内屏。窗口、屏幕身份或窗口尺寸改变时，会重新测圆角。
输出的宽高是被测视图尺寸，不能直接等同于物理屏幕总尺寸。

圆角优先用 iOS 26+ 的公开接口：临时放一个铺满窗口的视图，将圆角配置为
`containerConcentric()`，再逐角调用 `effectiveRadius(corner:)`。
“同心圆角”就是让探针曲线跟随所在屏幕的圆弧。`cornerRadii` 保留四个角各自的值，
兼容字段 `cornerRadius` 取四角最大值；某个角为 0 本身是合法读数。
iOS 27.1+ 的 `UIHingeInteraction` 监听转轴闭合、半开、展开；保留区则描述折痕或遮挡矩形，
并注明当前是否占用空间。半开和展开可能同尺寸，不能靠宽度把它们区分开。

### 把变化交给网页

Tauri 调用 Swift 插件的 `load(webview:)` 后，插件在主线程（iOS 更新界面的线程）挂接测量器。
探针必须已完成原生布局、挂到窗口且宽高非零，才会产出快照。
变化的快照经 `evaluateJavaScript` 写入 **`window.__duoMetrics`**，再发送
**`duo-metrics`** 事件，`event.detail` 是同一份数据。桥还附加
`adjustedInsets`（WebView 滚动容器已经吃掉的边距）以及 `viewportWidth/Height`
（视图宽高减去这些已消费边距）。

这**不是页面开始加载前的脚本注入**，也不是由 `DOMContentLoaded` 触发；
它可能早于或晚于前端初始化，不能保证第一段页面脚本运行前已有数据。
`observeDuoSafeArea()` 会先读取已存在的全局对象，再监听变化。
当前没有专门的导航/刷新重注入钩子，网页刷新后可能要等下一次原生变化才重新得到全局对象。
完整观测器使用的 `createTauriNativeSource()` 会先订阅 Tauri 的 `change`，再调用 `start`，
随后读 `get_snapshot`，因此不必只依赖最初那次 DOM 事件。

转轴更新、原生布局和安全区回调都会重新采样；另有 10Hz 的 display link
（跟随屏幕更新的 iOS 定时回调）补查其它变化。只有读数变化时才增加快照编号并重新注入/推事件，
折叠时不重建整个 app。原生采样保持到 WebView 生命周期结束；目前 `stop` 只调整 IPC 订阅计数。

### 由 app 应用度量

`observeDuoSafeArea()` 写入 `--duo-*` CSS 变量，不替 app 加 padding。
使用方 CSS 应只补 UIKit **尚未消费**的安全区，避免同一边距加两次。
`createLayoutObserver()` 是另一条可选策略路径：扣除安全区、正在占用的保留区和声明的导航，
给出内容矩形以及 compact/wide 模式。配套 gate CSS（就绪前隐藏外壳的样式）等待几何有效后显示内容；
启用原生源时，还会等待原生与 DOM 尺寸误差不超过 1px，失败时保留加载/重试界面。

依据：[原生采样](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/native/LayoutMetricsNative/Sources/LayoutMetricsNative/LayoutSnapshotReader.swift#L98)、
[圆角读取](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/native/LayoutMetricsNative/Sources/LayoutMetricsNative/DisplayCornerRadius.swift#L23)、
[JSON 注入](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/ios/Sources/LayoutMetricsPlugin.swift#L42)、[Duo CSS 辅助函数](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/src/duo.ts#L73)、
[IPC 适配](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/src/tauri.ts#L5)、[前端观测器](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/src/observer.ts#L54)。

### 历史测量值及证据边界

以下来自**模拟器中原生代码的历史运行读数**，并非抄写硬件规格，也不是实体真机验收。
方向、宿主和系统版本变化都可能改变数值；表格是例子，不是原生层识别机型的常量。

| 测量项 | 历史值（pt） | 来源 / 尚需确认 |
| --- | --- | --- |
| 闭合外屏视图 / 截图屏名 | 466×678 / LCD | 原生 demo JSON 及模拟器回执 |
| 半开 / 展开内屏视图 | 951×669 / LCD-1 | 早期应用桥的模拟器回执；当前包仍需分别复验 |
| 外屏最大圆角 | 59 | 随仓公开 API 样本：左上/右上/左下/右下为 **8/59/8/59**，不是四角都为59 |
| 内屏圆角 | 55 | 早期应用桥回执报告公开 API 标量值；模拟器配置记四角55；当前包内屏逐角样本待补 |
| 右安全区 / 外屏安全线 | 84 / **466−84=382** | 系统边距；未扣 app 导航时，内容右界为 x=382 |
| 底安全区 | 34 | 系统值；demo 可选的8pt底边预留是 app 策略，不是系统测量值 |

这些数值来自本包原生读取器在模拟器中的历史运行读数。早期应用桥回执中三态均为底34、右84pt，
但这不代表每个宿主都以相同方式消费这些边距。

## 设计取舍

- **先提供事实，再由 app 排版。** 同一份测量可供不同设计系统使用。
  折叠态只作观测；可用空间决定可选的 compact/wide 策略，app 也可以完全自行判定布局。
  当前桥还会将 WebView 设为透明并用标量半径裁剪，这是原生外观副作用，需要和 app 排版区分。
- **未知不等于展开。** 尚未布局时没有快照；缺少转轴接口或数据时，原始快照为 `unknown`。
  SwiftUI 分类器可参考折痕保留区，否则为 `notFoldable`。安全区四边都为0是合法情况，不代表读取失败。
- **回退分层处理。** Swift 圆角层在公开接口和允许的私有回退都无值时返回空值，
  原生几何层保留系统安全区，不凭空造半径。兼容 JS helper 则先用调用方传入的回退半径，
  否则在右安全区至少64pt时用59pt，其余为0。传 `fallbackCornerRadius: 0` 可禁用这次猜测。
  它不会根据内屏型号自动取55pt：缺少内屏读数时，只要符合上述条件，也可能回退成59pt。

## 构建与 demo

需要 Node.js 20+、npm，demo 服务需要 Python 3。可选 Rust 检查需要 Cargo；
iOS 原生编译需要 Xcode / iOS SDK 27.1+，插件最低部署目标仍为 iOS 17。

```sh
cd /absolute/path/to/tauri-plugin-iphone-duo-layout
npm ci
npm test
npm run example
npm run demo
```

打开 <http://127.0.0.1:8765/examples/browser.html>，缩放窗口检查 compact/wide 与导航占位。
demo 只含通用界面文案，矩阵使用合成数据，均不能代替物理铰链三态验证。

## 一行依赖与少量初始化

源码目录运行 `npm pack`，会自动构建 `dist/`。在使用方安装：

```sh
npm install /absolute/path/to/tauri-plugin-iphone-duo-layout/tauri-plugin-iphone-duo-layout-0.1.0.tgz
```

使用现有前端构建器，在挂载前导入：

```ts
import 'tauri-plugin-iphone-duo-layout/style.css';
import { createLayoutObserver } from 'tauri-plugin-iphone-duo-layout';
const observer = createLayoutObserver({ root: document.querySelector<HTMLElement>('#shell')! });
const unsubscribe = observer.subscribe(metrics => renderLayout(metrics)); // 使用方的渲染回调
await observer.start();
// 卸载时：unsubscribe(); await observer.dispose();
```

HTML 需有 `viewport-fit=cover`，根容器加 `data-layout-root`，内容区加 `.layout-content-host`。
加载及重试界面放在根容器外。`start()` 只代表监听已安装，第一份有效快照才设置
`data-layout-ready="true"`。导航默认占 240px；使用方自行占位时设 `config: { navigationWidth: 0 }`。

已有 `window.__duoMetrics` 原生桥时，可用 `observeDuoSafeArea(document.documentElement)`
同步 `--duo-*` CSS 变量，卸载时调用返回的清理函数。它负责消费数据，原生桥需另行接入。

## Tauri iOS 原生接入

```toml
[dependencies]
tauri-plugin-iphone-duo-layout = { path = "/absolute/path/to/tauri-plugin-iphone-duo-layout" }
```

Rust builder 加 `.plugin(tauri_plugin_iphone_duo_layout::init())`，对应窗口 capability 加
`"iphone-duo-layout:default"`。前端仅在 iOS 路由上启用：

```ts
import { createTauriNativeSource } from 'tauri-plugin-iphone-duo-layout/tauri';
const observer = createLayoutObserver({ root, native: createTauriNativeSource() });
await observer.start();
```

插件发送 `change`，同时注入 `window.__duoMetrics` 与 `duo-metrics` 事件。
原生测量仍需要 Rust 注册和 ACL，不能只装 npm 依赖。桌面、Android 用 CSS 回退，折叠态为 unknown。
原生 SwiftUI 可添加本地 Swift 包 `native/LayoutMetricsNative`，根视图挂 `.duoSafeArea()`；
无需 npm。私有圆角 API 回退的关闭方式及生命周期见详细接入文档。

## 干净目录复现

完整的 `git archive → npm ci → npm test → npm run example → npm pack → 新 consumer 安装 → demo`
命令与英文 README 的 “Verify from a clean directory” 一致；验证结果及实际目录见
[干净目录回执](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/verification/clean-room.md)。可选 Rust 检查为 `cargo check --locked`。
iOS 编译参考 [历史证据](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/verification/results.md)，历史结果不代表本次已验证原生三态。

## 已知限制

- 插件和 Swift 包最低为 iOS 17；公开圆角测量需要 iOS 26+，转轴与保留区接口需要 iOS 27.1+。
  编译当前源码需要包含这些新接口的 iOS SDK。
- 当前抽包后尚未完成原生三态复验，也没有实体真机验收。内屏逐角样本待补；
  标量半径或兼容层的59pt回退会对小圆角过度避让。
- 其它折叠屏未验证；没有 Android 原生转轴桥，不支持任意网页缩放及原生多窗口路由。
  浏览器/桌面/Android 的 CSS 回退报告 unknown 折叠态；CSS 无边距时四边为0。
- 圆角读取器含可选的私有 `UIScreen._displayCornerRadius` 回退。当前实现中，
  `allowPrivateCornerFallback = false` 只禁止选用该值，仍会执行私有查询；
  要声称“完全只用公开接口”，必须先修正这处实现。
- 不保证页面开始加载前或刷新后立即注入；WebView 的标量裁剪和持续原生采样也需使用方验收。
- 注册表发布仍待完成。MIT 与本地可安装不代表已经完成公开发布。

详见[详细接入](https://github.com/yy-works/tauri-plugin-iphone-duo-layout/blob/main/docs/integration.md)。
