#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::{
    collections::HashMap,
    process::{Child, Command, Stdio},
    sync::Mutex,
    time::{Duration, Instant},
};

use mdns_sd::{ServiceDaemon, ServiceEvent};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use serde::Serialize;
use std::ffi::CStr;
use vlc::{self, sys, MediaPlayerAudioEx};
use which::which;

#[derive(Serialize)]
struct MdnsDiscovery {
    name: String,
    host: String,
    port: u16,
    addresses: Vec<String>,
}

#[derive(Default)]
struct PlayerState {
    child: Mutex<Option<Child>>,
}

struct LibVlcPlayer {
    instance: vlc::Instance,
    player: Mutex<vlc::MediaPlayer>,
}

unsafe impl Send for LibVlcPlayer {}
unsafe impl Sync for LibVlcPlayer {}

impl LibVlcPlayer {
    fn new() -> Result<Self, String> {
        let instance = vlc::Instance::new().ok_or("failed to create libvlc instance")?;
        let player = vlc::MediaPlayer::new(&instance).ok_or("failed to create media player")?;
        Ok(Self {
            instance,
            player: Mutex::new(player),
        })
    }

    fn is_playing(&self) -> Result<bool, String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        Ok(player.is_playing())
    }

    fn set_pause(&self, paused: bool) -> Result<(), String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        player.set_pause(paused);
        Ok(())
    }

    fn audio_tracks(&self) -> Result<Vec<TrackOption>, String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        let desc = player.get_audio_track_description().unwrap_or_default();
        Ok(desc
            .into_iter()
            .map(|t| TrackOption {
                id: t.id,
                name: t.name.unwrap_or_else(|| "Unknown".to_string()),
            })
            .collect())
    }

    fn current_audio_track(&self) -> Result<i32, String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        Ok(unsafe { sys::libvlc_audio_get_track(player.raw()) })
    }

    fn set_audio_track(&self, id: i32) -> Result<(), String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        unsafe {
            sys::libvlc_audio_set_track(player.raw(), id);
        }
        Ok(())
    }

    fn subtitle_tracks(&self) -> Result<Vec<TrackOption>, String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        let p0 = unsafe { sys::libvlc_video_get_spu_description(player.raw()) };
        if p0.is_null() {
            return Ok(Vec::new());
        }
        let mut results = Vec::new();
        let mut p = p0;
        unsafe {
            while !(*p).p_next.is_null() {
                let name = if (*p).psz_name.is_null() {
                    "Unknown".to_string()
                } else {
                    CStr::from_ptr((*p).psz_name).to_string_lossy().into_owned()
                };
                results.push(TrackOption { id: (*p).i_id, name });
                p = (*p).p_next;
            }
            sys::libvlc_track_description_list_release(p0);
        }
        Ok(results)
    }

    fn current_subtitle_track(&self) -> Result<i32, String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        Ok(unsafe { sys::libvlc_video_get_spu(player.raw()) })
    }

    fn set_subtitle_track(&self, id: i32) -> Result<(), String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        unsafe {
            sys::libvlc_video_set_spu(player.raw(), id);
        }
        Ok(())
    }

    fn set_drawable(&self, window: &tauri::Window) -> Result<(), String> {
        let handle = window
            .window_handle()
            .map_err(|e| e.to_string())?
            .as_raw();
        let player = self.player.lock().map_err(|e| e.to_string())?;
        match handle {
            RawWindowHandle::AppKit(h) => {
                let view = h.ns_view.as_ptr();
                player.set_nsobject(view.cast());
                Ok(())
            }
            RawWindowHandle::UiKit(h) => {
                let view = h.ui_view.as_ptr();
                player.set_nsobject(view.cast());
                Ok(())
            }
            RawWindowHandle::Xlib(h) => {
                if h.window == 0 {
                    Err("xlib window handle unavailable".into())
                } else {
                    player.set_xwindow(h.window as u32);
                    Ok(())
                }
            }
            RawWindowHandle::Win32(h) => {
                let hwnd = h.hwnd.get();
                player.set_hwnd(hwnd as *mut _);
                Ok(())
            }
            _ => Err("Unsupported platform for embedded libVLC".into()),
        }
    }

    fn play(&self, window: &tauri::Window, url: &str) -> Result<(), String> {
        let media =
            vlc::Media::new_location(&self.instance, url).ok_or("failed to create media")?;
        {
            let player = self.player.lock().map_err(|e| e.to_string())?;
            player.set_media(&media);
        }
        self.set_drawable(window)?;
        {
            let player = self.player.lock().map_err(|e| e.to_string())?;
            player.play().map_err(|_| "libvlc play failed".to_string())?;
        }
        Ok(())
    }

    fn stop(&self) -> Result<(), String> {
        let player = self.player.lock().map_err(|e| e.to_string())?;
        player.stop();
        Ok(())
    }
}

#[derive(Default)]
struct ManagedLibVlc {
    inner: Mutex<Option<LibVlcPlayer>>,
}

impl ManagedLibVlc {
    fn ensure(&self) -> Result<std::sync::MutexGuard<'_, Option<LibVlcPlayer>>, String> {
        let mut guard = self.inner.lock().map_err(|e| e.to_string())?;
        if guard.is_none() {
            if let Ok(player) = LibVlcPlayer::new() {
                *guard = Some(player);
            }
        }
        Ok(guard)
    }
}

