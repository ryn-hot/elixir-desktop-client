# Tauri E2E checklist (manual smoke)

Purpose: a quick auth → play sanity check against a running Elixir server.

Server prep:
- Start the Elixir server with media scanned.
- Ensure a test user exists (signup via UI is fine).
- Have one playable item available.

Client prep:
- Install VLC/libVLC as noted in README-tauri-dev.md and set env accordingly.
- From `elixir-client`: `npm run tauri:dev:vlc` (mac) or platform-specific dev script.

Flow:
1) Launch the client; select a server (LAN/WAN/manual) and log in.
2) Verify library list loads; select an item; confirm details/files shown.
3) Start playback (auto-select or choose a file); confirm a session is created and playback starts.
4) Seek using the slider; confirm playback resumes and session state/position update.
5) End session; confirm server reports session ended.
6) Toggle embed/native VLC to ensure both paths work (only if libVLC available).

Expected: no errors in UI; status shows active session; seek updates; no crashes.

CLI automation (minimal):
- `ELIXIR_BASE=http://127.0.0.1:44301 ELIXIR_EMAIL=you@example.com ELIXIR_PASSWORD=secret python3 scripts/smoke_auth_play.py`
- Exercises: health, login, list, detail, play, poll, seek, end.

Future automation: stub a mock server or recorded responses for offline smoke. For now, keep this checklist handy for release validation.***
