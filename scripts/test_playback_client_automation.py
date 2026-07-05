#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import struct
import tempfile
import unittest
import zlib
from pathlib import Path


SCRIPT = Path(__file__).with_name("playback_client_automation.py")
spec = importlib.util.spec_from_file_location("playback_client_automation", SCRIPT)
automation = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(automation)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(kind)
    crc = zlib.crc32(payload, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)


def write_rgb_png(path: Path, width: int, height: int, pixels: list[tuple[int, int, int]]) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        row = pixels[y * width : (y + 1) * width]
        for r, g, b in row:
            raw.extend([r, g, b])
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk("IHDR".encode(), struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + png_chunk("IDAT".encode(), zlib.compress(bytes(raw)))
        + png_chunk("IEND".encode(), b"")
    )


class PlaybackClientAutomationTests(unittest.TestCase):
    def test_expected_events_include_control_path_evidence(self) -> None:
        events = automation.expected_events_for_actions(
            "pause,resume,seek_forward,seek_backward,lower_quality,retry_from_current,"
            "wait:2,skip_active_segment,up_next_cancel,up_next_play_now,stop"
        )
        self.assertIn("paused", events)
        self.assertIn("resumed", events)
        self.assertEqual(events.count("seek_applied|seek_completed"), 3)
        self.assertIn("lower_quality_requested|lower_quality_unavailable", events)
        self.assertIn("retry_recovery_requested", events)
        self.assertIn("automation_wait", events)
        self.assertIn("automation_skip_active_segment", events)
        self.assertIn("segment_skip_requested", events)
        self.assertIn("automation_up_next_cancel", events)
        self.assertIn("up_next_cancelled", events)
        self.assertIn("automation_up_next_play_now", events)
        self.assertIn("up_next_play_now", events)
        self.assertIn("session_end_requested", events)
        self.assertIn("automation_finished", events)

    def test_nonblank_png_rejects_black_and_accepts_varied_frame(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            black = tmp / "black.png"
            varied = tmp / "varied.png"
            write_rgb_png(black, 2, 2, [(0, 0, 0)] * 4)
            write_rgb_png(
                varied,
                2,
                2,
                [(0, 0, 0), (80, 20, 20), (20, 120, 20), (220, 220, 220)],
            )

            black_ok, black_details = automation.nonblank_png(black)
            varied_ok, varied_details = automation.nonblank_png(varied)

            self.assertFalse(black_ok, black_details)
            self.assertTrue(varied_ok, varied_details)
            self.assertGreater(varied_details["max_luma"], varied_details["min_luma"])

    def test_bright_region_png_accepts_visible_overlay_region(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            frame = tmp / "subtitle.png"
            pixels: list[tuple[int, int, int]] = []
            for y in range(4):
                for _x in range(4):
                    pixels.append((255, 255, 255) if y >= 2 else (0, 0, 0))
            write_rgb_png(frame, 4, 4, pixels)
            region = automation.parse_bright_region_spec("subtitle:0:0.5:1:0.5:120:200")

            ok, details = automation.bright_region_png(frame, region)

            self.assertTrue(ok, details)
            self.assertGreaterEqual(details["mean_luma"], 120)
            self.assertGreaterEqual(details["max_luma"], 200)

    def test_bright_region_png_supports_upper_bounds_for_transparent_gaps(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            frame = tmp / "gap.png"
            write_rgb_png(frame, 4, 4, [(128, 128, 128)] * 16)
            region = automation.parse_bright_region_spec("gap:0:0:1:1:80:100:190:220")

            ok, details = automation.bright_region_png(frame, region)

            self.assertTrue(ok, details)
            self.assertGreaterEqual(details["mean_luma"], 80)
            self.assertLessEqual(details["mean_luma"], 190)
            self.assertGreaterEqual(details["max_luma"], 100)
            self.assertLessEqual(details["max_luma"], 220)

    def test_parse_bright_region_rejects_out_of_bounds_specs(self) -> None:
        with self.assertRaises(ValueError):
            automation.parse_bright_region_spec("subtitle:0.8:0.8:0.4:0.4:10")

    def test_capture_refresh_retries_partial_png_until_valid(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            capture = tmp / "frame.png"
            capture.write_bytes(b"partial")
            capture_paths = {capture}
            checked: dict[Path, tuple[bool, dict]] = {}

            first = automation.refresh_capture_checks(capture_paths, tmp, checked)
            self.assertIsNone(first)
            self.assertFalse(checked[capture][0], checked[capture])

            write_rgb_png(
                capture,
                2,
                2,
                [(0, 0, 0), (80, 20, 20), (20, 120, 20), (220, 220, 220)],
            )

            second = automation.refresh_capture_checks(capture_paths, tmp, checked)
            self.assertIsNotNone(second)
            self.assertTrue(checked[capture][0], checked[capture])
            self.assertEqual(second["path"], str(capture))

    def test_server_session_expectations_require_exact_mode_and_delivery(self) -> None:
        matching = {"mode": "video_transcode", "delivery": "hls_fmp4"}
        mismatched = {
            "mode": "direct_stream",
            "delivery": "hls_mpegts",
            "plan_summary": {
                "selected_subtitle_track": None,
            },
        }

        self.assertEqual(
            automation.server_session_expectation_errors(
                matching,
                ["video_transcode"],
                ["hls_fmp4"],
                [],
            ),
            [],
        )
        self.assertEqual(
            automation.server_session_expectation_errors(
                mismatched,
                ["video_transcode"],
                ["hls_fmp4"],
                ["selected_subtitle_track=2"],
            ),
            [
                "server_mode:direct_stream",
                "server_delivery:hls_mpegts",
                "server_field:selected_subtitle_track:None!=2",
            ],
        )

    def test_server_session_urls_are_scoped_to_requested_session(self) -> None:
        self.assertEqual(
            automation.server_session_url("http://server.test/", "session-1"),
            "http://server.test/api/v1/sessions/session-1/poll",
        )
        self.assertEqual(
            automation.server_session_end_url("http://server.test/", "session-1"),
            "http://server.test/api/v1/sessions/session-1/end",
        )

    def test_server_field_expectations_compare_typed_compact_session_values(self) -> None:
        compact = {
            "selected_subtitle_track": 2,
            "adaptive": True,
            "active_rung": {"label": "720p 4000k", "bandwidth_bps": 4000000},
        }

        self.assertIsNone(
            automation.server_field_expectation_error(compact, "selected_subtitle_track=2")
        )
        self.assertIsNone(automation.server_field_expectation_error(compact, "adaptive=true"))
        self.assertIsNone(
            automation.server_field_expectation_error(compact, "active_rung.bandwidth_bps=4000000")
        )
        self.assertIsNone(
            automation.server_field_expectation_error(compact, "active_rung.label=720p 4000k")
        )
        self.assertEqual(
            automation.server_field_expectation_error(compact, "adaptive=false"),
            "server_field:adaptive:True!=False",
        )

    def test_timing_evidence_requires_samples_span_and_monotonic_progress(self) -> None:
        samples = [
            {"event": "position", "session_id": "s1", "position_seconds": 1.0, "paused": False},
            {"event": "player_observation", "session_id": "s1", "position_seconds": 3.0, "paused": False},
            {"event": "position", "session_id": "s1", "position_seconds": 5.0, "paused": False},
            {"event": "position", "session_id": "s1", "position_seconds": 7.2, "paused": False},
        ]

        evidence = automation.summarize_timing_evidence(
            samples,
            min_sample_count=4,
            min_span_seconds=6.0,
            max_regression_seconds=0.75,
        )

        self.assertEqual(evidence["status"], "passed")
        self.assertEqual(evidence["sample_count"], 4)
        self.assertGreaterEqual(evidence["position_span_seconds"], 6.0)
        self.assertEqual(evidence["regressions"], [])

        regressed = samples + [
            {"event": "position", "session_id": "s1", "position_seconds": 4.0, "paused": False}
        ]
        evidence = automation.summarize_timing_evidence(
            regressed,
            min_sample_count=4,
            min_span_seconds=6.0,
            max_regression_seconds=0.75,
        )

        self.assertEqual(evidence["status"], "failed")
        self.assertTrue(evidence["regressions"], evidence)

    def test_position_sample_from_event_uses_only_real_position_observations(self) -> None:
        self.assertEqual(
            automation.position_sample_from_event(
                {
                    "event": "position",
                    "session_id": "s1",
                    "position_seconds": 2.5,
                    "paused": False,
                    "timestamp": "2026-07-01T00:00:00.000Z",
                }
            ),
            {
                "event": "position",
                "session_id": "s1",
                "position_seconds": 2.5,
                "paused": False,
                "timestamp": "2026-07-01T00:00:00.000Z",
            },
        )
        self.assertIsNone(
            automation.position_sample_from_event({"event": "automation_action", "position_seconds": 2.5})
        )

    def test_player_observation_can_satisfy_advanced_playback_evidence(self) -> None:
        event = {
            "event": "player_observation",
            "session_id": "restart-session",
            "position_seconds": 3.5,
            "paused": False,
        }

        self.assertIs(
            automation.advanced_playback_event(event, min_position_seconds=2.0),
            event,
        )
        self.assertIsNone(automation.advanced_playback_event(event, min_position_seconds=4.0))

    def test_compact_server_session_preserves_phase16_evidence_fields(self) -> None:
        compact = automation.compact_server_session(
            {
                "id": "session-1",
                "state": "playing",
                "mode": "subtitle_transcode",
                "delivery": "hls_fmp4",
                "server_seek_required": True,
                "decision_reason": "subtitle_sidecar",
                "decision_reasons": ["subtitle_text_extracted"],
                "logical_position_seconds": 4.5,
                "duration_seconds": 20.0,
                "plan_summary": {
                    "selected_audio_track": "2",
                    "selected_subtitle_track": "4",
                    "hdr_action": "tone_map_to_sdr",
                    "video_transcode_reason": "hdr_tone_mapping_required",
                    "tone_map": {"output_primaries": "bt709"},
                    "quality_label": "Original",
                },
                "active_rung": {"height": 1080, "bitrate_bps": 8000000},
                "job_snapshot": {"state": "running", "error_kind": None},
                "token": "must-not-be-carried",
            }
        )

        self.assertEqual(compact["id"], "session-1")
        self.assertEqual(compact["mode"], "subtitle_transcode")
        self.assertEqual(compact["delivery"], "hls_fmp4")
        self.assertEqual(compact["selected_audio_track"], "2")
        self.assertEqual(compact["selected_subtitle_track"], "4")
        self.assertEqual(compact["hdr_action"], "tone_map_to_sdr")
        self.assertEqual(compact["video_transcode_reason"], "hdr_tone_mapping_required")
        self.assertEqual(compact["tone_map"], {"output_primaries": "bt709"})
        self.assertEqual(compact["active_rung"], {"height": 1080, "bitrate_bps": 8000000})
        self.assertEqual(compact["job_state"], "running")
        self.assertNotIn("token", compact)


if __name__ == "__main__":
    unittest.main()
