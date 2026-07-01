#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("playback_client_automation_matrix.py")
spec = importlib.util.spec_from_file_location("playback_client_automation_matrix", SCRIPT)
matrix = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(matrix)


def complete_manifest() -> dict:
    modes = [
        "direct_play",
        "direct_stream",
        "audio_transcode",
        "subtitle_transcode",
        "video_transcode",
        "adaptive_transcode",
    ]
    return {
        "required_profiles": ["native_mpv", "browser_like"],
        "cases": [
            {
                "name": f"{mode}-native" if index == 0 else f"{mode}-browser",
                "profile": "native_mpv" if index == 0 else "browser_like",
                "media_item_id": f"media-{index}",
                "expect_mode": mode,
                "expect_delivery": "direct_file" if mode == "direct_play" else "hls_fmp4",
            }
            for index, mode in enumerate(modes)
        ],
    }


def phase_complete_manifest() -> dict:
    manifest = complete_manifest()
    manifest["required_automation_actions"] = [
        "pause",
        "resume",
        "seek_forward",
        "seek_backward",
        "audio_next",
        "subtitle_next",
        "lower_quality",
        "retry_from_current",
        "stop",
    ]
    manifest["required_recovery_scenarios"] = [
        "server_seek_restart",
        "session_restart",
        "session_invalidation_retry",
    ]
    manifest["required_visual_review_cases"] = [
        matrix.TRAFFIC2_VOBSUB_VISUAL_CASE,
        *sorted(matrix.KODI_HDR10PLUS_VISUAL_CASES),
    ]
    manifest["release_candidate_evidence"] = {
        "workflow": ".github/workflows/playback-client-fixture-matrix.yml",
        "artifact": "playback-client-fixture-matrix",
        "manual_only": True,
        "retention_days": 30,
    }
    manifest["hardware_hdr_certification_artifacts"] = [
        {
            "target_id": "win11-nvidia-rtx5090",
            "hardware_api": "nvenc",
            "suite": "robust",
            "status": "passed",
            "artifact_digest": "sha256:" + "a" * 64,
            "features": ["hardware_hdr", "hdr_tone_mapping"],
        }
    ]
    manifest["cases"][0]["exercise_controls"] = True
    manifest["cases"][1]["automation_actions"] = "audio_next,subtitle_next,lower_quality,retry_from_current,stop"
    manifest["cases"][2]["require_server_seek_restart"] = True
    manifest["cases"][3]["require_session_restart"] = True
    manifest["cases"][3]["invalidate_session_before_retry"] = True
    manifest["cases"].extend(
        [
            {
                "name": "subtitle-transcode-webvtt-browser-like-srt",
                "profile": "browser_like",
                "media_item_id": "subtitle-srt",
                "expect_mode": "subtitle_transcode",
                "expect_delivery": "hls_fmp4",
                "require_subtitle_selection": True,
            },
            {
                "name": "subtitle-burn-in-browser-like-complex-ass",
                "profile": "browser_like",
                "media_item_id": "subtitle-ass",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_subtitle_selection": True,
            },
            {
                "name": "image-subtitle-burn-in-browser-like-pgs",
                "profile": "browser_like",
                "media_item_id": "subtitle-pgs",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_subtitle_selection": True,
            },
            {
                "name": "image-subtitle-burn-in-browser-like-pgs-transparent-overlay",
                "profile": "browser_like",
                "media_item_id": "subtitle-pgs-transparent",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_subtitle_selection": True,
            },
            {
                "name": "image-subtitle-burn-in-browser-like-pgs-transparent-overlay-long-timing",
                "profile": "browser_like",
                "media_item_id": "subtitle-pgs-transparent-long",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_subtitle_selection": True,
                "require_timing_evidence": True,
                "min_position_sample_count": 4,
                "min_position_span_seconds": 6.0,
            },
            {
                "name": "image-subtitle-burn-in-browser-like-dvdsub-transparent-overlay",
                "profile": "browser_like",
                "media_item_id": "subtitle-dvdsub-transparent",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_subtitle_selection": True,
            },
            {
                "name": "external-image-subtitle-burn-in-browser-like-pgs-sidecar-transparent-overlay",
                "profile": "browser_like",
                "media_item_id": "subtitle-pgs-sidecar",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_subtitle_selection": True,
            },
            {
                "name": matrix.TRAFFIC2_VOBSUB_VISUAL_CASE,
                "profile": "browser_like",
                "media_item_id": "traffic2",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_visual_review": True,
                "visual_review_type": "external_vobsub",
            },
            {
                "name": "hdr10plus-profile-b-browser-like-visual-review",
                "profile": "browser_like",
                "media_item_id": "kodi-hdr10plus-profile-b",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_visual_review": True,
                "visual_review_type": "hdr10_plus",
            },
            {
                "name": "hybrid-hdr10plus-dolby-vision-browser-like-visual-review",
                "profile": "browser_like",
                "media_item_id": "kodi-hybrid-hdr10plus-dv",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_visual_review": True,
                "visual_review_type": "dolby_vision_hdr10_plus",
            },
            {
                "name": "hdr-tonemap-browser-like-hdr10-to-sdr",
                "profile": "browser_like",
                "media_item_id": "hdr10",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_hdr_objective": True,
                "hdr_objective_args": ["--max-clipped-fraction", "0.99"],
            },
        ]
    )
    return manifest


