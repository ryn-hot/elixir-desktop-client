#!/usr/bin/env python3
"""Run the production Qt/mpv client under playback automation observation.

This harness intentionally does not implement a second player. It launches the
real client, enables PlayerController JSONL events, and validates the playback
events produced by the production UI/player path. A higher-level UI driver can
click movie/episode cards while this process observes the resulting playback.
"""

from __future__ import annotations

import argparse
import struct
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zlib
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-bin", required=True, help="Path to elixir-client executable")
    parser.add_argument("--server-url", required=True, help="Fixture server base URL")
    parser.add_argument("--auth-token", required=True, help="Access token for the fixture user")
    parser.add_argument("--access-token-expires-at", default="", help="ISO-8601 access token expiry")
    parser.add_argument("--media-item-id", default="", help="Media item id to autoplay through the production client")
    parser.add_argument("--media-file-id", default="", help="Optional preferred media file id for movie autoplay")
    parser.add_argument("--episode-id", default="", help="Optional episode id for episode autoplay")
    parser.add_argument("--network-type", default="lan", choices=["lan", "wan", "auto"])
    parser.add_argument(
        "--client-capabilities-json",
        default="",
        help="JSON object merged into the production client's playback capabilities for this run",
    )
    parser.add_argument(
        "--client-capabilities-file",
        default="",
        help="Path to a JSON object merged into production client playback capabilities for this run",
    )
    parser.add_argument("--log", default="", help="Automation JSONL path. Defaults to a temp file")
    parser.add_argument(
        "--capture-dir",
        default="",
        help="Directory for production-player frame captures. Defaults beside the automation log.",
    )
    parser.add_argument("--timeout-seconds", type=float, default=90.0)
    parser.add_argument("--expect-mode", action="append", default=[], help="Allowed playback mode")
    parser.add_argument("--expect-delivery", action="append", default=[], help="Allowed delivery")
    parser.add_argument(
        "--expect-server-field",
        action="append",
        default=[],
        help=(
            "Required compact server session field in dotted path=value form, "
            "for example selected_subtitle_track=2 or active_rung.label=720p"
        ),
    )
    parser.add_argument(
        "--automation-actions",
        default="",
        help="Comma/space-separated production player actions to run, e.g. pause,resume,seek_forward,seek_backward,stop",
    )
    parser.add_argument(
        "--exercise-controls",
        action="store_true",
        help="Run the default pause/resume/seek/stop production-control smoke sequence",
    )
    parser.add_argument(
        "--expect-event",
        action="append",
        default=[],
        help="Required JSONL event. Use A|B for alternatives such as seek_applied|seek_completed",
    )
    parser.add_argument(
        "--require-server-seek-restart",
        action="store_true",
        help="Require production HLS/server seek restart evidence: seek_requested with server_seek_required plus seek_completed",
    )
    parser.add_argument(
        "--require-session-restart",
        action="store_true",
        help="Require retry/recovery evidence: a second playback_started event with a different session id and post-restart progress",
    )
    parser.add_argument(
        "--invalidate-session-before-retry",
        action="store_true",
        help="End the first server session after playback starts so a retry action proves recovery from an invalidated session",
    )
    parser.add_argument("--min-position-seconds", type=float, default=2.0)
    parser.add_argument(
        "--min-position-sample-count",
        type=int,
        default=0,
        help="Require at least this many production player position/observation samples",
    )
    parser.add_argument(
        "--min-position-span-seconds",
        type=float,
        default=0.0,
        help="Require observed playback position samples to span this many seconds",
    )
    parser.add_argument(
        "--max-position-regression-seconds",
        type=float,
        default=-1.0,
        help=(
            "When non-negative, fail if consecutive unpaused samples for the same "
            "session regress by more than this tolerance"
        ),
    )
    parser.add_argument("--require-video", dest="require_video", action="store_true", default=True)
    parser.add_argument("--no-require-video", dest="require_video", action="store_false")
    parser.add_argument("--require-audio", dest="require_audio", action="store_true", default=True)
    parser.add_argument("--no-require-audio", dest="require_audio", action="store_false")
    parser.add_argument(
        "--require-nonblank-frame",
        dest="require_nonblank_frame",
        action="store_true",
        default=True,
    )
    parser.add_argument(
        "--skip-nonblank-frame",
        dest="require_nonblank_frame",
        action="store_false",
    )
    parser.add_argument("--require-subtitle-selection", action="store_true")
    parser.add_argument(
        "--require-bright-region",
        action="append",
        default=[],
        help=(
            "Require a bright normalized capture region in "
            "label:x:y:w:h:min_mean[:min_max] form. This is used for "
            "production-player visual subtitle evidence without OCR."
        ),
    )
    parser.add_argument(
        "--require-server-session-state",
        dest="require_server_session_state",
        action="store_true",
        default=True,
        help="Poll the real server session and require matching mode/delivery evidence",
    )
    parser.add_argument(
        "--no-require-server-session-state",
        dest="require_server_session_state",
        action="store_false",
    )
    parser.add_argument(
        "--no-kill",
        action="store_true",
        help="Leave the client running after validation for manual inspection",
    )
    return parser.parse_args()


