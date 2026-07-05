#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


FIXTURE_SCRIPT = Path(__file__).with_name("playback_client_fixture_matrix.py")
fixture_spec = importlib.util.spec_from_file_location("playback_client_fixture_matrix", FIXTURE_SCRIPT)
fixture = importlib.util.module_from_spec(fixture_spec)
assert fixture_spec.loader is not None
sys.modules[fixture_spec.name] = fixture
fixture_spec.loader.exec_module(fixture)

MATRIX_SCRIPT = Path(__file__).with_name("playback_client_automation_matrix.py")
matrix_spec = importlib.util.spec_from_file_location("playback_client_automation_matrix", MATRIX_SCRIPT)
matrix = importlib.util.module_from_spec(matrix_spec)
assert matrix_spec.loader is not None
sys.modules[matrix_spec.name] = matrix
matrix_spec.loader.exec_module(matrix)


def complete_ids(include_public_visual: bool = False) -> dict[str, dict[str, str]]:
    ids: dict[str, dict[str, str]] = {}
    fixtures = fixture.fixtures_for_run(include_public_visual)
    for name in fixtures:
        ids[name] = {
            "item_id": f"{name}-item",
            "file_id": f"{name}-file",
            "episode_id": f"{name}-episode",
        }
    return ids


def passed_results_for_cases(cases: list[dict]) -> list[dict]:
    results: list[dict] = []
    for case in cases:
        name = matrix.safe_case_name(case["name"])
        result = {
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
            "post_restart_advanced": {"position_seconds": 4.0}
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
        }
        if case.get("require_hdr_objective"):
            result["hdr_objective_validation"] = {
                "status": "passed",
                "returncode": 0,
                "report": f"/tmp/{name}/hdr-objective-report.json",
                "approved_thumbnail": f"/tmp/{name}/hdr-approved-thumbnail.png",
            }
        results.append(result)
    return results