def passed_results_for_manifest(manifest: dict) -> list[dict]:
    results: list[dict] = []
    for case in manifest["cases"]:
        name = matrix.safe_case_name(case["name"])
        results.append(
            {
                "case": name,
                "status": "passed",
                "returncode": 0,
                "video_observed": True,
                "audio_observed": True,
                "subtitle_observed": bool(case.get("require_subtitle_selection")),
                "nonblank_capture": {"path": f"/tmp/{name}.png"},
                "server_session": {
                    "mode": case["expect_mode"],
                    "delivery": case["expect_delivery"],
                },
                "seen_session_ids": ["session-1", "session-2"]
                if case.get("require_session_restart")
                else ["session-1"],
                "post_restart_advanced": {"position_seconds": 2.0}
                if case.get("require_session_restart")
                else None,
                "invalidated_session": {"ok": True}
                if case.get("invalidate_session_before_retry")
                else None,
                "server_seek_requested": {"server_seek_required": True}
                if case.get("require_server_seek_restart")
                else None,
                "server_seek_completed": {"position_seconds": 4.0}
                if case.get("require_server_seek_restart")
                else None,
                "timing_evidence": {
                    "status": "passed",
                    "sample_count": int(case.get("min_position_sample_count") or 0),
                    "position_span_seconds": float(case.get("min_position_span_seconds") or 0.0),
                    "regressions": [],
                }
                if case.get("require_timing_evidence")
                else None,
                "hdr_objective_validation": {
                    "status": "passed",
                    "returncode": 0,
                    "report": f"/tmp/{name}-hdr-report.json",
                    "approved_thumbnail": f"/tmp/{name}-hdr-thumb.png",
                }
                if case.get("require_hdr_objective")
                else None,
            }
        )
    return results