def default_control_actions() -> str:
    return "pause,resume,seek_forward,seek_backward,stop"


def automation_action_name(raw: str) -> str:
    action = raw.strip().lower()
    separator = action.find(":")
    equals = action.find("=")
    if separator < 0 or (0 <= equals < separator):
        separator = equals
    if separator > 0:
        action = action[:separator]
    return action


def expected_events_for_actions(actions: str) -> list[str]:
    expected: list[str] = []
    for raw in actions.replace(";", ",").replace(" ", ",").split(","):
        action = automation_action_name(raw)
        if action == "pause":
            expected.append("paused")
        elif action == "resume":
            expected.append("resumed")
        elif action in {"seek_forward", "seek_backward"}:
            expected.append("seek_applied|seek_completed")
        elif action == "audio_next":
            expected.append("audio_track_switch_requested")
        elif action == "subtitle_next":
            expected.append("subtitle_track_switch_requested")
        elif action == "lower_quality":
            expected.append("lower_quality_requested|lower_quality_unavailable")
        elif action in {"retry_same", "retry_from_current"}:
            expected.append("retry_recovery_requested")
        elif action == "wait":
            expected.append("automation_wait")
        elif action in {"skip_active_segment", "skip_segment"}:
            expected.append("automation_skip_active_segment")
            expected.append("segment_skip_requested")
            expected.append("seek_applied|seek_completed")
        elif action in {"up_next_play_now", "play_next"}:
            expected.append("automation_up_next_play_now")
            expected.append("up_next_play_now")
        elif action in {"up_next_cancel", "cancel_up_next"}:
            expected.append("automation_up_next_cancel")
            expected.append("up_next_cancelled")
        elif action == "stop":
            expected.append("session_end_requested")
    if actions.strip():
        expected.append("automation_finished")
    return expected


def matches_event_spec(spec: str, event_name: str) -> bool:
    return event_name in {part.strip() for part in spec.split("|") if part.strip()}


def mark_expected_events(
    pending: list[str],
    event_name: str,
) -> list[str]:
    remaining = list(pending)
    for index, spec in enumerate(pending):
        if matches_event_spec(spec, event_name):
            del remaining[index]
            return remaining
    return remaining


def load_events(path: Path, offset: int) -> tuple[list[dict[str, Any]], int]:
    if not path.exists():
        return [], offset
    data = path.read_bytes()
    if offset > len(data):
        offset = 0
    chunk = data[offset:]
    events: list[dict[str, Any]] = []
    for raw in chunk.splitlines():
        if not raw.strip():
            continue
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    return events, len(data)


def _paeth_predictor(left: int, above: int, upper_left: int) -> int:
    p = left + above - upper_left
    pa = abs(p - left)
    pb = abs(p - above)
    pc = abs(p - upper_left)
    if pa <= pb and pa <= pc:
        return left
    if pb <= pc:
        return above
    return upper_left