class PlaybackClientFixtureMatrixTests(unittest.TestCase):
    def test_public_visual_fixtures_are_opt_in(self) -> None:
        self.assertNotIn("traffic2_vobsub_visual", fixture.fixtures_for_run(False))
        selected = fixture.fixtures_for_run(True)

        self.assertIn("traffic2_vobsub_visual", selected)
        self.assertIn("kodi_hdr10plus_profile_b_visual", selected)
        self.assertIn("kodi_hybrid_hdr10plus_dv_visual", selected)

    def test_manifest_cases_cover_required_modes_profiles_and_server_evidence(self) -> None:
        manifest = {
            "required_profiles": ["native_mpv", "browser_like"],
            "required_modes": sorted(matrix.REQUIRED_MODES),
            "required_automation_actions": [
                "pause",
                "resume",
                "seek_forward",
                "seek_backward",
                "audio_next",
                "subtitle_next",
                "lower_quality",
                "retry_from_current",
                "skip_active_segment",
                "up_next_cancel",
                "up_next_play_now",
                "stop",
            ],
            "required_recovery_scenarios": [
                "server_seek_restart",
                "session_restart",
                "session_invalidation_retry",
            ],
            "cases": fixture.manifest_cases(complete_ids()),
        }

        errors = matrix.validate_manifest(manifest)

        self.assertEqual(errors, [])
        modes = {case["expect_mode"] for case in manifest["cases"]}
        profiles = {case["profile"] for case in manifest["cases"]}
        self.assertTrue(matrix.REQUIRED_MODES.issubset(modes))
        self.assertEqual({"native_mpv", "browser_like"}, profiles)
        for case in manifest["cases"]:
            self.assertIsInstance(case.get("expect_server"), dict, case["name"])
            self.assertNotEqual(case["expect_server"], {}, case["name"])

        seek_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "direct-stream-browser-like-hls-seek-restart"
        )
        self.assertTrue(seek_case["require_server_seek_restart"])
        self.assertEqual(seek_case["automation_actions"], "seek_forward,seek_backward,stop")

        retry_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "direct-play-native-mpv-retry-from-current"
        )
        self.assertTrue(retry_case["require_session_restart"])
        self.assertTrue(retry_case["invalidate_session_before_retry"])
        self.assertEqual(retry_case["automation_actions"], "wait:2,retry_from_current,wait,stop")

        skip_case = next(
            case for case in manifest["cases"] if case["name"] == "midm-skip-prompt-native-mpv"
        )
        self.assertEqual(skip_case["automation_actions"], "wait:2,skip_active_segment,stop")
        self.assertEqual(skip_case["expect_mode"], "direct_play")

        auto_skip_case = next(
            case for case in manifest["cases"] if case["name"] == "midm-auto-skip-native-mpv"
        )
        self.assertEqual(auto_skip_case["expect_event"], ["segment_skip_requested"])

        up_next_cancel_case = next(
            case for case in manifest["cases"] if case["name"] == "midm-up-next-cancel-native-mpv"
        )
        self.assertEqual(up_next_cancel_case["automation_actions"], "wait:1,up_next_cancel,stop")
        self.assertIn("up_next_countdown_started", up_next_cancel_case["expect_event"])
        self.assertIn("up_next_cancelled", up_next_cancel_case["expect_event"])

        up_next_play_now_case = next(
            case for case in manifest["cases"] if case["name"] == "midm-up-next-play-now-native-mpv"
        )
        self.assertEqual(
            up_next_play_now_case["automation_actions"],
            "wait:1,up_next_play_now,wait:1,stop",
        )
        self.assertIn("up_next_play_now", up_next_play_now_case["expect_event"])

        up_next_autoplay_case = next(
            case for case in manifest["cases"] if case["name"] == "midm-up-next-autoplay-native-mpv"
        )
        self.assertEqual(up_next_autoplay_case["automation_actions"], "wait:3,stop")
        self.assertIn("up_next_autoplay_starting", up_next_autoplay_case["expect_event"])

        ass_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "subtitle-burn-in-browser-like-complex-ass"
        )
        self.assertEqual(ass_case["expect_mode"], "video_transcode")
        self.assertEqual(ass_case["expect_server"]["subtitle_action"], "burn_in")
        self.assertEqual(
            ass_case["expect_server"]["video_transcode_reason"],
            "subtitle_not_supported",
        )
        self.assertIn("ass_overlay:", ass_case["require_bright_region"])

        pgs_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "image-subtitle-burn-in-browser-like-pgs"
        )
        self.assertEqual(pgs_case["expect_mode"], "video_transcode")
        self.assertEqual(pgs_case["expect_server"]["subtitle_action"], "burn_in")
        self.assertEqual(
            pgs_case["expect_server"]["video_transcode_reason"],
            "subtitle_requires_burn_in",
        )
        self.assertIn("pgs_overlay:", pgs_case["require_bright_region"])

        transparent_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "image-subtitle-burn-in-browser-like-pgs-transparent-overlay"
        )
        self.assertEqual(transparent_case["expect_mode"], "video_transcode")
        self.assertEqual(transparent_case["expect_server"]["subtitle_action"], "burn_in")
        self.assertEqual(
            transparent_case["expect_server"]["video_transcode_reason"],
            "subtitle_requires_burn_in",
        )
        self.assertIn(
            "pgs_transparent_gap:0.46:0.77:0.08:0.12:80:100:190:220",
            transparent_case["require_bright_region"],
        )
        self.assertTrue(transparent_case["require_timing_evidence"])
        self.assertEqual(transparent_case["min_position_sample_count"], 4)
        self.assertEqual(transparent_case["min_position_span_seconds"], 6.0)
        self.assertEqual(transparent_case["max_position_regression_seconds"], 0.75)

        long_timing_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "image-subtitle-burn-in-browser-like-pgs-transparent-overlay-long-timing"
        )
        self.assertEqual(long_timing_case["expect_mode"], "video_transcode")
        self.assertEqual(long_timing_case["expect_server"]["subtitle_action"], "burn_in")
        self.assertEqual(long_timing_case["automation_actions"], "wait:22,stop")
        self.assertEqual(long_timing_case["expect_event"], ["automation_wait", "stop_requested"])
        self.assertEqual(long_timing_case["timeout_seconds"], 90)
        self.assertTrue(long_timing_case["require_timing_evidence"])
        self.assertEqual(long_timing_case["min_position_sample_count"], 10)
        self.assertEqual(long_timing_case["min_position_span_seconds"], 20.0)
        self.assertEqual(long_timing_case["max_position_regression_seconds"], 0.75)
        self.assertIn(
            "pgs_long_gap:0.46:0.77:0.08:0.12:80:100:190:220",
            long_timing_case["require_bright_region"],
        )

        dvdsub_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "image-subtitle-burn-in-browser-like-dvdsub-transparent-overlay"
        )
        self.assertEqual(dvdsub_case["expect_mode"], "video_transcode")
        self.assertEqual(dvdsub_case["expect_server"]["subtitle_action"], "burn_in")
        self.assertEqual(
            dvdsub_case["expect_server"]["video_transcode_reason"],
            "subtitle_requires_burn_in",
        )
        self.assertIn(
            "dvdsub_gap:0.46:0.77:0.08:0.12:80:100:190:220",
            dvdsub_case["require_bright_region"],
        )

        external_pgs_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "external-image-subtitle-burn-in-browser-like-pgs-sidecar-transparent-overlay"
        )
        self.assertEqual(external_pgs_case["expect_mode"], "video_transcode")
        self.assertEqual(external_pgs_case["expect_server"]["selected_subtitle_track"], -100000)
        self.assertEqual(external_pgs_case["expect_server"]["subtitle_action"], "burn_in")
        self.assertEqual(
            external_pgs_case["expect_server"]["video_transcode_reason"],
            "subtitle_requires_burn_in",
        )
        self.assertIn(
            "external_pgs_gap:0.46:0.77:0.08:0.12:80:100:190:220",
            external_pgs_case["require_bright_region"],
        )

        hdr_case = next(
            case
            for case in manifest["cases"]
            if case["name"] == "hdr-tonemap-browser-like-hdr10-to-sdr"
        )
        self.assertEqual(hdr_case["expect_server"]["hdr_action"], "tone_map_to_sdr")
        self.assertEqual(
            hdr_case["expect_server"]["video_transcode_reason"],
            "hdr_tone_mapping_required",
        )
        self.assertEqual(hdr_case["expect_server"]["tone_map.output_primaries"], "bt709")
        self.assertTrue(hdr_case["require_hdr_objective"])
        self.assertIn("--min-output-luma-range", hdr_case["hdr_objective_args"])

    def test_public_visual_manifest_cases_are_declared_and_validated(self) -> None:
        cases = fixture.manifest_cases(complete_ids(include_public_visual=True))
        manifest = {
            "required_profiles": ["native_mpv", "browser_like"],
            "required_modes": sorted(matrix.REQUIRED_MODES),
            "required_visual_review_cases": [
                fixture.TRAFFIC2_VOBSUB_VISUAL_CASE,
                fixture.KODI_HDR10PLUS_PROFILE_B_VISUAL_CASE,
                fixture.KODI_HYBRID_HDR10PLUS_DV_VISUAL_CASE,
            ],
            "cases": cases,
        }

        errors = matrix.validate_manifest(manifest)

        self.assertEqual(errors, [])
        by_name = {case["name"]: case for case in cases}
        traffic2_case = by_name[fixture.TRAFFIC2_VOBSUB_VISUAL_CASE]
        self.assertEqual(traffic2_case["expect_server"]["selected_subtitle_track"], -100000)
        self.assertEqual(traffic2_case["visual_review_type"], "external_vobsub")
        self.assertIn("traffic2_vobsub_overlay:", traffic2_case["require_bright_region"])
        self.assertEqual(
            by_name[fixture.KODI_HDR10PLUS_PROFILE_B_VISUAL_CASE]["visual_review_type"],
            "hdr10_plus",
        )
        self.assertEqual(
            by_name[fixture.KODI_HYBRID_HDR10PLUS_DV_VISUAL_CASE]["visual_review_type"],
            "dolby_vision_hdr10_plus",
        )

    def test_release_evidence_requires_complete_archive_metadata(self) -> None:
        args = fixture.argparse.Namespace(
            release_workflow="Playback Client Fixture Matrix",
            release_artifact="playback-client-fixture-matrix",
            release_retention_days=30,
        )

        self.assertEqual(
            fixture.release_candidate_evidence_from_args(args),
            {
                "manual_only": True,
                "workflow": "Playback Client Fixture Matrix",
                "artifact": "playback-client-fixture-matrix",
                "retention_days": 30,
            },
        )

        incomplete = fixture.argparse.Namespace(
            release_workflow="Playback Client Fixture Matrix",
            release_artifact="",
            release_retention_days=30,
        )
        with self.assertRaises(ValueError):
            fixture.release_candidate_evidence_from_args(incomplete)

    def test_hardware_certification_evidence_derives_hdr_features(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            cert = Path(raw) / "certification.json"
            cert.write_text(
                json.dumps(
                    {
                        "status": "passed",
                        "target_id": "win11-nvidia-rtx5090",
                        "suite": "torture",
                        "hardware_api": "nvenc",
                        "artifact_digest": "sha256:" + "1" * 64,
                        "run_id": "123",
                        "commit_sha": "abc",
                        "cases": {
                            "case_reports": [
                                {
                                    "status": "passed",
                                    "features": ["type:hdr10", "resolution:4k"],
                                    "hardware_used": True,
                                }
                            ]
                        },
                    }
                ),
                encoding="utf-8",
            )

            evidence = fixture.hardware_certification_evidence(cert)

        self.assertEqual(evidence["status"], "passed")
        self.assertEqual(evidence["target_id"], "win11-nvidia-rtx5090")
        self.assertEqual(evidence["hardware_api"], "nvenc")
        self.assertEqual(evidence["suite"], "torture")
        self.assertIn("hardware_hdr", evidence["features"])
        self.assertIn("hdr_tone_mapping", evidence["features"])
        self.assertEqual(evidence["run_id"], "123")

    def test_vobsub_sidecar_writer_normalizes_traffic2_timing_and_copies_payload(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            source_dir = root / "public" / "ffmpeg" / "traffic"
            source_dir.mkdir(parents=True)
            (source_dir / "Traffic2.idx").write_text(
                "size: 720x480\n"
                "timestamp: 00:00:16:676, filepos: 000000000\n"
                "timestamp: 00:00:19:745, filepos: 000001000\n",
                encoding="latin-1",
            )
            (source_dir / "Traffic2.sub").write_bytes(b"vobsub-payload")
            out = root / "out" / "Traffic2.eng.idx"
            out.parent.mkdir()
            old_root = fixture.os.environ.get("ELIXIR_PLAYBACK_PUBLIC_CORPUS_ROOT")
            fixture.os.environ["ELIXIR_PLAYBACK_PUBLIC_CORPUS_ROOT"] = str(root / "public")
            try:
                fixture.write_subtitle(
                    out,
                    fixture.SubtitleFixture(
                        codec="idx",
                        extension="idx",
                        kind="image",
                        vobsub_source_rel="ffmpeg/traffic/Traffic2",
                    ),
                    video_width=720,
                    video_height=480,
                )
            finally:
                if old_root is None:
                    fixture.os.environ.pop("ELIXIR_PLAYBACK_PUBLIC_CORPUS_ROOT", None)
                else:
                    fixture.os.environ["ELIXIR_PLAYBACK_PUBLIC_CORPUS_ROOT"] = old_root

            normalized = out.read_text(encoding="latin-1")
            self.assertIn("size: 720x480", normalized)
            self.assertIn("timestamp: 00:00:01:000, filepos: 000000000", normalized)
            self.assertIn("timestamp: 00:00:01:750, filepos: 000001000", normalized)
            self.assertEqual(out.with_suffix(".sub").read_bytes(), b"vobsub-payload")

    def test_fixture_manifest_phase_16_18_ledger_tracks_reused_evidence_and_remaining_gaps(self) -> None:
        cases = fixture.manifest_cases(complete_ids())
        manifest = {
            "required_profiles": ["native_mpv", "browser_like"],
            "required_modes": sorted(matrix.REQUIRED_MODES),
            "required_automation_actions": [
                "pause",
                "resume",
                "seek_forward",
                "seek_backward",
                "audio_next",
                "subtitle_next",
                "lower_quality",
                "retry_from_current",
                "skip_active_segment",
                "up_next_cancel",
                "up_next_play_now",
                "stop",
            ],
            "required_recovery_scenarios": [
                "server_seek_restart",
                "session_restart",
                "session_invalidation_retry",
            ],
            "cases": cases,
        }
        results = passed_results_for_cases(cases)
        gate = matrix.summarize_evidence_gate(manifest, results)

        ledger = matrix.summarize_phase_16_18_ledger(manifest, results, gate)

        self.assertEqual(gate["status"], "passed")
        self.assertEqual(ledger["status"], "partial")
        phase17_status_by_requirement = {
            item["requirement"]: item["final_status"]
            for item in ledger["phase_17"]["requirements"]
        }
        self.assertEqual(
            phase17_status_by_requirement["Complex ASS burn-in path"],
            "validated",
        )
        self.assertEqual(
            phase17_status_by_requirement["External image subtitle sidecar burn-in path"],
            "validated",
        )
        self.assertEqual(
            phase17_status_by_requirement["External VobSub/SUB/IDX real-media visual validation"],
            "partial",
        )
        phase18_status_by_requirement = {
            item["requirement"]: item["final_status"]
            for item in ledger["phase_18"]["requirements"]
        }
        self.assertEqual(
            phase18_status_by_requirement["HDR10 to SDR tone-map is selected, captured, and objectively validated"],
            "validated",
        )
        self.assertEqual(
            phase18_status_by_requirement["Platform hardware HDR proof"],
            "partial",
        )

    def test_public_visual_manifest_with_release_and_hardware_evidence_completes_ledger(self) -> None:
        cases = fixture.manifest_cases(complete_ids(include_public_visual=True))
        manifest = {
            "required_profiles": ["native_mpv", "browser_like"],
            "required_modes": sorted(matrix.REQUIRED_MODES),
            "required_automation_actions": [
                "pause",
                "resume",
                "seek_forward",
                "seek_backward",
                "audio_next",
                "subtitle_next",
                "lower_quality",
                "retry_from_current",
                "skip_active_segment",
                "up_next_cancel",
                "up_next_play_now",
                "stop",
            ],
            "required_recovery_scenarios": [
                "server_seek_restart",
                "session_restart",
                "session_invalidation_retry",
            ],
            "required_visual_review_cases": [
                fixture.TRAFFIC2_VOBSUB_VISUAL_CASE,
                fixture.KODI_HDR10PLUS_PROFILE_B_VISUAL_CASE,
                fixture.KODI_HYBRID_HDR10PLUS_DV_VISUAL_CASE,
            ],
            "release_candidate_evidence": {
                "manual_only": True,
                "workflow": "Playback Client Fixture Matrix",
                "artifact": "playback-client-fixture-matrix",
                "retention_days": 30,
            },
            "hardware_hdr_certification_artifacts": [
                {
                    "status": "passed",
                    "target_id": "win11-nvidia-rtx5090",
                    "hardware_api": "nvenc",
                    "suite": "torture",
                    "artifact_digest": "sha256:" + "2" * 64,
                    "features": ["hardware_hdr", "hdr_tone_mapping"],
                }
            ],
            "cases": cases,
        }
        results = passed_results_for_cases(cases)
        for result in results:
            case_name = result["case"]
            if case_name in {
                fixture.TRAFFIC2_VOBSUB_VISUAL_CASE,
                fixture.KODI_HDR10PLUS_PROFILE_B_VISUAL_CASE,
                fixture.KODI_HYBRID_HDR10PLUS_DV_VISUAL_CASE,
            }:
                result["visual_review"] = {
                    "status": "passed",
                    "type": case_name,
                    "nonblank_capture": f"/tmp/{case_name}.png",
                }

        errors = matrix.validate_manifest(manifest)
        gate = matrix.summarize_evidence_gate(manifest, results)
        ledger = matrix.summarize_phase_16_18_ledger(manifest, results, gate)

        self.assertEqual(errors, [])
        self.assertEqual(gate["status"], "passed")
        self.assertEqual(ledger["phase_16"]["status"], "complete")
        self.assertEqual(ledger["phase_17"]["status"], "complete")
        self.assertEqual(ledger["phase_18"]["status"], "complete")
        self.assertEqual(ledger["status"], "complete")

    def test_audio_switch_fixture_has_two_audio_streams_and_matrix_case(self) -> None:
        audio_fixture = fixture.FIXTURES["direct_play_audio_switch"]

        self.assertTrue(audio_fixture.alternate_audio)
        streams = fixture.audio_streams_for_fixture(audio_fixture)
        self.assertEqual([stream["index"] for stream in streams], [1, 2])
        self.assertEqual(streams[0]["language"], "eng")
        self.assertEqual(streams[1]["language"], "jpn")

        cases = fixture.manifest_cases(complete_ids())
        audio_case = next(
            case
            for case in cases
            if case["name"] == "direct-play-native-mpv-audio-track-switch"
        )
        self.assertEqual(audio_case["expect_mode"], "direct_play")
        self.assertEqual(audio_case["automation_actions"], "audio_next,stop")
        self.assertIn("audio_track_switch_requested", audio_case["expect_event"])

    def test_phase17_and_phase18_fixtures_carry_probe_facts(self) -> None:
        ass_fixture = fixture.FIXTURES["complex_ass_burn_in"]
        self.assertEqual(ass_fixture.subtitle.codec, "ass")
        self.assertEqual(ass_fixture.subtitle.extension, "ass")
        self.assertIn("color=c=black", ass_fixture.video_lavfi)

        pgs_fixture = fixture.FIXTURES["pgs_burn_in"]
        self.assertEqual(pgs_fixture.subtitle.codec, "pgs")
        self.assertEqual(pgs_fixture.subtitle.extension, "sup")
        self.assertEqual(pgs_fixture.subtitle.kind, "image")
        self.assertEqual(pgs_fixture.subtitle.input_format, "sup")
        self.assertEqual(pgs_fixture.subtitle.mux_codec, "copy")
        self.assertEqual(pgs_fixture.subtitle.pgs_rect, (400, 560, 480, 80))
        self.assertIn("color=c=black", pgs_fixture.video_lavfi)

        transparent_fixture = fixture.FIXTURES["pgs_transparent_overlay"]
        self.assertEqual(transparent_fixture.subtitle.codec, "pgs")
        self.assertEqual(transparent_fixture.subtitle.kind, "image")
        self.assertEqual(transparent_fixture.subtitle.input_format, "sup")
        self.assertEqual(
            transparent_fixture.subtitle.pgs_rects,
            ((320, 560, 160, 80), (800, 560, 160, 80)),
        )
        self.assertIn("color=c=gray", transparent_fixture.video_lavfi)

        long_timing_fixture = fixture.FIXTURES["pgs_transparent_overlay_long_timing"]
        self.assertEqual(long_timing_fixture.duration_seconds, 36)
        self.assertEqual(long_timing_fixture.subtitle.codec, "pgs")
        self.assertEqual(long_timing_fixture.subtitle.kind, "image")
        self.assertEqual(long_timing_fixture.subtitle.input_format, "sup")
        self.assertEqual(
            long_timing_fixture.subtitle.pgs_rects,
            ((320, 560, 160, 80), (800, 560, 160, 80)),
        )
        self.assertEqual(long_timing_fixture.subtitle.pgs_clear_ms, 34000)
        self.assertIn("color=c=gray", long_timing_fixture.video_lavfi)

        dvdsub_fixture = fixture.FIXTURES["dvdsub_transparent_overlay"]
        self.assertEqual(dvdsub_fixture.subtitle.codec, "dvd_subtitle")
        self.assertEqual(dvdsub_fixture.subtitle.kind, "image")
        self.assertEqual(dvdsub_fixture.subtitle.input_format, "sup")
        self.assertEqual(dvdsub_fixture.subtitle.mux_codec, "dvdsub")
        self.assertEqual(
            dvdsub_fixture.subtitle.pgs_rects,
            ((320, 560, 160, 80), (800, 560, 160, 80)),
        )
        self.assertIn("color=c=gray", dvdsub_fixture.video_lavfi)

        external_fixture = fixture.FIXTURES["external_pgs_sidecar_transparent_overlay"]
        self.assertIsNone(external_fixture.subtitle)
        self.assertEqual(external_fixture.external_subtitle.codec, "pgs")
        self.assertEqual(external_fixture.external_subtitle.extension, "sup")
        self.assertEqual(external_fixture.external_subtitle.kind, "image")
        self.assertEqual(external_fixture.external_subtitle.input_format, "sup")
        self.assertEqual(
            external_fixture.external_subtitle.pgs_rects,
            ((320, 560, 160, 80), (800, 560, 160, 80)),
        )
        self.assertIn("color=c=gray", external_fixture.video_lavfi)

        hdr_fixture = fixture.FIXTURES["hdr10_tonemap"]
        self.assertEqual(hdr_fixture.video_codec, "hevc")
        self.assertEqual(hdr_fixture.ffmpeg_video_encoder, "libx265")
        self.assertEqual(hdr_fixture.bit_depth, 10)
        self.assertTrue(hdr_fixture.hdr10)
        self.assertEqual(hdr_fixture.color_transfer, "smpte2084")

        with tempfile.TemporaryDirectory() as raw:
            probe_path = Path(raw) / "phase18-hdr10.mkv"
            probe_path.write_bytes(b"fixture")
            probe = fixture.normalized_probe(hdr_fixture, probe_path)
        self.assertEqual(probe["probe_version"], fixture.MEDIA_CAPABILITIES_PROBE_VERSION)

    def test_server_command_prefers_prebuilt_binary_without_cargo_run(self) -> None:
        command = fixture.server_command(Path("/tmp/elixir-server"))

        self.assertEqual(command, ["/tmp/elixir-server"])

    def test_generate_media_uses_explicit_duration_not_shortest_for_sparse_subtitles(self) -> None:
        commands: list[list[str]] = []
        original_run = fixture.run

        def fake_run(command: list[str], *, cwd=None, env=None) -> None:  # noqa: ANN001
            commands.append(command)
            Path(command[-1]).write_bytes(b"synthetic")

        try:
            fixture.run = fake_run
            with tempfile.TemporaryDirectory() as temp_dir:
                output = fixture.generate_media(
                    Path(temp_dir),
                    fixture.FIXTURES["dvdsub_transparent_overlay"],
                )
        finally:
            fixture.run = original_run

        self.assertTrue(output.name.endswith(".mkv"))
        self.assertEqual(len(commands), 1)
        self.assertNotIn("-shortest", commands[0])
        duration_index = commands[0].index("-t")
        self.assertEqual(commands[0][duration_index + 1], "12")
        codec_index = commands[0].index("-c:s")
        self.assertEqual(commands[0][codec_index + 1], "dvdsub")

    def test_external_sidecar_path_matches_media_stem_and_language(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = fixture.external_subtitle_path(
                Path(temp_dir),
                fixture.FIXTURES["external_pgs_sidecar_transparent_overlay"],
            )

        self.assertEqual(
            path.name,
            "Phase17.External.PGS.Sidecar.TransparentOverlay.2026.eng.sup",
        )

    def test_server_command_falls_back_to_cargo_run_when_binary_is_missing(self) -> None:
        command = fixture.server_command(None)

        self.assertEqual(command, ["cargo", "run", "--quiet", "--bin", "elixir-server"])

    def test_compact_server_poll_keeps_phase16_assertion_fields(self) -> None:
        compact = fixture.compact_server_poll(
            {
                "mode": "adaptive_transcode",
                "delivery": "hls_adaptive_fmp4",
                "server_seek_required": True,
                "active_rung": {"label": "720p"},
                "plan_summary": {
                    "selected_audio_track": 1,
                    "selected_subtitle_track": 2,
                    "video_action": "transcode",
                    "audio_action": "passthrough",
                    "subtitle_action": "convert_text_to_webvtt",
                    "hdr_action": "tone_map_to_sdr",
                    "video_transcode_reason": "hdr_tone_mapping_required",
                    "tone_map": {"output_primaries": "bt709"},
                    "adaptive": True,
                },
            }
        )

        self.assertEqual(compact["mode"], "adaptive_transcode")
        self.assertEqual(compact["delivery"], "hls_adaptive_fmp4")
        self.assertEqual(compact["selected_audio_track"], 1)
        self.assertEqual(compact["selected_subtitle_track"], 2)
        self.assertEqual(compact["video_action"], "transcode")
        self.assertEqual(compact["subtitle_action"], "convert_text_to_webvtt")
        self.assertEqual(compact["hdr_action"], "tone_map_to_sdr")
        self.assertEqual(compact["video_transcode_reason"], "hdr_tone_mapping_required")
        self.assertEqual(compact["tone_map"], {"output_primaries": "bt709"})
        self.assertEqual(compact["active_rung"]["label"], "720p")


if __name__ == "__main__":
    unittest.main()