#[tauri::command]
fn discover_mdns(timeout_ms: Option<u64>) -> Result<Vec<MdnsDiscovery>, String> {
    let timeout = timeout_ms.unwrap_or(1_200);
    let daemon = ServiceDaemon::new().map_err(|e| e.to_string())?;
    let receiver = daemon
        .browse("_elixir-media._tcp.local.")
        .map_err(|e| e.to_string())?;

    let start = Instant::now();
    let mut found: HashMap<String, MdnsDiscovery> = HashMap::new();

    while start.elapsed() < Duration::from_millis(timeout) {
        match receiver.recv_timeout(Duration::from_millis(200)) {
            Ok(event) => match event {
                ServiceEvent::SearchStarted(_) => {}
                ServiceEvent::ServiceFound(_, _) => {}
                ServiceEvent::ServiceResolved(info) => {
                    let key = info.get_fullname().to_string();
                    found.entry(key.clone()).or_insert_with(|| MdnsDiscovery {
                        name: key,
                        host: info.get_hostname().to_string(),
                        port: info.get_port(),
                        addresses: info
                            .get_addresses()
                            .iter()
                            .map(|a| a.to_string())
                            .collect::<Vec<_>>(),
                    });
                }
                _ => {}
            },
            Err(_) => break,
        }
    }

    Ok(found.into_values().collect())
}

fn find_vlc_binary() -> Result<String, String> {
    if let Ok(path) = which("vlc") {
        return Ok(path.to_string_lossy().to_string());
    }
    if let Ok(path) = which("cvlc") {
        return Ok(path.to_string_lossy().to_string());
    }
    Err("vlc binary not found on PATH".to_string())
}

#[tauri::command]
fn vlc_available() -> bool {
    find_vlc_binary().is_ok()
}

#[tauri::command]
fn vlc_play(state: tauri::State<PlayerState>, url: String) -> Result<(), String> {
    let bin = find_vlc_binary()?;
    let mut guard = state.child.lock().map_err(|e| e.to_string())?;
    if let Some(child) = guard.as_mut() {
        let _ = child.kill();
    }
    let child = Command::new(bin)
        .arg("--play-and-exit")
        .arg("--no-video-title-show")
        .arg(&url)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    *guard = Some(child);
    Ok(())
}

#[tauri::command]
fn vlc_stop(state: tauri::State<PlayerState>) -> Result<(), String> {
    let mut guard = state.child.lock().map_err(|e| e.to_string())?;
    if let Some(mut child) = guard.take() {
        let _ = child.kill();
    }
    Ok(())
}

#[tauri::command]
fn vlc_embed_available(state: tauri::State<ManagedLibVlc>) -> bool {
    state.ensure().map(|g| g.is_some()).unwrap_or(false)
}

#[tauri::command]
fn vlc_embed_play(
    window: tauri::Window,
    url: String,
    state: tauri::State<ManagedLibVlc>,
) -> Result<(), String> {
    let guard = state.ensure()?;
    let player = guard
        .as_ref()
        .ok_or_else(|| "libVLC not available".to_string())?;
    player.play(&window, &url)
}

#[tauri::command]
fn vlc_embed_stop(state: tauri::State<ManagedLibVlc>) -> Result<(), String> {
    let guard = state.ensure()?;
    if let Some(player) = guard.as_ref() {
        player.stop().ok();
    }
    Ok(())
}

#[tauri::command]
fn vlc_embed_ping(window: tauri::Window, state: tauri::State<ManagedLibVlc>) -> Result<bool, String> {
    let guard = state.ensure()?;
    if let Some(player) = guard.as_ref() {
        return player
            .set_drawable(&window)
            .map(|_| true)
            .map_err(|e| e.to_string());
    }
    Ok(false)
}

#[derive(Serialize)]
struct TrackOption {
    id: i32,
    name: String,
}

#[derive(Serialize)]
struct TrackInfo {
    audio: Vec<TrackOption>,
    current_audio: i32,
    subtitles: Vec<TrackOption>,
    current_subtitle: i32,
}

#[tauri::command]
fn vlc_embed_toggle_pause(state: tauri::State<ManagedLibVlc>) -> Result<bool, String> {
    let guard = state.ensure()?;
    let player = guard.as_ref().ok_or_else(|| "libVLC not available".to_string())?;
    let playing = player.is_playing()?;
    player.set_pause(playing)?;
    Ok(!playing)
}

#[tauri::command]
fn vlc_embed_tracks(state: tauri::State<ManagedLibVlc>) -> Result<TrackInfo, String> {
    let guard = state.ensure()?;
    let player = guard.as_ref().ok_or_else(|| "libVLC not available".to_string())?;
    Ok(TrackInfo {
        audio: player.audio_tracks()?,
        current_audio: player.current_audio_track()?,
        subtitles: player.subtitle_tracks()?,
        current_subtitle: player.current_subtitle_track()?,
    })
}

#[tauri::command]
fn vlc_embed_set_audio_track(state: tauri::State<ManagedLibVlc>, track_id: i32) -> Result<(), String> {
    let guard = state.ensure()?;
    let player = guard.as_ref().ok_or_else(|| "libVLC not available".to_string())?;
    player.set_audio_track(track_id)
}

#[tauri::command]
fn vlc_embed_set_subtitle_track(
    state: tauri::State<ManagedLibVlc>,
    track_id: i32,
) -> Result<(), String> {
    let guard = state.ensure()?;
    let player = guard.as_ref().ok_or_else(|| "libVLC not available".to_string())?;
    player.set_subtitle_track(track_id)
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let version = app.package_info().version.to_string();
            println!("Starting Elixir client {}", version);
            Ok(())
        })
        .manage(PlayerState::default())
        .manage(ManagedLibVlc::default())
        .invoke_handler(tauri::generate_handler![
            discover_mdns,
            vlc_available,
            vlc_play,
            vlc_stop,
            vlc_embed_available,
            vlc_embed_play,
            vlc_embed_stop,
            vlc_embed_ping,
            vlc_embed_toggle_pause,
            vlc_embed_tracks,
            vlc_embed_set_audio_track,
            vlc_embed_set_subtitle_track
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