def decode_png_rows(path: Path) -> tuple[int, int, int, list[bytearray]]:
    data = path.read_bytes()
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        raise ValueError("not a PNG file")

    pos = len(signature)
    width = height = bit_depth = color_type = interlace = None
    compressed = bytearray()
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        chunk_type = data[pos + 4 : pos + 8]
        chunk_data = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _compression, _filter, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if width is None or height is None or bit_depth is None or color_type is None:
        raise ValueError("PNG missing IHDR")
    if bit_depth != 8 or color_type not in (0, 2, 6) or interlace != 0:
        raise ValueError(
            f"unsupported PNG format bit_depth={bit_depth} color_type={color_type} interlace={interlace}"
        )

    channels = {0: 1, 2: 3, 6: 4}[color_type]
    row_len = width * channels
    raw = zlib.decompress(bytes(compressed))
    expected_len = (row_len + 1) * height
    if len(raw) < expected_len:
        raise ValueError("PNG pixel data is truncated")

    rows: list[bytearray] = []
    offset = 0
    previous = bytearray(row_len)
    for _y in range(height):
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset : offset + row_len])
        offset += row_len
        for i in range(row_len):
            left = row[i - channels] if i >= channels else 0
            above = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 0:
                value = row[i]
            elif filter_type == 1:
                value = (row[i] + left) & 0xFF
            elif filter_type == 2:
                value = (row[i] + above) & 0xFF
            elif filter_type == 3:
                value = (row[i] + ((left + above) // 2)) & 0xFF
            elif filter_type == 4:
                value = (row[i] + _paeth_predictor(left, above, upper_left)) & 0xFF
            else:
                raise ValueError(f"unsupported PNG filter {filter_type}")
            row[i] = value
        rows.append(row)
        previous = row

    return width, height, channels, rows


def pixel_luma(row: bytearray, x: int, channels: int) -> int:
    offset = x * channels
    if channels == 1:
        return row[offset]
    r, g, b = row[offset], row[offset + 1], row[offset + 2]
    return int((0.2126 * r) + (0.7152 * g) + (0.0722 * b))


def png_luma_values(path: Path) -> list[int]:
    width, height, channels, rows = decode_png_rows(path)
    lumas: list[int] = []
    sample_stride = max(1, (width * height) // 20000)
    pixel_index = 0
    for row in rows:
        for x in range(width):
            if pixel_index % sample_stride == 0:
                lumas.append(pixel_luma(row, x, channels))
            pixel_index += 1
    return lumas


def parse_bright_region_spec(spec: str) -> dict[str, Any]:
    parts = [part.strip() for part in spec.split(":")]
    if len(parts) not in {6, 7, 8, 9}:
        raise ValueError(
            "bright region must be label:x:y:w:h:min_mean[:min_max[:max_mean[:max_max]]]"
        )
    label = parts[0]
    if not label:
        raise ValueError("bright region label is required")
    try:
        x, y, width, height = [float(value) for value in parts[1:5]]
        min_mean = float(parts[5])
        min_max = float(parts[6]) if len(parts) == 7 else None
        if len(parts) >= 8:
            min_max = float(parts[6])
            max_mean = float(parts[7])
        else:
            max_mean = None
        max_max = float(parts[8]) if len(parts) == 9 else None
    except ValueError as exc:
        raise ValueError(f"bright region has non-numeric bounds: {spec}") from exc
    if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > 1 or y + height > 1:
        raise ValueError(f"bright region bounds must be normalized into the capture: {spec}")
    if (
        min_mean < 0
        or (min_max is not None and min_max < 0)
        or (max_mean is not None and max_mean < 0)
        or (max_max is not None and max_max < 0)
    ):
        raise ValueError(f"bright region thresholds must be non-negative: {spec}")
    if max_mean is not None and max_mean < min_mean:
        raise ValueError(f"bright region max_mean must be >= min_mean: {spec}")
    if max_max is not None and min_max is not None and max_max < min_max:
        raise ValueError(f"bright region max_max must be >= min_max: {spec}")
    return {
        "label": label,
        "x": x,
        "y": y,
        "width": width,
        "height": height,
        "min_mean": min_mean,
        "min_max": min_max,
        "max_mean": max_mean,
        "max_max": max_max,
        "spec": spec,
    }


def bright_region_png(path: Path, region: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    try:
        width, height, channels, rows = decode_png_rows(path)
    except Exception as exc:  # noqa: BLE001 - returned as harness evidence
        return False, {"path": str(path), "label": region["label"], "error": str(exc)}

    left = max(0, min(width - 1, int(region["x"] * width)))
    top = max(0, min(height - 1, int(region["y"] * height)))
    right = max(left + 1, min(width, int((region["x"] + region["width"]) * width + 0.999)))
    bottom = max(top + 1, min(height, int((region["y"] + region["height"]) * height + 0.999)))
    lumas: list[int] = []
    for row in rows[top:bottom]:
        for x in range(left, right):
            lumas.append(pixel_luma(row, x, channels))
    if not lumas:
        return False, {"path": str(path), "label": region["label"], "error": "empty region"}

    minimum = min(lumas)
    maximum = max(lumas)
    mean = sum(lumas) / len(lumas)
    min_max = region.get("min_max")
    max_mean = region.get("max_mean")
    max_max = region.get("max_max")
    result = (
        mean >= region["min_mean"]
        and (min_max is None or maximum >= min_max)
        and (max_mean is None or mean <= max_mean)
        and (max_max is None or maximum <= max_max)
    )
    return result, {
        "path": str(path),
        "label": region["label"],
        "bounds": {
            "left": left,
            "top": top,
            "right": right,
            "bottom": bottom,
            "normalized": {
                "x": region["x"],
                "y": region["y"],
                "width": region["width"],
                "height": region["height"],
            },
        },
        "min_luma": minimum,
        "max_luma": maximum,
        "mean_luma": round(mean, 3),
        "sample_count": len(lumas),
        "required_min_mean": region["min_mean"],
        "required_min_max": min_max,
        "required_max_mean": max_mean,
        "required_max_max": max_max,
    }


def nonblank_png(path: Path) -> tuple[bool, dict[str, Any]]:
    try:
        lumas = png_luma_values(path)
    except Exception as exc:  # noqa: BLE001 - surface parser/capture failures in harness JSON
        return False, {"path": str(path), "error": str(exc)}
    if not lumas:
        return False, {"path": str(path), "error": "no pixels"}
    minimum = min(lumas)
    maximum = max(lumas)
    mean = sum(lumas) / len(lumas)
    result = maximum >= 12 and (maximum - minimum) >= 4
    return result, {
        "path": str(path),
        "min_luma": minimum,
        "max_luma": maximum,
        "mean_luma": round(mean, 3),
        "sample_count": len(lumas),
    }


def refresh_capture_checks(
    capture_paths: set[Path],
    capture_dir: Path,
    checked_captures: dict[Path, tuple[bool, dict[str, Any]]],
) -> dict[str, Any] | None:
    for png_path in capture_dir.glob("*.png"):
        capture_paths.add(png_path)

    first_nonblank: dict[str, Any] | None = None
    for capture_path in list(capture_paths):
        previous = checked_captures.get(capture_path)
        if previous is not None and previous[0]:
            if first_nonblank is None:
                first_nonblank = previous[1]
            continue
        if not capture_path.exists():
            continue
        checked_captures[capture_path] = nonblank_png(capture_path)
        ok, details = checked_captures[capture_path]
        if ok and first_nonblank is None:
            first_nonblank = details
    return first_nonblank


def refresh_bright_region_checks(
    capture_paths: set[Path],
    capture_dir: Path,
    regions: list[dict[str, Any]],
    matched_regions: dict[str, dict[str, Any]],
    region_attempts: dict[str, list[dict[str, Any]]],
) -> None:
    if not regions:
        return
    for png_path in capture_dir.glob("*.png"):
        capture_paths.add(png_path)
    for region in regions:
        label = str(region["label"])
        if label in matched_regions:
            continue
        attempts = region_attempts.setdefault(label, [])
        for capture_path in sorted(capture_paths):
            if not capture_path.exists():
                continue
            ok, details = bright_region_png(capture_path, region)
            attempts.append(details)
            if ok:
                matched_regions[label] = details
                break


def server_session_url(server_url: str, session_id: str) -> str:
    return f"{server_url.rstrip('/')}/api/v1/sessions/{session_id}/poll"


def server_session_end_url(server_url: str, session_id: str) -> str:
    return f"{server_url.rstrip('/')}/api/v1/sessions/{session_id}/end"


def fetch_server_session(server_url: str, auth_token: str, session_id: str) -> tuple[bool, dict[str, Any]]:
    request = urllib.request.Request(server_session_url(server_url, session_id))
    request.add_header("Authorization", f"Bearer {auth_token}")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return False, {"status": exc.code, "error": exc.reason}
    except Exception as exc:  # noqa: BLE001 - returned as harness evidence
        return False, {"error": str(exc)}
    if not isinstance(data, dict):
        return False, {"error": "session poll response was not an object"}
    return True, data


def end_server_session(server_url: str, auth_token: str, session_id: str) -> tuple[bool, dict[str, Any]]:
    request = urllib.request.Request(server_session_end_url(server_url, session_id), method="POST")
    request.add_header("Authorization", f"Bearer {auth_token}")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            raw = response.read().decode("utf-8", errors="replace")
            data = json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        return False, {"status": exc.code, "error": exc.reason}
    except Exception as exc:  # noqa: BLE001 - returned as cleanup evidence when called directly
        return False, {"error": str(exc)}
    return True, data if isinstance(data, dict) else {"response": data}


def server_session_expectation_errors(
    session: dict[str, Any],
    expect_modes: list[str],
    expect_deliveries: list[str],
    expect_fields: list[str] | None = None,
) -> list[str]:
    errors: list[str] = []
    mode = str(session.get("mode", ""))
    delivery = str(session.get("delivery", ""))
    if expect_modes and mode not in expect_modes:
        errors.append(f"server_mode:{mode}")
    if expect_deliveries and delivery not in expect_deliveries:
        errors.append(f"server_delivery:{delivery}")
    compact = compact_server_session(session)
    for spec in expect_fields or []:
        field_error = server_field_expectation_error(compact, spec)
        if field_error:
            errors.append(field_error)
    return errors


def compact_server_session(session: dict[str, Any]) -> dict[str, Any]:
    plan_summary = session.get("plan_summary")
    if not isinstance(plan_summary, dict):
        plan_summary = {}
    job_snapshot = session.get("job_snapshot")
    if not isinstance(job_snapshot, dict):
        job_snapshot = {}
    active_rung = session.get("active_rung")
    if not isinstance(active_rung, dict):
        active_rung = {}
    return {
        "id": session.get("id"),
        "state": session.get("state"),
        "mode": session.get("mode"),
        "delivery": session.get("delivery"),
        "server_seek_required": session.get("server_seek_required"),
        "decision_reason": session.get("decision_reason"),
        "decision_reasons": session.get("decision_reasons"),
        "logical_position_seconds": session.get("logical_position_seconds"),
        "duration_seconds": session.get("duration_seconds"),
        "selected_audio_track": plan_summary.get("selected_audio_track"),
        "selected_subtitle_track": plan_summary.get("selected_subtitle_track"),
        "video_action": plan_summary.get("video_action"),
        "audio_action": plan_summary.get("audio_action"),
        "subtitle_action": plan_summary.get("subtitle_action"),
        "hdr_action": plan_summary.get("hdr_action"),
        "video_transcode_reason": plan_summary.get("video_transcode_reason"),
        "tone_map": plan_summary.get("tone_map"),
        "adaptive": plan_summary.get("adaptive"),
        "quality_label": plan_summary.get("quality_label"),
        "active_rung": active_rung,
        "job_state": job_snapshot.get("state"),
        "job_error_kind": job_snapshot.get("error_kind"),
    }


def value_at_path(value: Any, path: str) -> Any:
    current = value
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def parse_expected_value(raw: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def comparable_value(value: Any) -> Any:
    if isinstance(value, (bool, int, float)) or value is None:
        return value
    if isinstance(value, str):
        stripped = value.strip()
        parsed = parse_expected_value(stripped)
        if parsed != stripped:
            return comparable_value(parsed)
        return stripped
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def server_field_expectation_error(compact_session: dict[str, Any], spec: str) -> str | None:
    if "=" not in spec:
        return f"server_field_invalid:{spec}"
    path, expected_raw = spec.split("=", 1)
    path = path.strip()
    if not path:
        return f"server_field_invalid:{spec}"
    expected = comparable_value(parse_expected_value(expected_raw.strip()))
    actual = comparable_value(value_at_path(compact_session, path))
    if actual != expected:
        return f"server_field:{path}:{actual!r}!={expected!r}"
    return None


def position_sample_from_event(event: dict[str, Any]) -> dict[str, Any] | None:
    name = str(event.get("event") or "")
    if name not in {"position", "player_observation"}:
        return None
    try:
        position = float(event.get("position_seconds"))
    except (TypeError, ValueError):
        return None
    if not position >= 0.0:
        return None
    return {
        "event": name,
        "session_id": str(event.get("session_id") or ""),
        "position_seconds": position,
        "paused": bool(event.get("paused")),
        "timestamp": event.get("timestamp"),
    }


def advanced_playback_event(
    event: dict[str, Any],
    *,
    min_position_seconds: float,
) -> dict[str, Any] | None:
    sample = position_sample_from_event(event)
    if sample is None:
        return None
    if float(sample["position_seconds"]) < min_position_seconds:
        return None
    return event


def summarize_timing_evidence(
    samples: list[dict[str, Any]],
    *,
    min_sample_count: int,
    min_span_seconds: float,
    max_regression_seconds: float,
) -> dict[str, Any]:
    unpaused = [sample for sample in samples if sample.get("paused") is not True]
    positions = [float(sample["position_seconds"]) for sample in unpaused]
    first_position = positions[0] if positions else None
    last_position = positions[-1] if positions else None
    span = (max(positions) - min(positions)) if positions else 0.0
    regressions: list[dict[str, Any]] = []
    previous_by_session: dict[str, dict[str, Any]] = {}
    if max_regression_seconds >= 0:
        for sample in unpaused:
            session_id = str(sample.get("session_id") or "")
            previous = previous_by_session.get(session_id)
            if previous is not None:
                previous_position = float(previous["position_seconds"])
                position = float(sample["position_seconds"])
                regression = previous_position - position
                if regression > max_regression_seconds:
                    regressions.append(
                        {
                            "session_id": session_id,
                            "previous_position_seconds": round(previous_position, 3),
                            "position_seconds": round(position, 3),
                            "regression_seconds": round(regression, 3),
                            "previous_event": previous.get("event"),
                            "event": sample.get("event"),
                        }
                    )
            previous_by_session[session_id] = sample

    failures: list[str] = []
    if min_sample_count > 0 and len(unpaused) < min_sample_count:
        failures.append(f"sample_count:{len(unpaused)}<{min_sample_count}")
    if min_span_seconds > 0 and span < min_span_seconds:
        failures.append(f"position_span_seconds:{span:.3f}<{min_span_seconds:.3f}")
    if regressions:
        failures.append(f"position_regressions:{len(regressions)}")

    return {
        "status": "passed" if not failures else "failed",
        "failures": failures,
        "sample_count": len(unpaused),
        "raw_sample_count": len(samples),
        "position_span_seconds": round(span, 3),
        "first_position_seconds": round(first_position, 3) if first_position is not None else None,
        "last_position_seconds": round(last_position, 3) if last_position is not None else None,
        "min_required_sample_count": max(0, min_sample_count),
        "min_required_position_span_seconds": max(0.0, min_span_seconds),
        "max_allowed_regression_seconds": max_regression_seconds
        if max_regression_seconds >= 0
        else None,
        "regressions": regressions,
        "samples": [
            {
                "event": sample.get("event"),
                "session_id": sample.get("session_id"),
                "position_seconds": round(float(sample["position_seconds"]), 3),
                "paused": sample.get("paused"),
                "timestamp": sample.get("timestamp"),
            }
            for sample in unpaused
        ],
    }


def terminate(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=8)


def main() -> int:
    args = parse_args()
    client_bin = Path(args.client_bin)
    if not client_bin.exists():
        print(f"client executable not found: {client_bin}", file=sys.stderr)
        return 2

    log_path = Path(args.log) if args.log else Path(tempfile.mkdtemp()) / "playback-client.jsonl"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    if log_path.exists():
        log_path.unlink()
    capture_dir = Path(args.capture_dir) if args.capture_dir else log_path.parent / "captures"
    capture_dir.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env["ELIXIR_CLIENT_BASE_URL"] = args.server_url
    env["ELIXIR_CLIENT_AUTH_TOKEN"] = args.auth_token
    env["ELIXIR_CLIENT_NETWORK_TYPE"] = args.network_type
    env["ELIXIR_PLAYBACK_AUTOMATION_LOG"] = str(log_path)
    env["ELIXIR_PLAYBACK_AUTOMATION_CAPTURE_DIR"] = str(capture_dir)
    capabilities_json = args.client_capabilities_json.strip()
    if args.client_capabilities_file:
        capabilities_json = Path(args.client_capabilities_file).read_text().strip()
    if capabilities_json:
        try:
            parsed_capabilities = json.loads(capabilities_json)
        except json.JSONDecodeError as exc:
            print(f"invalid client capabilities JSON: {exc}", file=sys.stderr)
            return 2
        if not isinstance(parsed_capabilities, dict):
            print("client capabilities JSON must be an object", file=sys.stderr)
            return 2
        env["ELIXIR_CLIENT_CAPABILITIES_JSON"] = json.dumps(
            parsed_capabilities,
            separators=(",", ":"),
            sort_keys=True,
        )
    automation_actions = args.automation_actions.strip()
    if args.exercise_controls and not automation_actions:
        automation_actions = default_control_actions()
    if automation_actions:
        env["ELIXIR_CLIENT_AUTOMATION_ACTIONS"] = automation_actions
    if args.access_token_expires_at:
        env["ELIXIR_CLIENT_ACCESS_TOKEN_EXPIRES_AT"] = args.access_token_expires_at
    if args.media_item_id:
        env["ELIXIR_CLIENT_AUTOPLAY_MEDIA_ITEM_ID"] = args.media_item_id
    if args.media_file_id:
        env["ELIXIR_CLIENT_AUTOPLAY_MEDIA_FILE_ID"] = args.media_file_id
    if args.episode_id:
        env["ELIXIR_CLIENT_AUTOPLAY_EPISODE_ID"] = args.episode_id
    try:
        required_bright_regions = [
            parse_bright_region_spec(spec) for spec in args.require_bright_region
        ]
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    process = subprocess.Popen([str(client_bin)], env=env)
    deadline = time.monotonic() + args.timeout_seconds
    offset = 0
    all_events: list[dict[str, Any]] = []
    pending_events = list(args.expect_event)
    if automation_actions and not pending_events:
        pending_events = expected_events_for_actions(automation_actions)
    started: dict[str, Any] | None = None
    advanced: dict[str, Any] | None = None
    playback_started_events: list[dict[str, Any]] = []
    seen_session_ids: list[str] = []
    restarted_session_id: str | None = None
    post_restart_advanced: dict[str, Any] | None = None
    server_seek_requested: dict[str, Any] | None = None
    server_seek_completed: dict[str, Any] | None = None
    invalidated_session: dict[str, Any] | None = None
    failure: dict[str, Any] | None = None
    video_observed = False
    audio_observed = False
    subtitle_observed = False
    capture_paths: set[Path] = set()
    checked_captures: dict[Path, tuple[bool, dict[str, Any]]] = {}
    nonblank_capture: dict[str, Any] | None = None
    bright_region_matches: dict[str, dict[str, Any]] = {}
    bright_region_attempts: dict[str, list[dict[str, Any]]] = {}
    position_samples: list[dict[str, Any]] = []
    timing_evidence = summarize_timing_evidence(
        position_samples,
        min_sample_count=args.min_position_sample_count,
        min_span_seconds=args.min_position_span_seconds,
        max_regression_seconds=args.max_position_regression_seconds,
    )
    server_session: dict[str, Any] | None = None
    server_session_error: dict[str, Any] | None = None
    missing_evidence: list[str] = []

    try:
        while time.monotonic() < deadline:
            events, offset = load_events(log_path, offset)
            all_events.extend(events)
            for event in events:
                position_sample = position_sample_from_event(event)
                if position_sample is not None:
                    position_samples.append(position_sample)
                name = event.get("event")
                if isinstance(name, str):
                    pending_events = mark_expected_events(pending_events, name)
                if name == "playback_failed":
                    failure = event
                elif name == "playback_started":
                    previous_session_id = str(started.get("session_id") or "").strip() if started else ""
                    next_session_id = str(event.get("session_id") or "").strip()
                    if previous_session_id and next_session_id and previous_session_id != next_session_id:
                        server_session = None
                        server_session_error = None
                        advanced = None
                        restarted_session_id = next_session_id
                    mode = str(event.get("mode", ""))
                    delivery = str(event.get("delivery", ""))
                    selected_subtitle = str(event.get("selected_subtitle_track") or "").strip().lower()
                    if selected_subtitle and selected_subtitle not in {"none", "off", "no subtitles"}:
                        subtitle_observed = True
                    if args.expect_mode and mode not in args.expect_mode:
                        failure = {"event": "harness_failed", "message": f"unexpected mode {mode}"}
                    elif args.expect_delivery and delivery not in args.expect_delivery:
                        failure = {
                            "event": "harness_failed",
                            "message": f"unexpected delivery {delivery}",
                        }
                    else:
                        started = event
                        playback_started_events.append(event)
                        if next_session_id and next_session_id not in seen_session_ids:
                            seen_session_ids.append(next_session_id)
                elif name == "position":
                    advanced_candidate = advanced_playback_event(
                        event,
                        min_position_seconds=args.min_position_seconds,
                    )
                    if advanced_candidate is not None:
                        advanced = advanced_candidate
                        event_session_id = str(event.get("session_id") or "").strip()
                        if restarted_session_id and event_session_id == restarted_session_id:
                            post_restart_advanced = advanced_candidate
                elif name == "seek_requested" and bool(event.get("server_seek_required")):
                    server_seek_requested = event
                elif name == "seek_completed":
                    server_seek_completed = event
                elif name == "player_observation":
                    video_observed = video_observed or bool(event.get("video_ready"))
                    audio_observed = audio_observed or bool(event.get("audio_ready"))
                    selected_subtitle = str(event.get("selected_subtitle_id") or "").strip().lower()
                    subtitle_observed = subtitle_observed or (
                        bool(event.get("subtitle_visible"))
                        and selected_subtitle not in {"", "no", "none", "0", "false"}
                    )
                    advanced_candidate = advanced_playback_event(
                        event,
                        min_position_seconds=args.min_position_seconds,
                    )
                    if advanced_candidate is not None:
                        advanced = advanced_candidate
                        event_session_id = str(event.get("session_id") or "").strip()
                        if restarted_session_id and event_session_id == restarted_session_id:
                            post_restart_advanced = advanced_candidate
                elif name == "subtitle_track_switch_requested":
                    subtitle_observed = True
                elif name == "video_frame_capture_requested":
                    raw_path = str(event.get("capture_path") or "").strip()
                    if raw_path:
                        capture_paths.add(Path(raw_path))

            refreshed_capture = refresh_capture_checks(capture_paths, capture_dir, checked_captures)
            if refreshed_capture is not None and nonblank_capture is None:
                nonblank_capture = refreshed_capture
            refresh_bright_region_checks(
                capture_paths,
                capture_dir,
                required_bright_regions,
                bright_region_matches,
                bright_region_attempts,
            )
            timing_evidence = summarize_timing_evidence(
                position_samples,
                min_sample_count=args.min_position_sample_count,
                min_span_seconds=args.min_position_span_seconds,
                max_regression_seconds=args.max_position_regression_seconds,
            )

            if args.require_server_session_state and started is not None and server_session is None:
                session_id = str(started.get("session_id") or "").strip()
                if session_id:
                    ok, details = fetch_server_session(args.server_url, args.auth_token, session_id)
                    if ok:
                        expectation_errors = server_session_expectation_errors(
                            details,
                            args.expect_mode,
                            args.expect_delivery,
                            args.expect_server_field,
                        )
                        if expectation_errors:
                            server_session_error = {
                                "error": "server_session_expectation_mismatch",
                                "details": expectation_errors,
                                "session": compact_server_session(details),
                            }
                            failure = server_session_error
                        else:
                            server_session = details
                    else:
                        server_session_error = details

            if (
                args.invalidate_session_before_retry
                and started is not None
                and advanced is not None
                and invalidated_session is None
            ):
                session_id = str(started.get("session_id") or "").strip()
                if session_id:
                    ok, details = end_server_session(args.server_url, args.auth_token, session_id)
                    invalidated_session = {
                        "session_id": session_id,
                        "ok": ok,
                        "details": details,
                    }
                    if not ok:
                        failure = {
                            "event": "harness_failed",
                            "message": "failed to invalidate session before retry",
                            "details": invalidated_session,
                        }

            missing_evidence = []
            if args.require_video and not video_observed:
                missing_evidence.append("video_observation")
            if args.require_audio and not audio_observed:
                missing_evidence.append("audio_observation")
            if args.require_nonblank_frame and nonblank_capture is None:
                missing_evidence.append("nonblank_frame_capture")
            if args.require_subtitle_selection and not subtitle_observed:
                missing_evidence.append("subtitle_selection")
            for region in required_bright_regions:
                label = str(region["label"])
                if label not in bright_region_matches:
                    missing_evidence.append(f"bright_region:{label}")
            if args.require_server_session_state and server_session is None:
                missing_evidence.append("server_session_state")
            if args.require_server_seek_restart:
                if server_seek_requested is None:
                    missing_evidence.append("server_seek_requested")
                if server_seek_completed is None:
                    missing_evidence.append("server_seek_completed")
            if args.require_session_restart:
                if len(seen_session_ids) < 2:
                    missing_evidence.append("session_restart")
                if post_restart_advanced is None:
                    missing_evidence.append("post_restart_position")
            if args.invalidate_session_before_retry and invalidated_session is None:
                missing_evidence.append("session_invalidation")
            if timing_evidence["status"] != "passed":
                missing_evidence.extend(
                    f"timing:{failure}" for failure in timing_evidence["failures"]
                )

            if failure is not None:
                print(
                    json.dumps(
                        {
                            "status": "failed",
                            "failure": failure,
                            "log": str(log_path),
                            "pending_events": pending_events,
                            "missing_evidence": missing_evidence,
                            "server_session_error": server_session_error,
                            "server_session": compact_server_session(server_session)
                            if server_session is not None
                            else None,
                            "seen_session_ids": seen_session_ids,
                            "invalidated_session": invalidated_session,
                            "server_seek_requested": server_seek_requested,
                            "server_seek_completed": server_seek_completed,
                            "post_restart_advanced": post_restart_advanced,
                            "capture_results": [details for _ok, details in checked_captures.values()],
                            "bright_region_matches": bright_region_matches,
                            "bright_region_attempts": bright_region_attempts,
                            "timing_evidence": timing_evidence,
                        }
                    )
                )
                return 1
            if (
                started is not None
                and advanced is not None
                and not pending_events
                and not missing_evidence
            ):
                print(
                    json.dumps(
                        {
                            "status": "passed",
                            "log": str(log_path),
                            "capture_dir": str(capture_dir),
                            "started": started,
                            "advanced": advanced,
                            "event_count": len(all_events),
                            "automation_actions": automation_actions,
                            "playback_started_count": len(playback_started_events),
                            "seen_session_ids": seen_session_ids,
                            "invalidated_session": invalidated_session,
                            "video_observed": video_observed,
                            "audio_observed": audio_observed,
                            "subtitle_observed": subtitle_observed,
                            "server_seek_requested": server_seek_requested,
                            "server_seek_completed": server_seek_completed,
                            "post_restart_advanced": post_restart_advanced,
                            "nonblank_capture": nonblank_capture,
                            "bright_regions": bright_region_matches,
                            "timing_evidence": timing_evidence,
                            "server_session": compact_server_session(server_session)
                            if server_session is not None
                            else None,
                        },
                        sort_keys=True,
                    )
                )
                return 0
            if process.poll() is not None:
                print(
                    json.dumps(
                        {
                            "status": "failed",
                            "message": f"client exited with {process.returncode}",
                            "log": str(log_path),
                            "events": all_events,
                        }
                    )
                )
                return 1
            time.sleep(0.25)

        print(
            json.dumps(
                {
                    "status": "failed",
                    "message": "timed out waiting for playback_started, position, and expected automation events",
                    "log": str(log_path),
                    "capture_dir": str(capture_dir),
                    "events": all_events,
                    "pending_events": pending_events,
                    "missing_evidence": missing_evidence,
                    "server_session_error": server_session_error,
                    "seen_session_ids": seen_session_ids,
                    "invalidated_session": invalidated_session,
                    "server_seek_requested": server_seek_requested,
                    "server_seek_completed": server_seek_completed,
                    "post_restart_advanced": post_restart_advanced,
                    "capture_results": [details for _ok, details in checked_captures.values()],
                    "bright_region_matches": bright_region_matches,
                    "bright_region_attempts": bright_region_attempts,
                    "timing_evidence": timing_evidence,
                }
            )
        )
        return 1
    finally:
        session_id = str(started.get("session_id") or "").strip() if started else ""
        if session_id:
            end_server_session(args.server_url, args.auth_token, session_id)
        if not args.no_kill:
            terminate(process)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    raise SystemExit(main())
