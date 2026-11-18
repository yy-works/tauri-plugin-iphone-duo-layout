# 改名后的干净目录验证（2026-11-18）

包名、Cargo crate、Swift 插件产品、Tauri IPC 标识与权限前缀已统一为 `tauri-plugin-iphone-duo-layout` / `iphone-duo-layout`。
从本次增加 iphone 的改名提交通过 README 的 `git archive HEAD` 导出至 `/tmp/iphone-duo-layout-clean.UR3EL9`；未复制 node_modules、dist 或 target。

- `npm ci`：通过，审计 0 漏洞。
- `npm test`：13/13 通过，包括新 `plugin:iphone-duo-layout|…` 命令链 mock。
- `npm run example`：8/8 精确几何场景通过。
- `npm pack`：通过，prepack 自动构建，产物 `tauri-plugin-iphone-duo-layout-0.1.0.tgz`。
- 新建 `/tmp/iphone-duo-layout-clean.UR3EL9/consumer`，一行 `npm install ../tauri-plugin-iphone-duo-layout-0.1.0.tgz` 通过，按新包名导入 calculateLayout 得到 function。
- Chromium 直接加载 consumer/node_modules 中新包 JS/CSS：1000×800 → wide / 导航240 / 内容760；466×678 → compact / 导航0 / 内容466，ready 且 visible，无页面脚本异常。
- `cargo check --locked`：在该干净目录全新 host 编译通过。
- 首次浏览器 favicon 404；不影响模块、布局或上述断言。

原始回执见 clean-room/。此前旧包的历史原生结果保留在 results.md；
不代表本次已验证新 Swift 绑定或真实铰链三态。本次未运行 iOS 模拟器、安装业务 App、发布任何注册表包。
本次验证范围仍为前端、安装产物、IPC mock 与 macOS Rust host，三态截图及原生安全区数值待应用迁移后复验。
