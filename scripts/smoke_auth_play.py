#!/usr/bin/env python3
"""
Minimal auth→library→play→seek→end smoke test against a running Elixir server.
Usage:
  ELIXIR_BASE=http://127.0.0.1:44301 ELIXIR_EMAIL=you@example.com ELIXIR_PASSWORD=secret python3 scripts/smoke_auth_play.py
"""

import os
import sys
import time
from typing import Any, Dict, Optional

import requests


BASE = os.environ.get("ELIXIR_BASE", "http://127.0.0.1:44301")
EMAIL = os.environ.get("ELIXIR_EMAIL")
PASSWORD = os.environ.get("ELIXIR_PASSWORD")


def fail(msg: str):
    print(f"ERROR: {msg}")
    sys.exit(1)


def fetch_json(path: str, method="GET", token: Optional[str] = None, body: Optional[Dict[str, Any]] = None):
    url = f"{BASE.rstrip('/')}{path}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    resp = requests.request(method, url, json=body, headers=headers, timeout=10)
    if not resp.ok:
        fail(f"{method} {url} -> {resp.status_code} {resp.text}")
    return resp.json()


def main():
    if not EMAIL or not PASSWORD:
        fail("Set ELIXIR_EMAIL and ELIXIR_PASSWORD env vars.")

    print(f"Base: {BASE}")
    health = fetch_json("/health")
    print(f"Health ok: {health.get('status')}")

    # Login
    login = fetch_json(
        "/api/v1/auth/login",
        method="POST",
        body={"email": EMAIL, "password": PASSWORD},
    )
    token = login["access_token"]
    print("Login ok, token acquired")

    # Library list
    items = fetch_json("/api/v1/library/items", token=token)
    if not items:
        fail("No library items found; run a scan first.")
    item = items[0]
    print(f"Using item: {item['title']} ({item['id']})")

    detail = fetch_json(f"/api/v1/library/items/{item['id']}", token=token)
    files = [f for f in detail["files"] if f.get("scanState", f.get("scan_state")) != "missing"]
    if not files:
        fail("No playable files (all missing).")
    file_id = files[0]["id"]

    # Start play
    play = fetch_json(
        "/api/v1/play",
        method="POST",
        token=token,
        body={
            "media_item_id": item["id"],
            "preferred_file_id": file_id,
            "network_type": "lan",
            "client_capabilities": None,
        },
    )
    session_id = play["session_id"]
    mode = play["mode"]
    print(f"Play ok: session {session_id}, mode={mode}, stream={play['stream_url']}")

    # Poll session
    poll = fetch_json(f"/api/v1/sessions/{session_id}/poll", token=token)
    print(f"Poll: state={poll['state']} position={poll['logical_position_seconds']}")

    # Seek to 30s
    seek_resp = fetch_json(
        f"/api/v1/sessions/{session_id}/seek",
        method="POST",
        token=token,
        body={"position_seconds": 30.0},
    )
    print(f"Seek response: {seek_resp}")
    time.sleep(1)
    poll2 = fetch_json(f"/api/v1/sessions/{session_id}/poll", token=token)
    print(f"After seek: state={poll2['state']} position={poll2['logical_position_seconds']}")

    # End session
    end = fetch_json(
        f"/api/v1/sessions/{session_id}/end",
        method="POST",
        token=token,
    )
    print(f"End session: {end}")
    print("Smoke test completed.")


if __name__ == "__main__":
    main()