class PlaybackClientAutomationMatrixTests(unittest.TestCase):
    def test_validate_manifest_requires_all_modes_and_profiles(self) -> None:
        manifest = complete_manifest()
        manifest["cases"] = manifest["cases"][:1]

        errors = matrix.validate_manifest(manifest)

        self.assertTrue(any("matrix missing required playback modes" in error for error in errors), errors)
        self.assertTrue(any("matrix missing required client profiles" in error for error in errors), errors)

    def test_validate_manifest_accepts_complete_mode_and_profile_coverage(self) -> None:
        errors = matrix.validate_manifest(complete_manifest())

        self.assertEqual(errors, [])

    def test_case_command_passes_capability_overrides_to_real_harness(self) -> None:
        case = {
            "name": "video transcode/hdr sdr",
            "profile": "browser_like",
            "media_item_id": "media-1",
            "media_file_id": "file-1",
            "expect_mode": ["video_transcode"],
            "expect_delivery": ["hls_fmp4", "hls_mpegts"],
            "client_capabilities": {
                "supports_hdr": False,
                "max_bitrate_bps": 2_000_000,
            },
            "automation_actions": "pause,resume,seek_forward,stop",
            "require_subtitle_selection": False,
            "expect_server": {
                "selected_audio_track": 1,
                "adaptive": False,
            },
            "expect_server_field": ["active_rung.label=null"],
            "require_bright_region": "subtitle:0.05:0.6:0.9:0.3:2:100",
            "require_server_seek_restart": True,
            "require_session_restart": True,
            "invalidate_session_before_retry": True,
            "require_timing_evidence": True,
            "min_position_sample_count": 4,
            "min_position_span_seconds": 6.0,
            "max_position_regression_seconds": 0.75,
        }
        with tempfile.TemporaryDirectory() as raw:
            command = matrix.case_command(
                harness_script=Path("/tmp/playback_client_automation.py"),
                client_bin=Path("/tmp/elixir-client"),
                server_url="http://127.0.0.1:4000",
                auth_token="token",
                artifact_dir=Path(raw),
                timeout_seconds=30,
                case=case,
            )

        self.assertIn("--client-capabilities-json", command)
        caps = json.loads(command[command.index("--client-capabilities-json") + 1])
        self.assertEqual(caps["client_kind"], "web")
        self.assertEqual(caps["supports_hdr"], False)
        self.assertEqual(caps["max_bitrate_bps"], 2_000_000)
        self.assertEqual(command.count("--expect-delivery"), 2)
        self.assertIn("--media-file-id", command)
        self.assertIn("--automation-actions", command)
        self.assertEqual(command.count("--expect-server-field"), 3)
        self.assertIn("selected_audio_track=1", command)
        self.assertIn("adaptive=false", command)
        self.assertIn("active_rung.label=null", command)
        self.assertIn("--require-bright-region", command)
        self.assertIn("subtitle:0.05:0.6:0.9:0.3:2:100", command)
        self.assertIn("--require-server-seek-restart", command)
        self.assertIn("--require-session-restart", command)
        self.assertIn("--invalidate-session-before-retry", command)
        self.assertIn("--min-position-sample-count", command)
        self.assertEqual(command[command.index("--min-position-sample-count") + 1], "4")
        self.assertIn("--min-position-span-seconds", command)
        self.assertEqual(command[command.index("--min-position-span-seconds") + 1], "6.0")
        self.assertIn("--max-position-regression-seconds", command)
        self.assertEqual(command[command.index("--max-position-regression-seconds") + 1], "0.75")
        self.assertNotIn("--no-require-server-session-state", command)

    def test_validate_manifest_rejects_malformed_server_expectations(self) -> None:
        manifest = complete_manifest()
        manifest["cases"][0]["expect_server"] = ["not", "an", "object"]

        errors = matrix.validate_manifest(manifest)

        self.assertTrue(any("expect_server must be an object" in error for error in errors), errors)

    def test_validate_manifest_requires_declared_automation_actions(self) -> None:
        manifest = complete_manifest()
        manifest["required_automation_actions"] = [
            "pause",
            "resume",
            "seek_forward",
            "seek_backward",
            "audio_next",
            "subtitle_next",
            "lower_quality",
            "stop",
        ]
        manifest["cases"][0]["exercise_controls"] = True
        manifest["cases"][1]["automation_actions"] = "subtitle_next,stop"

        errors = matrix.validate_manifest(manifest)

        self.assertTrue(
            any("matrix missing required automation actions" in error for error in errors),
            errors,
        )
        self.assertTrue(any("audio_next" in error for error in errors), errors)
        self.assertTrue(any("lower_quality" in error for error in errors), errors)

        manifest["cases"][2]["automation_actions"] = "audio_next,lower_quality"
        errors = matrix.validate_manifest(manifest)

        self.assertEqual(errors, [])

    def test_timed_wait_actions_count_as_wait_coverage(self) -> None:
        manifest = complete_manifest()
        manifest["required_automation_actions"] = ["wait", "stop"]
        manifest["cases"][0]["automation_actions"] = "wait:20,stop"

        errors = matrix.validate_manifest(manifest)

        self.assertEqual(errors, [])
        self.assertEqual(matrix.action_tokens("wait:20,wait=3,stop"), ["wait", "wait", "stop"])

    def test_validate_manifest_requires_declared_recovery_scenarios(self) -> None:
        manifest = complete_manifest()
        manifest["required_recovery_scenarios"] = [
            "server_seek_restart",
            "session_restart",
            "session_invalidation_retry",
        ]
        manifest["cases"][0]["require_server_seek_restart"] = True
        manifest["cases"][1]["require_session_restart"] = True

        errors = matrix.validate_manifest(manifest)

        self.assertTrue(
            any("matrix missing required recovery scenarios" in error for error in errors),
            errors,
        )
        self.assertTrue(any("session_invalidation_retry" in error for error in errors), errors)

        manifest["cases"][1]["invalidate_session_before_retry"] = True
        errors = matrix.validate_manifest(manifest)

        self.assertEqual(errors, [])

    def test_validate_manifest_requires_declared_visual_review_cases(self) -> None:
        manifest = complete_manifest()
        manifest["required_visual_review_cases"] = [matrix.TRAFFIC2_VOBSUB_VISUAL_CASE]

        errors = matrix.validate_manifest(manifest)

        self.assertTrue(
            any("matrix missing required visual review cases" in error for error in errors),
            errors,
        )

        manifest["cases"].append(
            {
                "name": matrix.TRAFFIC2_VOBSUB_VISUAL_CASE,
                "profile": "browser_like",
                "media_item_id": "traffic2",
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "require_visual_review": True,
                "visual_review_type": "external_vobsub",
            }
        )
        errors = matrix.validate_manifest(manifest)

        self.assertEqual(errors, [])

    def test_case_command_can_explicitly_disable_server_session_poll_for_narrow_cases(self) -> None:
        case = {
            "name": "direct play local inspection",
            "profile": "native_mpv",
            "media_item_id": "media-1",
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "require_server_session_state": False,
        }
        with tempfile.TemporaryDirectory() as raw:
            command = matrix.case_command(
                harness_script=Path("/tmp/playback_client_automation.py"),
                client_bin=Path("/tmp/elixir-client"),
                server_url="http://127.0.0.1:4000",
                auth_token="token",
                artifact_dir=Path(raw),
                timeout_seconds=30,
                case=case,
            )

        self.assertIn("--no-require-server-session-state", command)

    def test_validate_manifest_rejects_hdr_objective_without_frame_capture(self) -> None:
        manifest = complete_manifest()
        manifest["cases"][0]["require_hdr_objective"] = True
        manifest["cases"][0]["require_nonblank_frame"] = False

        errors = matrix.validate_manifest(manifest)

        self.assertTrue(any("cannot require HDR objective validation" in error for error in errors), errors)

    def test_validate_manifest_requires_useful_timing_evidence_thresholds(self) -> None:
        manifest = complete_manifest()
        manifest["cases"][0]["require_timing_evidence"] = True
        manifest["cases"][0]["min_position_sample_count"] = 1
        manifest["cases"][0]["min_position_span_seconds"] = 0

        errors = matrix.validate_manifest(manifest)

        self.assertTrue(any("min_position_sample_count >= 2" in error for error in errors), errors)
        self.assertTrue(any("min_position_span_seconds > 0" in error for error in errors), errors)

        manifest["cases"][0]["min_position_sample_count"] = 4
        manifest["cases"][0]["min_position_span_seconds"] = 6.0
        errors = matrix.validate_manifest(manifest)

        self.assertEqual(errors, [])

    def test_hdr_objective_command_uses_nonblank_capture_and_case_artifacts(self) -> None:
        case = {
            "name": "hdr tonemap/browser",
            "profile": "browser_like",
            "media_item_id": "media-1",
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "require_hdr_objective": True,
            "hdr_objective_args": ["--max-clipped-fraction", "0.99"],
        }
        result = {"nonblank_capture": {"path": "/tmp/frame.png"}}
        command = matrix.hdr_objective_command(
            artifact_dir=Path("/tmp/artifacts"),
            case=case,
            result=result,
        )

        self.assertIn("playback_hdr_objective_validation.py", command[1])
        self.assertIn("--output-frame", command)
        self.assertEqual(command[command.index("--output-frame") + 1], "/tmp/frame.png")
        self.assertIn("/tmp/artifacts/hdr_tonemap_browser/hdr-objective-report.json", command)
        self.assertIn("/tmp/artifacts/hdr_tonemap_browser/hdr-approved-thumbnail.png", command)
        self.assertIn("--max-clipped-fraction", command)

    def test_evidence_gate_passes_complete_summary(self) -> None:
        manifest = complete_manifest()
        gate = matrix.summarize_evidence_gate(manifest, passed_results_for_manifest(manifest))

        self.assertEqual(gate["status"], "passed")
        self.assertEqual(gate["failures"], [])
        self.assertEqual(set(gate["modes"]), set(matrix.REQUIRED_MODES))
        self.assertEqual(set(gate["profiles"]), {"native_mpv", "browser_like"})

    def test_phase_16_18_ledger_is_not_a_false_completion_claim(self) -> None:
        manifest = complete_manifest()
        results = passed_results_for_manifest(manifest)
        gate = matrix.summarize_evidence_gate(manifest, results)

        ledger = matrix.summarize_phase_16_18_ledger(manifest, results, gate)

        self.assertEqual(ledger["status"], "partial")
        self.assertEqual(ledger["phase_16"]["status"], "partial")
        self.assertEqual(ledger["phase_17"]["status"], "partial")
        self.assertEqual(ledger["phase_18"]["status"], "partial")
        self.assertTrue(
            any(
                item.get("remaining_gap", "").startswith("Wire locked FFmpeg Traffic2 .idx/.sub")
                for item in ledger["phase_17"]["requirements"]
            ),
            ledger["phase_17"],
        )
        self.assertTrue(
            any(
                item.get("remaining_gap", "").startswith("Run and archive hardware HDR certification")
                for item in ledger["phase_18"]["requirements"]
            ),
            ledger["phase_18"],
        )

    def test_phase_16_18_ledger_completes_only_with_required_evidence(self) -> None:
        manifest = phase_complete_manifest()
        results = passed_results_for_manifest(manifest)
        gate = matrix.summarize_evidence_gate(manifest, results)

        ledger = matrix.summarize_phase_16_18_ledger(manifest, results, gate)

        self.assertEqual(gate["status"], "passed")
        self.assertEqual(ledger["status"], "complete")
        self.assertEqual(ledger["phase_16"]["status"], "complete")
        self.assertEqual(ledger["phase_17"]["status"], "complete")
        self.assertEqual(ledger["phase_18"]["status"], "complete")
        self.assertTrue(
            all(
                item["final_status"] == "validated"
                for phase in ("phase_16", "phase_17", "phase_18")
                for item in ledger[phase]["requirements"]
            )
        )

    def test_evidence_gate_requires_hdr_objective_artifact_when_declared(self) -> None:
        manifest = complete_manifest()
        hdr_case = manifest["cases"][4]
        hdr_case["require_hdr_objective"] = True
        results = passed_results_for_manifest(manifest)
        results[4].pop("hdr_objective_validation", None)

        gate = matrix.summarize_evidence_gate(manifest, results)

        self.assertEqual(gate["status"], "failed")
        self.assertTrue(
            any("missing passing HDR objective validation" in failure for failure in gate["failures"]),
            gate,
        )

        results[4]["hdr_objective_validation"] = {
            "status": "passed",
            "returncode": 0,
            "report": "/tmp/report.json",
            "approved_thumbnail": "/tmp/thumb.png",
        }
        gate = matrix.summarize_evidence_gate(manifest, results)

        self.assertEqual(gate["status"], "passed")

    def test_evidence_gate_requires_timing_evidence_when_declared(self) -> None:
        manifest = complete_manifest()
        timing_case = manifest["cases"][1]
        timing_case["require_timing_evidence"] = True
        timing_case["min_position_sample_count"] = 4
        timing_case["min_position_span_seconds"] = 6.0
        results = passed_results_for_manifest(manifest)
        results[1]["timing_evidence"] = {
            "status": "failed",
            "sample_count": 2,
            "position_span_seconds": 2.0,
        }

        gate = matrix.summarize_evidence_gate(manifest, results)

        self.assertEqual(gate["status"], "failed")
        self.assertTrue(any("missing passing timing evidence" in failure for failure in gate["failures"]), gate)

        results[1]["timing_evidence"] = {
            "status": "passed",
            "sample_count": 4,
            "position_span_seconds": 6.0,
        }
        gate = matrix.summarize_evidence_gate(manifest, results)

        self.assertEqual(gate["status"], "passed")
        self.assertIn("direct_stream-browser", gate["timing_evidence_cases"])

    def test_redacts_token_material_from_artifact_text(self) -> None:
        redacted = matrix.redact_sensitive(
            "GET /segment.m4s?session=abc&token=def Authorization: Bearer secret"
        )

        self.assertIn("session=[redacted]", redacted)
        self.assertIn("token=[redacted]", redacted)
        self.assertIn("Bearer [redacted]", redacted)
        self.assertNotIn("abc", redacted)
        self.assertNotIn("def", redacted)
        self.assertNotIn("secret", redacted)


if __name__ == "__main__":
    unittest.main()
