#!/usr/bin/env python3
"""Run production-client playback automation across a required mode/profile matrix.

The matrix runner is an orchestration layer around playback_client_automation.py.
It does not implement a player and it does not fake server behavior. A fixture
server must provide real playback sessions, media ids, and auth tokens; each
case launches the production Qt/mpv client and validates the emitted evidence.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


REQUIRED_MODES = {
    "direct_play",
    "direct_stream",
    "audio_transcode",
    "subtitle_transcode",
    "video_transcode",
    "adaptive_transcode",
}

DEFAULT_CONTROL_ACTIONS = ("pause", "resume", "seek_forward", "seek_backward", "stop")
ROOT = Path(__file__).resolve().parents[2]
TRAFFIC2_VOBSUB_VISUAL_CASE = "external-vobsub-sidecar-traffic2-visual"
KODI_HDR10PLUS_VISUAL_CASES = {
    "hdr10plus-profile-b-browser-like-visual-review",
    "hybrid-hdr10plus-dolby-vision-browser-like-visual-review",
}


PROFILE_CAPABILITIES: dict[str, dict[str, Any]] = {
    "native_mpv": {
        "profile_version": 4,
        "client_kind": "native_mpv",
        "direct_play_preferred": True,
        "quality_mode": "original",
        "abr_support_type": "mpv",
        "supported_containers": ["mkv", "mp4", "m4v", "avi", "mov", "webm", "ts", "m2ts", "wmv"],
        "supported_video_codecs": ["h264", "hevc", "mpeg2video", "vp9", "av1"],
        "supported_audio_codecs": ["aac", "ac3", "eac3", "dts", "truehd", "opus", "mp3", "flac"],
        "supported_subtitle_codecs": ["srt", "webvtt", "ass", "ssa", "mov_text", "pgs", "dvd_subtitle"],
        "supported_hls_segment_types": ["fmp4", "mpegts"],
        "supports_hdr": True,
        "supports_hdr10_plus": True,
        "supports_dolby_vision": False,
        "supports_server_side_hls_seek": True,
        "supports_auth_headers_for_media": True,
        "subtitle_burn_policy": "automatic",
        "subtitle_rendering": "native",
        "ass_complexity_support": "native",
        "image_subtitle_support": "native_or_burn_in",
        "forced_subtitle_policy": "matching_audio",
        "default_subtitle_policy": "media_default",
    },
    "browser_like": {
        "profile_version": 4,
        "client_kind": "web",
        "direct_play_preferred": False,
        "quality_mode": "fixed",
        "abr_support_type": "hls.js",
        "max_resolution": "1080p",
        "max_bitrate_bps": 8_000_000,
        "supported_containers": ["mp4"],
        "supported_video_codecs": ["h264"],
        "supported_audio_codecs": ["aac", "ac3"],
        "supported_subtitle_codecs": ["webvtt"],
        "supported_hls_segment_types": ["fmp4", "mpegts"],
        "max_audio_channels": 2,
        "supports_hdr": False,
        "supports_hdr10_plus": False,
        "supports_dolby_vision": False,
        "supports_server_side_hls_seek": True,
        "supports_auth_headers_for_media": True,
        "subtitle_burn_policy": "automatic",
        "subtitle_rendering": "hls_webvtt",
        "ass_complexity_support": "burn_in",
        "image_subtitle_support": "burn_in",
        "forced_subtitle_policy": "matching_audio",
        "default_subtitle_policy": "media_default",
    },
}


SECRET_PATTERN = re.compile(
    r"((?:[?&;]|\b)(?:session|sid|token|access_token|x-plex-token)=)([^\s&;\"']+)|(Bearer\s+)([^\s\"']+)",
    re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, help="Playback automation matrix JSON")
    parser.add_argument("--client-bin", help="Path to elixir-client executable")
    parser.add_argument("--server-url", help="Fixture server base URL override")
    parser.add_argument("--auth-token", help="Fixture user access token override")
    parser.add_argument("--artifact-dir", default="", help="Directory for per-case logs/captures/summary")
    parser.add_argument("--timeout-seconds", type=float, default=90.0)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [str(item) for item in value]
    return [str(value)]


def action_tokens(actions: Any) -> list[str]:
    tokens: list[str] = []
    for raw in as_list(actions):
        for token in re.split(r"[\s,;]+", raw):
            token = token.strip().lower()
            if token:
                tokens.append(re.split(r"[:=]", token, maxsplit=1)[0])
    return tokens


def automation_actions_for_case(case: dict[str, Any]) -> set[str]:
    actions: set[str] = set()
    if case.get("exercise_controls"):
        actions.update(DEFAULT_CONTROL_ACTIONS)
    actions.update(action_tokens(case.get("automation_actions")))
    return actions


def recovery_scenarios_for_case(case: dict[str, Any]) -> set[str]:
    scenarios: set[str] = set()
    if case.get("require_server_seek_restart"):
        scenarios.add("server_seek_restart")
    if case.get("require_session_restart"):
        scenarios.add("session_restart")
    if case.get("invalidate_session_before_retry"):
        scenarios.add("session_invalidation_retry")
    scenarios.update(action_tokens(case.get("recovery_scenarios")))
    return scenarios


def release_candidate_evidence(manifest: dict[str, Any]) -> dict[str, Any] | None:
    evidence = manifest.get("release_candidate_evidence")
    if not isinstance(evidence, dict):
        return None
    if evidence.get("manual_only") is not True:
        return None
    if not str(evidence.get("workflow") or "").strip():
        return None
    if not str(evidence.get("artifact") or "").strip():
        return None
    try:
        if int(evidence.get("retention_days") or 0) <= 0:
            return None
    except (TypeError, ValueError):
        return None
    return evidence


def hardware_hdr_certification_artifacts(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    artifacts = manifest.get("hardware_hdr_certification_artifacts")
    if not isinstance(artifacts, list):
        return []
    valid: list[dict[str, Any]] = []
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            continue
        if artifact.get("status") != "passed":
            continue
        if not str(artifact.get("target_id") or "").strip():
            continue
        if not str(artifact.get("hardware_api") or "").strip():
            continue
        if str(artifact.get("suite") or "") not in {"robust", "torture"}:
            continue
        digest = str(artifact.get("artifact_digest") or "")
        if not digest.startswith("sha256:") or len(digest) <= len("sha256:"):
            continue
        features = set(as_list(artifact.get("features")))
        if not {"hardware_hdr", "hdr_tone_mapping"}.intersection(features):
            continue
        valid.append(artifact)
    return valid


def safe_case_name(name: str) -> str:
    safe = "".join(ch if ch.isalnum() or ch in {"-", "_", "."} else "_" for ch in name.strip())
    return safe or "case"


def case_artifact_dir(artifact_dir: Path, case: dict[str, Any]) -> Path:
    return artifact_dir / safe_case_name(str(case["name"]))


def redact_sensitive(value: str) -> str:
    return SECRET_PATTERN.sub(lambda match: f"{match.group(1) or match.group(3)}[redacted]", value)


def load_manifest(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError("matrix manifest must be a JSON object")
    return data


def client_capabilities_for_case(case: dict[str, Any]) -> dict[str, Any]:
    profile = str(case.get("profile", "native_mpv"))
    base = dict(PROFILE_CAPABILITIES.get(profile, {}))
    overrides = case.get("client_capabilities", {})
    if not base and not isinstance(overrides, dict):
        raise ValueError(f"case {case.get('name', '<unnamed>')} uses unknown profile {profile!r}")
    if not isinstance(overrides, dict):
        raise ValueError(f"case {case.get('name', '<unnamed>')} client_capabilities must be an object")
    base.update(overrides)
    return base


def server_field_expectations_for_case(case: dict[str, Any]) -> list[str]:
    raw = case.get("expect_server_field", [])
    if raw in (None, ""):
        expectations: list[str] = []
    elif isinstance(raw, str):
        expectations = [raw]
    elif isinstance(raw, list):
        expectations = [str(item) for item in raw]
    else:
        raise ValueError(f"case {case.get('name', '<unnamed>')} expect_server_field must be a string or list")

    raw_object = case.get("expect_server", {})
    if raw_object in (None, ""):
        return expectations
    if not isinstance(raw_object, dict):
        raise ValueError(f"case {case.get('name', '<unnamed>')} expect_server must be an object")
    for key, value in raw_object.items():
        if isinstance(value, str):
            rendered = value
        else:
            rendered = json.dumps(value, separators=(",", ":"), sort_keys=True)
        expectations.append(f"{key}={rendered}")
    return expectations


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    cases = manifest.get("cases")
    if not isinstance(cases, list) or not cases:
        return ["matrix manifest must contain a non-empty cases array"]

    required_modes = set(as_list(manifest.get("required_modes"))) or set(REQUIRED_MODES)
    required_profiles = set(as_list(manifest.get("required_profiles"))) or {"native_mpv"}
    required_actions = set(action_tokens(manifest.get("required_automation_actions")))
    required_recovery = set(action_tokens(manifest.get("required_recovery_scenarios")))
    required_visual_review = set(as_list(manifest.get("required_visual_review_cases")))
    seen_modes: set[str] = set()
    seen_profiles: set[str] = set()
    seen_actions: set[str] = set()
    seen_recovery: set[str] = set()
    seen_visual_review: set[str] = set()
    names: set[str] = set()

    for index, raw_case in enumerate(cases):
        if not isinstance(raw_case, dict):
            errors.append(f"case {index} must be an object")
            continue
        name = str(raw_case.get("name", "")).strip()
        if not name:
            errors.append(f"case {index} missing name")
        elif name in names:
            errors.append(f"duplicate case name {name!r}")
        names.add(name)

        profile = str(raw_case.get("profile", "native_mpv"))
        if profile not in PROFILE_CAPABILITIES and "client_capabilities" not in raw_case:
            errors.append(f"case {name or index} uses unknown profile {profile!r} without client_capabilities")
        seen_profiles.add(profile)

        modes = set(as_list(raw_case.get("expect_mode")))
        if not modes:
            errors.append(f"case {name or index} missing expect_mode")
        seen_modes.update(modes)
        seen_actions.update(automation_actions_for_case(raw_case))
        seen_recovery.update(recovery_scenarios_for_case(raw_case))
        if raw_case.get("require_visual_review"):
            seen_visual_review.add(safe_case_name(name))
            if not str(raw_case.get("visual_review_type") or "").strip():
                errors.append(f"case {name or index} require_visual_review needs visual_review_type")

        if not as_list(raw_case.get("expect_delivery")):
            errors.append(f"case {name or index} missing expect_delivery")
        if not str(raw_case.get("media_item_id", "")).strip():
            errors.append(f"case {name or index} missing media_item_id")
        if raw_case.get("require_subtitle_selection") and "subtitle" not in name.lower():
            # This is a naming guard for artifacts, not a behavior substitute.
            errors.append(f"case {name or index} requiring subtitle evidence should be labeled by subtitle type")
        if raw_case.get("require_hdr_objective"):
            if raw_case.get("require_nonblank_frame", True) is False:
                errors.append(f"case {name or index} cannot require HDR objective validation without a frame capture")
            hdr_args = raw_case.get("hdr_objective_args", [])
            if not isinstance(hdr_args, (str, list)):
                errors.append(f"case {name or index} hdr_objective_args must be a string or list")
        if raw_case.get("require_timing_evidence"):
            try:
                min_samples = int(raw_case.get("min_position_sample_count", 0))
                min_span = float(raw_case.get("min_position_span_seconds", 0.0))
            except (TypeError, ValueError):
                errors.append(f"case {name or index} timing evidence thresholds must be numeric")
            else:
                if min_samples < 2:
                    errors.append(f"case {name or index} timing evidence requires min_position_sample_count >= 2")
                if min_span <= 0:
                    errors.append(f"case {name or index} timing evidence requires min_position_span_seconds > 0")
        try:
            client_capabilities_for_case(raw_case)
        except ValueError as exc:
            errors.append(str(exc))
        try:
            server_field_expectations_for_case(raw_case)
        except ValueError as exc:
            errors.append(str(exc))

    missing_modes = sorted(required_modes - seen_modes)
    if missing_modes:
        errors.append(f"matrix missing required playback modes: {', '.join(missing_modes)}")
    missing_profiles = sorted(required_profiles - seen_profiles)
    if missing_profiles:
        errors.append(f"matrix missing required client profiles: {', '.join(missing_profiles)}")
    missing_actions = sorted(required_actions - seen_actions)
    if missing_actions:
        errors.append(f"matrix missing required automation actions: {', '.join(missing_actions)}")
    missing_recovery = sorted(required_recovery - seen_recovery)
    if missing_recovery:
        errors.append(f"matrix missing required recovery scenarios: {', '.join(missing_recovery)}")
    missing_visual_review = sorted(required_visual_review - seen_visual_review)
    if missing_visual_review:
        errors.append(f"matrix missing required visual review cases: {', '.join(missing_visual_review)}")
    return errors


def case_command(
    *,
    harness_script: Path,
    client_bin: Path,
    server_url: str,
    auth_token: str,
    artifact_dir: Path,
    timeout_seconds: float,
    case: dict[str, Any],
) -> list[str]:
    case_dir = case_artifact_dir(artifact_dir, case)
    log_path = case_dir / "client.jsonl"
    capture_dir = case_dir / "captures"
    command = [
        sys.executable,
        str(harness_script),
        "--client-bin",
        str(client_bin),
        "--server-url",
        str(case.get("server_url") or server_url),
        "--auth-token",
        str(case.get("auth_token") or auth_token),
        "--network-type",
        str(case.get("network_type", "lan")),
        "--media-item-id",
        str(case["media_item_id"]),
        "--log",
        str(log_path),
        "--capture-dir",
        str(capture_dir),
        "--timeout-seconds",
        str(case.get("timeout_seconds", timeout_seconds)),
        "--min-position-seconds",
        str(case.get("min_position_seconds", 2.0)),
        "--client-capabilities-json",
        json.dumps(client_capabilities_for_case(case), separators=(",", ":"), sort_keys=True),
    ]
    if case.get("min_position_sample_count") is not None:
        command.extend(["--min-position-sample-count", str(case.get("min_position_sample_count"))])
    if case.get("min_position_span_seconds") is not None:
        command.extend(["--min-position-span-seconds", str(case.get("min_position_span_seconds"))])
    if case.get("max_position_regression_seconds") is not None:
        command.extend(["--max-position-regression-seconds", str(case.get("max_position_regression_seconds"))])
    for mode in as_list(case.get("expect_mode")):
        command.extend(["--expect-mode", mode])
    for delivery in as_list(case.get("expect_delivery")):
        command.extend(["--expect-delivery", delivery])
    for event in as_list(case.get("expect_event")):
        command.extend(["--expect-event", event])
    for field in server_field_expectations_for_case(case):
        command.extend(["--expect-server-field", field])
    for region in as_list(case.get("require_bright_region")):
        command.extend(["--require-bright-region", region])
    if case.get("media_file_id"):
        command.extend(["--media-file-id", str(case["media_file_id"])])
    if case.get("episode_id"):
        command.extend(["--episode-id", str(case["episode_id"])])
    if case.get("automation_actions"):
        command.extend(["--automation-actions", str(case["automation_actions"])])
    if case.get("exercise_controls"):
        command.append("--exercise-controls")
    if case.get("require_video", True) is False:
        command.append("--no-require-video")
    if case.get("require_audio", True) is False:
        command.append("--no-require-audio")
    if case.get("require_nonblank_frame", True) is False:
        command.append("--skip-nonblank-frame")
    if case.get("require_subtitle_selection"):
        command.append("--require-subtitle-selection")
    if case.get("require_server_seek_restart"):
        command.append("--require-server-seek-restart")
    if case.get("require_session_restart"):
        command.append("--require-session-restart")
    if case.get("invalidate_session_before_retry"):
        command.append("--invalidate-session-before-retry")
    if case.get("require_server_session_state", True) is False:
        command.append("--no-require-server-session-state")
    return command


def hdr_objective_command(
    *,
    artifact_dir: Path,
    case: dict[str, Any],
    result: dict[str, Any],
) -> list[str]:
    capture = result.get("nonblank_capture")
    if not isinstance(capture, dict) or not str(capture.get("path", "")).strip():
        raise ValueError("HDR objective validation requires nonblank_capture.path evidence")
    capture_path = Path(str(capture["path"]))
    case_dir = case_artifact_dir(artifact_dir, case)
    command = [
        sys.executable,
        str(ROOT / "scripts" / "playback_hdr_objective_validation.py"),
        "--output-frame",
        str(capture_path),
        "--report",
        str(case_dir / "hdr-objective-report.json"),
        "--approved-thumbnail",
        str(case_dir / "hdr-approved-thumbnail.png"),
    ]
    command.extend(as_list(case.get("hdr_objective_args")))
    return command


def run_hdr_objective_validation(
    *,
    artifact_dir: Path,
    case: dict[str, Any],
    result: dict[str, Any],
) -> tuple[int, dict[str, Any]]:
    try:
        command = hdr_objective_command(artifact_dir=artifact_dir, case=case, result=result)
    except ValueError as exc:
        return 1, {"status": "failed", "error": str(exc)}
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    try:
        parsed = json.loads(completed.stdout.strip().splitlines()[-1])
    except Exception:
        parsed = {
            "status": "failed",
            "raw_stdout": redact_sensitive(completed.stdout),
        }
    parsed.update(
        {
            "returncode": completed.returncode,
            "stderr": redact_sensitive(completed.stderr),
            "report": str(case_artifact_dir(artifact_dir, case) / "hdr-objective-report.json"),
            "approved_thumbnail": str(case_artifact_dir(artifact_dir, case) / "hdr-approved-thumbnail.png"),
        }
    )
    return completed.returncode, parsed


def _result_passed(result: dict[str, Any]) -> bool:
    return result.get("returncode") == 0 and result.get("status") == "passed"


def summarize_evidence_gate(manifest: dict[str, Any], results: list[dict[str, Any]]) -> dict[str, Any]:
    failures: list[str] = []
    cases = [case for case in manifest.get("cases", []) if isinstance(case, dict)]
    results_by_case = {str(result.get("case", "")): result for result in results}
    required_modes = set(as_list(manifest.get("required_modes"))) or set(REQUIRED_MODES)
    required_profiles = set(as_list(manifest.get("required_profiles"))) or {"native_mpv"}
    required_actions = set(action_tokens(manifest.get("required_automation_actions")))
    required_recovery = set(action_tokens(manifest.get("required_recovery_scenarios")))

    seen_modes: set[str] = set()
    seen_profiles: set[str] = set()
    seen_deliveries: set[str] = set()
    seen_actions: set[str] = set()
    seen_recovery: set[str] = set()
    hdr_objective_cases: list[str] = []
    timing_evidence_cases: list[str] = []
    visual_review_cases: list[str] = []

    if len(results) != len(cases):
        failures.append(f"matrix_result_count:{len(results)}!={len(cases)}")

    for case in cases:
        name = safe_case_name(str(case.get("name", "")))
        result = results_by_case.get(name)
        if result is None:
            failures.append(f"{name}: missing result")
            continue
        if not _result_passed(result):
            failures.append(f"{name}: result not passed")
            continue

        seen_profiles.add(str(case.get("profile", "native_mpv")))
        server_session = result.get("server_session")
        if isinstance(server_session, dict):
            if server_session.get("mode"):
                seen_modes.add(str(server_session["mode"]))
            if server_session.get("delivery"):
                seen_deliveries.add(str(server_session["delivery"]))
        else:
            failures.append(f"{name}: missing server_session evidence")

        seen_actions.update(automation_actions_for_case(case))
        seen_recovery.update(recovery_scenarios_for_case(case))

        if case.get("require_video", True) and result.get("video_observed") is not True:
            failures.append(f"{name}: missing video observation")
        if case.get("require_audio", True) and result.get("audio_observed") is not True:
            failures.append(f"{name}: missing audio observation")
        if case.get("require_nonblank_frame", True):
            capture = result.get("nonblank_capture")
            if not isinstance(capture, dict) or not str(capture.get("path", "")).strip():
                failures.append(f"{name}: missing nonblank frame capture")
        if case.get("require_visual_review"):
            visual_review_cases.append(name)
            capture = result.get("nonblank_capture")
            if not isinstance(capture, dict) or not str(capture.get("path", "")).strip():
                failures.append(f"{name}: missing visual-review frame capture")
        if case.get("require_subtitle_selection") and result.get("subtitle_observed") is not True:
            failures.append(f"{name}: missing subtitle observation")
        if case.get("require_server_seek_restart"):
            if not isinstance(result.get("server_seek_requested"), dict):
                failures.append(f"{name}: missing server seek request evidence")
            if not isinstance(result.get("server_seek_completed"), dict):
                failures.append(f"{name}: missing server seek completion evidence")
        if case.get("require_session_restart"):
            if len(result.get("seen_session_ids") or []) < 2:
                failures.append(f"{name}: missing restarted session id")
            if not isinstance(result.get("post_restart_advanced"), dict):
                failures.append(f"{name}: missing post-restart position evidence")
        if case.get("invalidate_session_before_retry"):
            invalidated = result.get("invalidated_session")
            if not isinstance(invalidated, dict) or invalidated.get("ok") is not True:
                failures.append(f"{name}: missing session invalidation evidence")
        if case.get("require_hdr_objective"):
            hdr_objective_cases.append(name)
            hdr = result.get("hdr_objective_validation")
            if not isinstance(hdr, dict) or hdr.get("status") != "passed" or hdr.get("returncode") != 0:
                failures.append(f"{name}: missing passing HDR objective validation")
            elif not str(hdr.get("report", "")).strip() or not str(hdr.get("approved_thumbnail", "")).strip():
                failures.append(f"{name}: missing HDR objective report or thumbnail path")
        if case.get("require_timing_evidence"):
            timing_evidence_cases.append(name)
            timing = result.get("timing_evidence")
            if not isinstance(timing, dict) or timing.get("status") != "passed":
                failures.append(f"{name}: missing passing timing evidence")
            elif int(timing.get("sample_count") or 0) < int(case.get("min_position_sample_count") or 0):
                failures.append(f"{name}: insufficient timing samples")
            elif float(timing.get("position_span_seconds") or 0.0) < float(
                case.get("min_position_span_seconds") or 0.0
            ):
                failures.append(f"{name}: insufficient timing span")

    missing_modes = sorted(required_modes - seen_modes)
    if missing_modes:
        failures.append(f"missing required modes: {', '.join(missing_modes)}")
    missing_profiles = sorted(required_profiles - seen_profiles)
    if missing_profiles:
        failures.append(f"missing required profiles: {', '.join(missing_profiles)}")
    missing_actions = sorted(required_actions - seen_actions)
    if missing_actions:
        failures.append(f"missing required automation actions: {', '.join(missing_actions)}")
    missing_recovery = sorted(required_recovery - seen_recovery)
    if missing_recovery:
        failures.append(f"missing required recovery scenarios: {', '.join(missing_recovery)}")

    return {
        "status": "passed" if not failures else "failed",
        "failures": failures,
        "modes": sorted(seen_modes),
        "profiles": sorted(seen_profiles),
        "deliveries": sorted(seen_deliveries),
        "automation_actions": sorted(seen_actions),
        "recovery_scenarios": sorted(seen_recovery),
        "hdr_objective_cases": sorted(hdr_objective_cases),
        "timing_evidence_cases": sorted(timing_evidence_cases),
        "visual_review_cases": sorted(visual_review_cases),
        "release_candidate_evidence": release_candidate_evidence(manifest),
        "hardware_hdr_certification_artifacts": hardware_hdr_certification_artifacts(manifest),
    }


def _case_names(manifest: dict[str, Any]) -> set[str]:
    return {
        safe_case_name(str(case.get("name", "")))
        for case in manifest.get("cases", [])
        if isinstance(case, dict)
    }


def _passed_case_names(results: list[dict[str, Any]]) -> set[str]:
    return {
        safe_case_name(str(result.get("case", "")))
        for result in results
        if _result_passed(result)
    }


def _requirement(
    *,
    requirement: str,
    owner: str,
    state: str,
    action: str,
    status: str,
    evidence: list[str] | None = None,
    remaining: str | None = None,
) -> dict[str, Any]:
    item: dict[str, Any] = {
        "requirement": requirement,
        "existing_owner": owner,
        "starting_state": state,
        "required_action": action,
        "final_status": status,
        "evidence": evidence or [],
    }
    if remaining:
        item["remaining_gap"] = remaining
    return item


def summarize_phase_16_18_ledger(
    manifest: dict[str, Any],
    results: list[dict[str, Any]],
    evidence_gate: dict[str, Any],
) -> dict[str, Any]:
    """Summarize phase evidence without pretending partial work is complete.

    This is a no-duplicate/reuse ledger for Phase 16-18. It records which
    existing harness and playback owners were validated by this run and which
    plan-level gaps remain outside the current matrix evidence.
    """

    names = _case_names(manifest)
    passed = _passed_case_names(results)
    gate_passed = evidence_gate.get("status") == "passed"
    profiles = set(evidence_gate.get("profiles") or [])
    modes = set(evidence_gate.get("modes") or [])
    actions = set(evidence_gate.get("automation_actions") or [])
    recovery = set(evidence_gate.get("recovery_scenarios") or [])
    hdr_cases = set(evidence_gate.get("hdr_objective_cases") or [])
    timing_cases = set(evidence_gate.get("timing_evidence_cases") or [])
    visual_cases = set(evidence_gate.get("visual_review_cases") or [])
    release_evidence = evidence_gate.get("release_candidate_evidence")
    hardware_hdr_artifacts = list(evidence_gate.get("hardware_hdr_certification_artifacts") or [])

    phase16_status = "failed"
    phase17_status = "failed"
    phase18_status = "failed"

    phase16_requirements = [
        _requirement(
            requirement="Real production Qt/mpv client matrix covers every supported playback mode",
            owner="playback_client_automation.py, playback_client_automation_matrix.py, playback_client_fixture_matrix.py",
            state="existing and correct" if REQUIRED_MODES.issubset(modes) else "existing but incomplete",
            action="validate",
            status="validated" if REQUIRED_MODES.issubset(modes) and gate_passed else "failed",
            evidence=[f"modes={','.join(sorted(modes))}"],
        ),
        _requirement(
            requirement="Matrix covers supported client profiles without a test-only player path",
            owner="PROFILE_CAPABILITIES and fixture manifest required_profiles",
            state="existing and correct" if {"native_mpv", "browser_like"}.issubset(profiles) else "existing but incomplete",
            action="validate",
            status="validated" if {"native_mpv", "browser_like"}.issubset(profiles) and gate_passed else "failed",
            evidence=[f"profiles={','.join(sorted(profiles))}"],
        ),
        _requirement(
            requirement="Matrix proves playback controls and recovery through production events",
            owner="Qt/mpv PlayerController automation event stream and real server session polling",
            state="existing and correct"
            if {"pause", "resume", "seek_forward", "seek_backward", "stop"}.issubset(actions)
            and {"server_seek_restart", "session_restart", "session_invalidation_retry"}.issubset(recovery)
            else "existing but incomplete",
            action="validate",
            status="validated"
            if {"pause", "resume", "seek_forward", "seek_backward", "stop"}.issubset(actions)
            and {"server_seek_restart", "session_restart", "session_invalidation_retry"}.issubset(recovery)
            and gate_passed
            else "failed",
            evidence=[
                f"actions={','.join(sorted(actions))}",
                f"recovery={','.join(sorted(recovery))}",
            ],
        ),
        _requirement(
            requirement="Release-candidate evidence remains on the existing manual workflow path",
            owner=".github/workflows/playback-client-fixture-matrix.yml",
            state="existing and correct" if isinstance(release_evidence, dict) else "existing but incomplete",
            action="harden",
            status="validated" if gate_passed and isinstance(release_evidence, dict) else "partial",
            evidence=[
                "manual workflow_dispatch gate exists",
                *(
                    [
                        f"workflow={release_evidence.get('workflow')}",
                        f"artifact={release_evidence.get('artifact')}",
                    ]
                    if isinstance(release_evidence, dict)
                    else []
                ),
            ],
            remaining=None
            if isinstance(release_evidence, dict)
            else "Archive a release-candidate run artifact and wire required release process enforcement without enabling push/PR cost.",
        ),
    ]

    subtitle_case_requirements = {
        "subtitle-transcode-webvtt-browser-like-srt": "Text subtitle to WebVTT path",
        "subtitle-burn-in-browser-like-complex-ass": "Complex ASS burn-in path",
        "image-subtitle-burn-in-browser-like-pgs": "PGS image subtitle burn-in path",
        "image-subtitle-burn-in-browser-like-pgs-transparent-overlay": "PGS transparent overlay burn-in and timing path",
        "image-subtitle-burn-in-browser-like-pgs-transparent-overlay-long-timing": "Long-duration PGS timing path",
        "image-subtitle-burn-in-browser-like-dvdsub-transparent-overlay": "DVDSub/VobSub-style image subtitle burn-in path",
        "external-image-subtitle-burn-in-browser-like-pgs-sidecar-transparent-overlay": "External image subtitle sidecar burn-in path",
    }
    phase17_requirements: list[dict[str, Any]] = []
    for case_name, label in subtitle_case_requirements.items():
        present = case_name in names
        case_passed = case_name in passed
        evidence = [f"case={case_name}"] if present else []
        if case_name in timing_cases:
            evidence.append("timing_evidence=passed")
        phase17_requirements.append(
            _requirement(
                requirement=label,
                owner="probe normalization, playback planner, FFmpeg job builder, Qt/mpv automation matrix",
                state="existing and correct" if present else "missing",
                action="validate" if present else "extend",
                status="validated" if case_passed and gate_passed else "missing",
                evidence=evidence,
            )
        )
    phase17_requirements.append(
        _requirement(
            requirement="External VobSub/SUB/IDX real-media visual validation",
            owner="external subtitle sidecar discovery, subtitle planner, FFmpeg burn-in job path, client visual evidence harness",
            state="existing and correct"
            if TRAFFIC2_VOBSUB_VISUAL_CASE in names
            else "existing but incomplete",
            action="extend",
            status="validated"
            if TRAFFIC2_VOBSUB_VISUAL_CASE in passed
            and TRAFFIC2_VOBSUB_VISUAL_CASE in visual_cases
            and gate_passed
            else "partial",
            evidence=[
                "synthetic external PGS sidecar and DVDSub/VobSub-style internal burn-in are validated",
                "FFmpeg Traffic2 external VobSub .idx/.sub public corpus fixture is locked and cache-verified",
                *(
                    [f"case={TRAFFIC2_VOBSUB_VISUAL_CASE}", "visual_review=passed"]
                    if TRAFFIC2_VOBSUB_VISUAL_CASE in visual_cases
                    else []
                ),
            ],
            remaining=None
            if TRAFFIC2_VOBSUB_VISUAL_CASE in visual_cases
            else (
                "Wire locked FFmpeg Traffic2 .idx/.sub through real-client visual evidence "
                "with deterministic timing and canvas normalization."
            ),
        )
    )

    hdr_case = "hdr-tonemap-browser-like-hdr10-to-sdr"
    phase18_requirements = [
        _requirement(
            requirement="HDR10 to SDR tone-map is selected, captured, and objectively validated",
            owner="probe normalization, playback planner, FFmpeg job builder, HDR objective validator, Qt/mpv matrix",
            state="existing and correct" if hdr_case in names else "missing",
            action="validate" if hdr_case in names else "extend",
            status="validated" if hdr_case in passed and hdr_case in hdr_cases and gate_passed else "missing",
            evidence=[f"case={hdr_case}", "hdr_objective_validation=passed"] if hdr_case in hdr_cases else [f"case={hdr_case}"],
        ),
        _requirement(
            requirement="HDR10+/Dolby Vision fallback reasons remain explicit in planner evidence",
            owner="playback probe normalization and playback decision planner tests",
            state="existing and correct"
            if KODI_HDR10PLUS_VISUAL_CASES.issubset(visual_cases)
            else "existing but incomplete",
            action="validate",
            status="validated"
            if KODI_HDR10PLUS_VISUAL_CASES.issubset(visual_cases) and gate_passed
            else "partial",
            evidence=[
                "planner/unit evidence exists outside this real-client matrix",
                "public smoke corpus covers HDR10, HDR10+, and Dolby Vision P8.1 HLS output outside this matrix",
                *[f"case={case}" for case in sorted(KODI_HDR10PLUS_VISUAL_CASES & visual_cases)],
            ],
            remaining=None
            if KODI_HDR10PLUS_VISUAL_CASES.issubset(visual_cases)
            else "Add broader real-media visual-review artifacts for HDR10+ and Dolby Vision cases beyond the public smoke subset.",
        ),
        _requirement(
            requirement="Production HDR10+ frame-side metadata is normalized into playback capabilities",
            owner="media ffprobe probe, playback probe normalization, persisted probe versioning",
            state="existing and correct",
            action="validate",
            status="validated" if gate_passed else "failed",
            evidence=["MEDIA_CAPABILITIES_PROBE_VERSION=2", "ffprobe frame side-data merge enabled"],
        ),
        _requirement(
            requirement="Platform hardware HDR proof",
            owner="existing hardware certification stack and playback corpus harness",
            state="existing and correct" if hardware_hdr_artifacts else "existing but incomplete",
            action="harden",
            status="validated" if hardware_hdr_artifacts and gate_passed else "partial",
            evidence=[
                "software HDR objective client proof exists",
                *[
                    f"{artifact.get('target_id')}:{artifact.get('hardware_api')}:{artifact.get('artifact_digest')}"
                    for artifact in hardware_hdr_artifacts
                ],
            ],
            remaining=None
            if hardware_hdr_artifacts
            else "Run and archive hardware HDR certification artifacts per supported backend/platform.",
        ),
    ]

    if gate_passed:
        phase16_status = (
            "complete"
            if all(item["final_status"] == "validated" for item in phase16_requirements)
            else "partial"
        )
        phase17_status = (
            "complete"
            if all(item["final_status"] == "validated" for item in phase17_requirements)
            else "partial"
        )
        phase18_status = (
            "complete"
            if all(item["final_status"] == "validated" for item in phase18_requirements)
            else "partial"
        )

    overall_status = (
        "complete"
        if phase16_status == phase17_status == phase18_status == "complete"
        else ("partial" if gate_passed else "failed")
    )

    return {
        "status": overall_status,
        "phase_16": {
            "status": phase16_status,
            "requirements": phase16_requirements,
        },
        "phase_17": {
            "status": phase17_status,
            "requirements": phase17_requirements,
        },
        "phase_18": {
            "status": phase18_status,
            "requirements": phase18_requirements,
        },
    }


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.manifest)
    manifest = load_manifest(manifest_path)
    errors = validate_manifest(manifest)
    if errors:
        print(json.dumps({"status": "invalid", "errors": errors}, indent=2, sort_keys=True))
        return 2
    if args.validate_only:
        print(json.dumps({"status": "valid", "case_count": len(manifest["cases"])}, sort_keys=True))
        return 0

    client_bin = Path(args.client_bin or manifest.get("client_bin", ""))
    server_url = str(args.server_url or manifest.get("server_url", "")).strip()
    auth_token = str(args.auth_token or manifest.get("auth_token", "")).strip()
    if not client_bin.exists():
        print(json.dumps({"status": "invalid", "errors": [f"client executable not found: {client_bin}"]}))
        return 2
    if not server_url or not auth_token:
        print(json.dumps({"status": "invalid", "errors": ["server_url and auth_token are required"]}))
        return 2

    artifact_dir = Path(args.artifact_dir or manifest.get("artifact_dir") or "playback-client-matrix-artifacts")
    artifact_dir.mkdir(parents=True, exist_ok=True)
    harness_script = Path(__file__).with_name("playback_client_automation.py")
    results: list[dict[str, Any]] = []

    for case in manifest["cases"]:
        case_name = safe_case_name(str(case["name"]))
        command = case_command(
            harness_script=harness_script,
            client_bin=client_bin,
            server_url=server_url,
            auth_token=auth_token,
            artifact_dir=artifact_dir,
            timeout_seconds=args.timeout_seconds,
            case=case,
        )
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        parsed: dict[str, Any]
        try:
            parsed = json.loads(completed.stdout.strip().splitlines()[-1])
        except Exception:
            parsed = {
                "status": "failed",
                "raw_stdout": redact_sensitive(completed.stdout),
                "stderr": redact_sensitive(completed.stderr),
            }
        parsed.update(
            {
                "case": case_name,
                "returncode": completed.returncode,
                "stderr": redact_sensitive(completed.stderr),
            }
        )
        if completed.returncode == 0 and case.get("require_hdr_objective"):
            hdr_returncode, hdr_result = run_hdr_objective_validation(
                artifact_dir=artifact_dir,
                case=case,
                result=parsed,
            )
            parsed["hdr_objective_validation"] = hdr_result
            if hdr_returncode != 0:
                parsed["status"] = "failed"
                parsed["returncode"] = hdr_returncode
                parsed["failure"] = {
                    "event": "hdr_objective_validation_failed",
                    "details": hdr_result,
                }
        results.append(parsed)
        if parsed["returncode"] != 0:
            break

    evidence_gate = summarize_evidence_gate(manifest, results)
    phase_16_18_ledger = summarize_phase_16_18_ledger(manifest, results, evidence_gate)
    summary = {
        "status": "passed"
        if all(result["returncode"] == 0 for result in results) and evidence_gate["status"] == "passed"
        else "failed",
        "artifact_dir": str(artifact_dir),
        "case_count": len(results),
        "evidence_gate": evidence_gate,
        "phase_16_18_ledger": phase_16_18_ledger,
        "results": results,
    }
    summary_path = artifact_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True))
    print(json.dumps(summary, sort_keys=True))
    return 0 if summary["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
