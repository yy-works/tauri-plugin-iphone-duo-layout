fn main() {
    tauri_plugin::Builder::new(&[
        "start",
        "stop",
        "get_snapshot",
        "register_listener",
        "remove_listener",
    ])
    .ios_path("ios")
    .build();
}
