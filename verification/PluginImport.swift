// Compile the real plugin, Tauri bridge and standalone native reader together.
// A static fixture intentionally does not link a Rust application or launch an app.
import tauri_plugin_iphone_duo_layout
import LayoutMetricsNative

public func layoutMetricsFixturePresent() -> Bool { true }
