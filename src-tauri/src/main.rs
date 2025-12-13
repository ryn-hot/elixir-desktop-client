#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let version = app.package_info().version.to_string();
            println!("Starting Elixir client {}", version);
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
