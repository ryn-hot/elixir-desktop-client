#!/usr/bin/env python3
"""Create and run a real local Phase 16 client playback matrix.

The runner creates legal synthetic media with ffmpeg, starts a real Elixir
server against a temporary SQLite database, seeds production library/probe
tables, preflights `/api/v1/play`, then delegates to
playback_client_automation_matrix.py. It does not fake the client, player,
server route, playback planner, or FFmpeg job path.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any


HOST = "127.0.0.1"
DEFAULT_PORT = 45116
MEDIA_CAPABILITIES_PROBE_VERSION = 2
ROOT = Path(__file__).resolve().parents[2]
CLIENT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PUBLIC_CORPUS_ROOT = ROOT / "data" / "playback-corpus" / "public"
TRAFFIC2_VOBSUB_VISUAL_CASE = "external-vobsub-sidecar-traffic2-visual"
KODI_HDR10PLUS_PROFILE_B_VISUAL_CASE = "hdr10plus-profile-b-browser-like-visual-review"
KODI_HYBRID_HDR10PLUS_DV_VISUAL_CASE = "hybrid-hdr10plus-dolby-vision-browser-like-visual-review"


@dataclass(frozen=True)
class SubtitleFixture:
    codec: str = "srt"
    extension: str = "srt"
    kind: str = "text"
    language: str = "eng"
    title: str = "Phase 16 English"
    is_default: bool = True
    is_forced: bool = False
    input_format: str | None = None
    mux_codec: str | None = None
    pgs_rect: tuple[int, int, int, int] | None = None
    pgs_rects: tuple[tuple[int, int, int, int], ...] | None = None
    pgs_clear_ms: int = 9000
    vobsub_source_rel: str | None = None
    vobsub_first_timestamp_ms: int = 1000
    vobsub_timestamp_step_ms: int = 750


@dataclass(frozen=True)
class MediaFixture:
    name: str
    file_name: str
    container: str
    video_codec: str
    audio_codec: str
    width: int
    height: int
    bitrate_bps: int
    duration_seconds: int = 12
    ffmpeg_video_encoder: str = "libx264"
    ffmpeg_video_pixel_format: str = "yuv420p"
    ffmpeg_video_extra_args: tuple[str, ...] = ()
    ffmpeg_audio_encoder: str = "aac"
    video_lavfi: str = ""
    video_profile: str = "High"
    bit_depth: int = 8
    color_primaries: str | None = None
    color_transfer: str | None = None
    color_matrix: str | None = None
    hdr10: bool = False
    hdr10_plus: bool = False
    dolby_vision: bool = False
    mastering_metadata: bool = False
    content_light_metadata: bool = False
    dolby_vision_profile: int | None = None
    dolby_vision_has_hdr10_fallback: bool = False
    subtitle: SubtitleFixture | None = None
    external_subtitle: SubtitleFixture | None = None
    episode: bool = False
    episode_count: int = 1
    alternate_audio: bool = False
    midm_segment_type: str = ""
    midm_segment_start_seconds: float = 0.0
    midm_segment_end_seconds: float = 8.0
    source_media_rel: str | None = None


FIXTURES: dict[str, MediaFixture] = {
    "direct_play": MediaFixture(
        name="direct_play",
        file_name="Phase16.Direct.Play.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
    ),
    "direct_play_episode": MediaFixture(
        name="direct_play_episode",
        file_name="Phase16.Series.S01E01.Direct.Play.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        episode=True,
    ),
    "midm_skip_prompt": MediaFixture(
        name="midm_skip_prompt",
        file_name="MIDM.Skip.Prompt.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        midm_segment_type="intro",
    ),
    "midm_auto_skip": MediaFixture(
        name="midm_auto_skip",
        file_name="MIDM.Auto.Skip.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        midm_segment_type="credits",
    ),
    "midm_up_next": MediaFixture(
        name="midm_up_next",
        file_name="MIDM.Up.Next.S01E01.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        episode=True,
        episode_count=2,
    ),
    "direct_play_audio_switch": MediaFixture(
        name="direct_play_audio_switch",
        file_name="Phase16.Direct.Play.Audio.Switch.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_200_000,
        alternate_audio=True,
    ),
    "direct_stream": MediaFixture(
        name="direct_stream",
        file_name="Phase16.Direct.Stream.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
    ),
    "audio_transcode": MediaFixture(
        name="audio_transcode",
        file_name="Phase16.Audio.Transcode.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="ac3",
        width=1280,
        height=720,
        bitrate_bps=3_000_000,
        ffmpeg_audio_encoder="ac3",
    ),
    "subtitle_transcode": MediaFixture(
        name="subtitle_transcode",
        file_name="Phase16.Subtitle.Transcode.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        subtitle=SubtitleFixture(),
    ),
    "video_transcode": MediaFixture(
        name="video_transcode",
        file_name="Phase16.Video.Transcode.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=8_000_000,
    ),
    "adaptive_transcode": MediaFixture(
        name="adaptive_transcode",
        file_name="Phase16.Adaptive.Transcode.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=8_000_000,
    ),
    "complex_ass_burn_in": MediaFixture(
        name="complex_ass_burn_in",
        file_name="Phase17.Complex.Ass.Burnin.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        video_lavfi="color=c=black:size={width}x{height}:rate=24:duration={duration}",
        subtitle=SubtitleFixture(
            codec="ass",
            extension="ass",
            language="eng",
            title="Phase 17 Complex ASS",
        ),
    ),
    "pgs_burn_in": MediaFixture(
        name="pgs_burn_in",
        file_name="Phase17.Image.PGS.Burnin.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        video_lavfi="color=c=black:size={width}x{height}:rate=24:duration={duration}",
        subtitle=SubtitleFixture(
            codec="pgs",
            extension="sup",
            kind="image",
            language="eng",
            title="Phase 17 PGS Image",
            input_format="sup",
            mux_codec="copy",
            pgs_rect=(400, 560, 480, 80),
        ),
    ),
    "pgs_transparent_overlay": MediaFixture(
        name="pgs_transparent_overlay",
        file_name="Phase17.Image.PGS.TransparentOverlay.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        video_lavfi="color=c=gray:size={width}x{height}:rate=24:duration={duration}",
        subtitle=SubtitleFixture(
            codec="pgs",
            extension="sup",
            kind="image",
            language="eng",
            title="Phase 17 PGS Transparent Overlay",
            input_format="sup",
            mux_codec="copy",
            pgs_rects=((320, 560, 160, 80), (800, 560, 160, 80)),
        ),
    ),
    "pgs_transparent_overlay_long_timing": MediaFixture(
        name="pgs_transparent_overlay_long_timing",
        file_name="Phase17.Image.PGS.TransparentOverlay.LongTiming.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        duration_seconds=36,
        video_lavfi="color=c=gray:size={width}x{height}:rate=24:duration={duration}",
        subtitle=SubtitleFixture(
            codec="pgs",
            extension="sup",
            kind="image",
            language="eng",
            title="Phase 17 PGS Long Timing Overlay",
            input_format="sup",
            mux_codec="copy",
            pgs_rects=((320, 560, 160, 80), (800, 560, 160, 80)),
            pgs_clear_ms=34000,
        ),
    ),
    "dvdsub_transparent_overlay": MediaFixture(
        name="dvdsub_transparent_overlay",
        file_name="Phase17.Image.DVDSub.TransparentOverlay.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        video_lavfi="color=c=gray:size={width}x{height}:rate=24:duration={duration}",
        subtitle=SubtitleFixture(
            codec="dvd_subtitle",
            extension="sup",
            kind="image",
            language="eng",
            title="Phase 17 DVD Subtitle Transparent Overlay",
            input_format="sup",
            mux_codec="dvdsub",
            pgs_rects=((320, 560, 160, 80), (800, 560, 160, 80)),
        ),
    ),
    "external_pgs_sidecar_transparent_overlay": MediaFixture(
        name="external_pgs_sidecar_transparent_overlay",
        file_name="Phase17.External.PGS.Sidecar.TransparentOverlay.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=1280,
        height=720,
        bitrate_bps=2_000_000,
        video_lavfi="color=c=gray:size={width}x{height}:rate=24:duration={duration}",
        external_subtitle=SubtitleFixture(
            codec="pgs",
            extension="sup",
            kind="image",
            language="eng",
            title="Phase 17 External PGS Sidecar",
            input_format="sup",
            mux_codec="copy",
            pgs_rects=((320, 560, 160, 80), (800, 560, 160, 80)),
        ),
    ),
    "hdr10_tonemap": MediaFixture(
        name="hdr10_tonemap",
        file_name="Phase18.HDR10.To.SDR.2026.mkv",
        container="mkv",
        video_codec="hevc",
        audio_codec="aac",
        width=640,
        height=360,
        bitrate_bps=2_000_000,
        ffmpeg_video_encoder="libx265",
        ffmpeg_video_pixel_format="yuv420p10le",
        ffmpeg_video_extra_args=(
            "-color_primaries",
            "bt2020",
            "-color_trc",
            "smpte2084",
            "-colorspace",
            "bt2020nc",
            "-x265-params",
            "hdr-opt=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:"
            "master-display=G(13250,34500)B(7500,3000)R(34000,16000)"
            "WP(15635,16450)L(10000000,1):max-cll=1000,400",
        ),
        video_profile="Main 10",
        bit_depth=10,
        color_primaries="bt2020",
        color_transfer="smpte2084",
        color_matrix="bt2020nc",
        hdr10=True,
        mastering_metadata=True,
        content_light_metadata=True,
    ),
}


PUBLIC_VISUAL_FIXTURES: dict[str, MediaFixture] = {
    "traffic2_vobsub_visual": MediaFixture(
        name="traffic2_vobsub_visual",
        file_name="Phase17.External.VobSub.Traffic2.Normalized.2026.mkv",
        container="mkv",
        video_codec="h264",
        audio_codec="aac",
        width=720,
        height=480,
        bitrate_bps=2_000_000,
        video_lavfi="color=c=gray:size={width}x{height}:rate=24:duration={duration}",
        external_subtitle=SubtitleFixture(
            codec="idx",
            extension="idx",
            kind="image",
            language="eng",
            title="FFmpeg Traffic2 VobSub normalized visual derivative",
            is_default=True,
            is_forced=False,
            vobsub_source_rel="ffmpeg/traffic/Traffic2",
        ),
    ),
    "kodi_hdr10plus_profile_b_visual": MediaFixture(
        name="kodi_hdr10plus_profile_b_visual",
        file_name="Kodi.HDR10Plus.ProfileB.EAC3JOC.mkv",
        container="mkv",
        video_codec="hevc",
        audio_codec="eac3",
        width=3840,
        height=2160,
        bitrate_bps=15_563_018,
        duration_seconds=50,
        ffmpeg_video_pixel_format="yuv420p10le",
        video_profile="Main 10",
        bit_depth=10,
        color_primaries="bt2020",
        color_transfer="smpte2084",
        color_matrix="bt2020nc",
        hdr10=True,
        hdr10_plus=True,
        mastering_metadata=True,
        content_light_metadata=True,
        source_media_rel="kodi/hdr10plus/HDR10Plus_PB_EAC3JOC.mkv",
    ),
    "kodi_hybrid_hdr10plus_dv_visual": MediaFixture(
        name="kodi_hybrid_hdr10plus_dv_visual",
        file_name="Kodi.Hybrid.HDR10Plus.DV.Sample.mkv",
        container="mkv",
        video_codec="hevc",
        audio_codec="truehd",
        width=3840,
        height=2160,
        bitrate_bps=71_279_701,
        duration_seconds=60,
        ffmpeg_video_pixel_format="yuv420p10le",
        video_profile="Main 10",
        bit_depth=10,
        color_primaries="bt2020",
        color_transfer="smpte2084",
        color_matrix="bt2020nc",
        hdr10=True,
        hdr10_plus=True,
        dolby_vision=True,
        mastering_metadata=True,
        content_light_metadata=True,
        dolby_vision_profile=7,
        dolby_vision_has_hdr10_fallback=True,
        source_media_rel="kodi/hdr10plus/Hybrid HDR10Plus DV Sample.mkv",
    ),
}


NATIVE_EXPECTED_CAPS: dict[str, Any] = {
    "profile_id": "native_mpv_desktop",
    "profile_version": 5,
    "client_kind": "native_mpv",
    "direct_play_preferred": True,
    "quality_mode": "original",
    "abr_support_type": "mpv",
    "supported_containers": ["mkv", "mp4", "matroska"],
    "supported_video_codecs": ["h264", "hevc", "vp9", "av1"],
    "supported_audio_codecs": ["aac", "ac3", "eac3", "opus", "mp3", "flac"],
    "supported_subtitle_codecs": ["srt", "webvtt", "ass", "ssa", "mov_text"],
    "supported_hls_segment_types": ["fmp4", "mpegts"],
    "subtitle_rendering": "native",
    "ass_complexity_support": "native",
    "image_subtitle_support": "native_or_burn_in",
    "forced_subtitle_policy": "matching_audio",
    "default_subtitle_policy": "media_default",
    "supports_auth_headers_for_media": True,
    "supports_server_side_hls_seek": True,
    "supports_native_text_subtitles": True,
    "strict_h264_profile_limits": False,
}


BROWSER_CAPS: dict[str, Any] = {
    "profile_id": "web_chromium",
    "profile_version": 5,
    "client_kind": "web",
    "direct_play_preferred": False,
    "quality_mode": "fixed",
    "abr_support_type": "hls.js",
    "supported_containers": ["mp4"],
    "supported_video_codecs": ["h264"],
    "supported_audio_codecs": ["aac"],
    "supported_subtitle_codecs": ["webvtt"],
    "supported_hls_segment_types": ["fmp4"],
    "subtitle_rendering": "hls_webvtt",
    "ass_complexity_support": "simple_webvtt",
    "image_subtitle_support": "burn_in",
    "forced_subtitle_policy": "matching_audio",
    "default_subtitle_policy": "media_default",
    "supports_auth_headers_for_media": True,
    "supports_server_side_hls_seek": True,
    "supports_native_text_subtitles": False,
    "strict_h264_profile_limits": True,
    "supports_hdr": False,
    "supports_hdr10_plus": False,
    "supports_dolby_vision": False,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-bin", required=True, help="Path to elixir-client executable")
    parser.add_argument(
        "--server-bin",
        default="",
        help="Path to elixir-server executable; defaults to target/debug/elixir-server when present",
    )
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--artifact-dir", default="", help="Persistent artifact root")
    parser.add_argument("--timeout-seconds", type=float, default=120.0)
    parser.add_argument("--server-timeout-seconds", type=float, default=180.0)
    parser.add_argument("--prepare-only", action="store_true", help="Generate media, seed server, write manifest, then exit")
    parser.add_argument("--keep-temp", action="store_true", help="Keep temporary media/database directory")
    parser.add_argument("--no-generate-media", action="store_true", help="Reuse existing generated fixture files")
    parser.add_argument(
        "--include-public-visual-fixtures",
        action="store_true",
        help="Include local-cache-only Traffic2 VobSub and Kodi HDR10+/DV visual review cases",
    )
    parser.add_argument(
        "--release-workflow",
        default="",
        help="Opt-in workflow name that produced this release-candidate evidence archive",
    )
    parser.add_argument(
        "--release-artifact",
        default="",
        help="Artifact name for this release-candidate evidence archive",
    )
    parser.add_argument(
        "--release-retention-days",
        type=int,
        default=0,
        help="Retention days for the release-candidate evidence archive",
    )
    parser.add_argument(
        "--hardware-certification-json",
        action="append",
        default=[],
        help="Passed playback hardware certification.json to attach as Phase 18 evidence",
    )
    return parser.parse_args()


def log(message: str) -> None:
    print(f"[phase16-client-fixture] {message}", flush=True)


def run(command: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    log("running " + " ".join(command))
    subprocess.run(command, cwd=cwd, env=env, check=True)


def public_corpus_root() -> Path:
    raw = os.environ.get("ELIXIR_PLAYBACK_PUBLIC_CORPUS_ROOT")
    return Path(raw).expanduser().resolve() if raw else DEFAULT_PUBLIC_CORPUS_ROOT


def public_corpus_path(relative: str) -> Path:
    return public_corpus_root() / relative


def fixtures_for_run(include_public_visual: bool) -> dict[str, MediaFixture]:
    fixtures = dict(FIXTURES)
    if include_public_visual:
        fixtures.update(PUBLIC_VISUAL_FIXTURES)
    return fixtures


def materialize_source_file(source: Path, destination: Path) -> None:
    if not source.exists():
        raise FileNotFoundError(f"public fixture source missing: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        return
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def release_candidate_evidence_from_args(args: argparse.Namespace) -> dict[str, Any] | None:
    workflow = str(args.release_workflow or "").strip()
    artifact = str(args.release_artifact or "").strip()
    retention_days = int(args.release_retention_days or 0)
    if not any([workflow, artifact, retention_days]):
        return None
    if not workflow or not artifact or retention_days <= 0:
        raise ValueError(
            "release evidence requires --release-workflow, --release-artifact, "
            "and --release-retention-days > 0"
        )
    return {
        "manual_only": True,
        "workflow": workflow,
        "artifact": artifact,
        "retention_days": retention_days,
    }


def hardware_certification_evidence(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"hardware certification must be a JSON object: {path}")
    if data.get("status") != "passed":
        raise ValueError(f"hardware certification is not passed: {path}")
    target_id = str(data.get("target_id") or "").strip()
    hardware_api = str(data.get("hardware_api") or "").strip()
    suite = str(data.get("suite") or "").strip()
    artifact_digest = str(data.get("artifact_digest") or "").strip()
    if not target_id:
        raise ValueError(f"hardware certification missing target_id: {path}")
    if not hardware_api:
        raise ValueError(f"hardware certification missing hardware_api: {path}")
    if suite not in {"robust", "torture"}:
        raise ValueError(f"hardware certification suite must be robust or torture: {path}")
    if not artifact_digest.startswith("sha256:") or len(artifact_digest) <= len("sha256:"):
        raise ValueError(f"hardware certification missing sha256 artifact_digest: {path}")

    features = set(data.get("features") or [])
    cases = data.get("cases") if isinstance(data.get("cases"), dict) else {}
    reports = cases.get("case_reports") if isinstance(cases.get("case_reports"), list) else []
    for report in reports:
        if not isinstance(report, dict) or report.get("status") != "passed":
            continue
        report_features = {str(feature) for feature in report.get("features") or []}
        if "type:hdr10" in report_features or "type:dolby-vision" in report_features:
            features.add("hardware_hdr")
            if report.get("hardware_used") is True:
                features.add("hdr_tone_mapping")
    if not {"hardware_hdr", "hdr_tone_mapping"}.intersection(features):
        raise ValueError(f"hardware certification lacks HDR hardware feature evidence: {path}")

    evidence: dict[str, Any] = {
        "status": "passed",
        "target_id": target_id,
        "hardware_api": hardware_api,
        "suite": suite,
        "artifact_digest": artifact_digest,
        "features": sorted(features),
    }
    for key in ("run_id", "commit_sha", "started_at", "finished_at"):
        value = data.get(key)
        if value:
            evidence[key] = value
    return evidence


def hardware_certification_evidence_from_paths(paths: list[str]) -> list[dict[str, Any]]:
    evidence: list[dict[str, Any]] = []
    for raw in paths:
        path = Path(raw).expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(f"hardware certification JSON not found: {path}")
        evidence.append(hardware_certification_evidence(path))
    return evidence


def format_vobsub_timestamp(ms: int) -> str:
    seconds, millis = divmod(ms, 1000)
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}:{millis:03d}"


def write_vobsub_sidecar(path: Path, fixture: SubtitleFixture, video_width: int, video_height: int) -> None:
    if not fixture.vobsub_source_rel:
        raise ValueError("VobSub sidecar fixture requires vobsub_source_rel")
    source_stem = public_corpus_path(fixture.vobsub_source_rel)
    source_idx = source_stem.with_suffix(".idx")
    source_sub = source_stem.with_suffix(".sub")
    if not source_idx.exists() or not source_sub.exists():
        raise FileNotFoundError(f"VobSub fixture requires {source_idx} and {source_sub}")

    text = source_idx.read_text(encoding="latin-1")
    text = re.sub(
        r"^size:\s*\d+x\d+",
        f"size: {video_width}x{video_height}",
        text,
        flags=re.MULTILINE,
    )
    counter = 0

    def replace_timestamp(match: re.Match[str]) -> str:
        nonlocal counter
        timestamp_ms = fixture.vobsub_first_timestamp_ms + counter * fixture.vobsub_timestamp_step_ms
        counter += 1
        return f"timestamp: {format_vobsub_timestamp(timestamp_ms)}, filepos: {match.group(1)}"

    text = re.sub(
        r"timestamp:\s*\d\d:\d\d:\d\d:\d\d\d,\s*filepos:\s*([0-9A-Fa-f]+)",
        replace_timestamp,
        text,
    )
    path.write_text(text, encoding="latin-1")
    materialize_source_file(source_sub, path.with_suffix(".sub"))


def http_request(
    base_url: str,
    method: str,
    path: str,
    *,
    headers: dict[str, str] | None = None,
    body: dict[str, Any] | None = None,
    timeout: float = 15.0,
) -> tuple[int, Any, dict[str, str]]:
    url = path if path.startswith("http") else f"{base_url.rstrip('/')}{path}"
    request_headers = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        request_headers["content-type"] = "application/json"
    request = urllib.request.Request(url, method=method, headers=request_headers, data=data)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            text = raw.decode("utf-8", errors="replace")
            try:
                parsed: Any = json.loads(text) if text else None
            except json.JSONDecodeError:
                parsed = text
            return response.getcode(), parsed, dict(response.headers)
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        text = raw.decode("utf-8", errors="replace")
        with contextlib.suppress(json.JSONDecodeError):
            return exc.code, json.loads(text), dict(exc.headers)
        return exc.code, text, dict(exc.headers)


def wait_for_health(base_url: str, process: subprocess.Popen[str], timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"server exited early with {process.returncode}")
        try:
            status, _body, _headers = http_request(base_url, "GET", "/health", timeout=2.0)
            if status == 200:
                return
        except Exception:
            pass
        time.sleep(0.25)
    raise RuntimeError("server did not become healthy")


def default_server_binary() -> Path | None:
    candidate = ROOT / "target" / "debug" / "elixir-server"
    return candidate if candidate.exists() else None


def server_command(server_bin: Path | None) -> list[str]:
    if server_bin is not None:
        return [str(server_bin)]
    return ["cargo", "run", "--quiet", "--bin", "elixir-server"]


def start_server(
    base_url: str,
    db_path: Path,
    library_root: Path,
    port: int,
    timeout: float,
    server_bin: Path | None,
) -> subprocess.Popen[str]:
    env = os.environ.copy()
    env.update(
        {
            "ELIXIR_ENV": "development",
            "ELIXIR__SERVER__HOST": HOST,
            "ELIXIR__SERVER__PORT": str(port),
            "ELIXIR__DATABASE__URL": f"sqlite://{db_path}",
            "ELIXIR__LIBRARY__LOCAL_ROOT": str(library_root),
            "ELIXIR__NETWORK__MDNS_ENABLED": "false",
            "ELIXIR__NETWORK__WAN_ENABLED": "false",
            "ELIXIR__PLAYBACK__ALLOW_ADAPTIVE_TRANSCODE": "true",
            "ELIXIR__PLAYBACK__ADAPTIVE_QUALITY_ENABLED": "true",
            "RUST_LOG": "info",
        }
    )
    command = server_command(server_bin)
    log("starting server with " + " ".join(command))
    process = subprocess.Popen(
        command,
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    def drain() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            print(f"[phase16-server] {line.rstrip()}", flush=True)

    threading.Thread(target=drain, daemon=True).start()
    wait_for_health(base_url, process, timeout)
    return process


def stop_server(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.send_signal(signal.SIGINT)
    try:
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=8)


def pgs_segment(segment_type: int, pts_ms: int, payload: bytes) -> bytes:
    pts = int(pts_ms * 90).to_bytes(4, "big")
    return b"PG" + pts + pts + bytes([segment_type]) + len(payload).to_bytes(2, "big") + payload


def pgs_palette_segment() -> bytes:
    return bytes(
        [
            0,  # palette id
            0,  # palette version
            0,
            16,
            128,
            128,
            0,  # transparent black
            1,
            235,
            128,
            128,
            255,  # opaque white
        ]
    )


def pgs_window_segment(rects: tuple[tuple[int, int, int, int], ...]) -> bytes:
    payload = bytearray([len(rects)])
    for window_id, rect in enumerate(rects):
        x, y, width, height = rect
        payload.extend(
            bytes([window_id])
            + x.to_bytes(2, "big")
            + y.to_bytes(2, "big")
            + width.to_bytes(2, "big")
            + height.to_bytes(2, "big")
        )
    return bytes(payload)


def pgs_object_segment(object_id: int, rect: tuple[int, int, int, int]) -> bytes:
    _x, _y, width, height = rect
    rle = bytearray()
    for _row in range(height):
        rle.extend(b"\x01" * width)
        rle.extend(b"\x00\x00")
    object_data_length = len(rle) + 4
    return (
        object_id.to_bytes(2, "big")
        + bytes([0, 0xC0])
        + object_data_length.to_bytes(3, "big")
        + width.to_bytes(2, "big")
        + height.to_bytes(2, "big")
        + bytes(rle)
    )


def pgs_presentation_segment(
    video_width: int,
    video_height: int,
    rects: tuple[tuple[int, int, int, int], ...],
    composition_number: int,
) -> bytes:
    payload = (
        video_width.to_bytes(2, "big")
        + video_height.to_bytes(2, "big")
        + bytes([0x10, composition_number >> 8, composition_number & 0xFF])
    )
    if not rects:
        return payload + bytes([0, 0, 0, 0])
    result = bytearray(payload + bytes([0x80, 0, 0, len(rects)]))
    for index, rect in enumerate(rects, start=1):
        x, y, _width, _height = rect
        window_id = index - 1
        result.extend(index.to_bytes(2, "big") + bytes([window_id, 0]) + x.to_bytes(2, "big") + y.to_bytes(2, "big"))
    return bytes(result)


def write_pgs_subtitle(
    path: Path,
    video_width: int,
    video_height: int,
    rect: tuple[int, int, int, int] | None,
    rects: tuple[tuple[int, int, int, int], ...] | None = None,
    clear_ms: int = 9000,
) -> None:
    if rects is None:
        rects = (rect,) if rect is not None else None
    if rects is None:
        rect_width = max(64, video_width * 3 // 8)
        rect_height = max(32, video_height // 9)
        rects = (((video_width - rect_width) // 2, video_height * 7 // 9, rect_width, rect_height),)
    for rect_item in rects:
        x, y, width, height = rect_item
        if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > video_width or y + height > video_height:
            raise ValueError(f"PGS rectangle {rect_item} does not fit {video_width}x{video_height}")

    display_ms = 1000
    segments = [
        pgs_segment(0x16, display_ms, pgs_presentation_segment(video_width, video_height, rects, 1)),
        pgs_segment(0x17, display_ms, pgs_window_segment(rects)),
        pgs_segment(0x14, display_ms, pgs_palette_segment()),
        *[
            pgs_segment(0x15, display_ms, pgs_object_segment(index, rect_item))
            for index, rect_item in enumerate(rects, start=1)
        ],
        pgs_segment(0x80, display_ms, b""),
        pgs_segment(0x16, clear_ms, pgs_presentation_segment(video_width, video_height, (), 2)),
        pgs_segment(0x80, clear_ms, b""),
    ]
    path.write_bytes(b"".join(segments))


def write_subtitle(
    path: Path,
    fixture: SubtitleFixture,
    *,
    video_width: int = 1280,
    video_height: int = 720,
) -> None:
    if fixture.vobsub_source_rel:
        write_vobsub_sidecar(path, fixture, video_width, video_height)
        return
    if fixture.input_format == "sup" or fixture.codec == "pgs":
        write_pgs_subtitle(
            path,
            video_width,
            video_height,
            fixture.pgs_rect,
            fixture.pgs_rects,
            clear_ms=fixture.pgs_clear_ms,
        )
        return
    if fixture.codec == "ass":
        path.write_text(
            "[Script Info]\n"
            "ScriptType: v4.00+\n"
            "PlayResX: 1280\n"
            "PlayResY: 720\n"
            "WrapStyle: 0\n"
            "\n"
            "[V4+ Styles]\n"
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
            "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, "
            "ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
            "Alignment, MarginL, MarginR, MarginV, Encoding\n"
            "Style: Default,Arial,96,&H00FFFFFF,&H000000FF,&H00000000,"
            "&H80000000,1,0,0,0,100,100,0,0,1,5,0,2,20,20,90,1\n"
            "\n"
            "[Events]\n"
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, "
            "MarginV, Effect, Text\n"
            "Dialogue: 0,0:00:01.00,0:00:09.00,Default,,0,0,0,,"
            "PHASE 17 ASS BURN-IN\n",
            encoding="utf-8",
        )
        return
    path.write_text(
        "1\n"
        "00:00:00,400 --> 00:00:03,400\n"
        "Phase 16 subtitle fixture\n\n"
        "2\n"
        "00:00:04,000 --> 00:00:08,000\n"
        "Server selected subtitle evidence\n",
        encoding="utf-8",
    )


def video_lavfi_for_fixture(fixture: MediaFixture, duration: str) -> str:
    if fixture.video_lavfi:
        return fixture.video_lavfi.format(
            width=fixture.width,
            height=fixture.height,
            duration=duration,
        )
    return f"testsrc2=size={fixture.width}x{fixture.height}:rate=24:duration={duration}"


def external_subtitle_path(media_dir: Path, fixture: MediaFixture) -> Path:
    if fixture.external_subtitle is None:
        raise ValueError(f"{fixture.name} has no external subtitle")
    stem = Path(fixture.file_name).stem
    return media_dir / f"{stem}.{fixture.external_subtitle.language}.{fixture.external_subtitle.extension}"


def generate_media(media_dir: Path, fixture: MediaFixture) -> Path:
    output = media_dir / fixture.file_name
    if output.exists():
        if fixture.external_subtitle is not None:
            sidecar = external_subtitle_path(media_dir, fixture)
            if not sidecar.exists():
                write_subtitle(
                    sidecar,
                    fixture.external_subtitle,
                    video_width=fixture.width,
                    video_height=fixture.height,
                )
        return output
    if fixture.source_media_rel:
        materialize_source_file(public_corpus_path(fixture.source_media_rel), output)
        if fixture.external_subtitle is not None:
            write_subtitle(
                external_subtitle_path(media_dir, fixture),
                fixture.external_subtitle,
                video_width=fixture.width,
                video_height=fixture.height,
            )
        return output
    duration = str(fixture.duration_seconds)
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "warning",
        "-y",
        "-f",
        "lavfi",
        "-i",
        video_lavfi_for_fixture(fixture, duration),
        "-f",
        "lavfi",
        "-i",
        f"sine=frequency=880:duration={duration}:sample_rate=48000",
    ]
    if fixture.alternate_audio:
        command.extend(
            [
                "-f",
                "lavfi",
                "-i",
                f"sine=frequency=440:duration={duration}:sample_rate=48000",
            ]
        )
    subtitle_input_index = 2 + (1 if fixture.alternate_audio else 0)
    if fixture.subtitle is not None:
        subtitle_path = media_dir / f"{fixture.name}.{fixture.subtitle.extension}"
        write_subtitle(
            subtitle_path,
            fixture.subtitle,
            video_width=fixture.width,
            video_height=fixture.height,
        )
        if fixture.subtitle.input_format:
            command.extend(["-f", fixture.subtitle.input_format])
        command.extend(["-i", str(subtitle_path)])
    command.extend(
        [
            "-map",
            "0:v:0",
            "-map",
            "1:a:0",
        ]
    )
    if fixture.alternate_audio:
        command.extend(["-map", "2:a:0"])
    if fixture.subtitle is not None:
        command.extend(["-map", f"{subtitle_input_index}:s:0"])
    command.extend(
        [
            "-c:v",
            fixture.ffmpeg_video_encoder,
            "-preset",
            "ultrafast",
            "-pix_fmt",
            fixture.ffmpeg_video_pixel_format,
            "-g",
            "48",
            "-c:a",
            fixture.ffmpeg_audio_encoder,
            "-b:a",
            "192k",
        ]
    )
    if fixture.ffmpeg_video_encoder == "libx264":
        command.extend(["-tune", "zerolatency"])
    command.extend(fixture.ffmpeg_video_extra_args)
    if fixture.subtitle is not None:
        command.extend(["-c:s", fixture.subtitle.mux_codec or fixture.subtitle.codec])
    if fixture.alternate_audio:
        command.extend(
            [
                "-metadata:s:a:0",
                "language=eng",
                "-metadata:s:a:0",
                "title=English",
                "-metadata:s:a:1",
                "language=jpn",
                "-metadata:s:a:1",
                "title=Alternate",
            ]
        )
    command.extend(["-t", duration, str(output)])
    run(command)
    if fixture.external_subtitle is not None:
        write_subtitle(
            external_subtitle_path(media_dir, fixture),
            fixture.external_subtitle,
            video_width=fixture.width,
            video_height=fixture.height,
        )
    return output


def normalized_probe(fixture: MediaFixture, path: Path) -> dict[str, Any]:
    stat = path.stat()
    subtitle_index = 2 + (1 if fixture.alternate_audio else 0)
    subtitle_streams: list[dict[str, Any]] = []
    if fixture.subtitle is not None:
        subtitle_streams.append(
            {
                "index": subtitle_index,
                "codec": fixture.subtitle.codec,
                "kind": fixture.subtitle.kind,
                "language": fixture.subtitle.language,
                "title": fixture.subtitle.title,
                "is_default": fixture.subtitle.is_default,
                "is_forced": fixture.subtitle.is_forced,
                "is_hearing_impaired": False,
                "external_path": None,
            }
        )
    return {
        "probe_version": MEDIA_CAPABILITIES_PROBE_VERSION,
        "ffprobe_version": "phase16-client-fixture",
        "probe_status": "ok",
        "probe_error": None,
        "probed_at": None,
        "path": str(path),
        "container": {
            "format_names": [fixture.container],
            "canonical": fixture.container,
            "major_brand": None,
            "compatible_brands": [],
        },
        "duration_seconds": float(fixture.duration_seconds),
        "size_bytes": stat.st_size,
        "overall_bitrate_bps": fixture.bitrate_bps,
        "start_time_seconds": 0.0,
        "video_streams": [
            {
                "index": 0,
                "codec": fixture.video_codec,
                "profile": fixture.video_profile,
                "level": 41,
                "pixel_format": fixture.ffmpeg_video_pixel_format,
                "width": fixture.width,
                "height": fixture.height,
                "frame_rate": 24.0,
                "bit_depth": fixture.bit_depth,
                "bitrate_bps": fixture.bitrate_bps,
                "color_primaries": fixture.color_primaries,
                "color_transfer": fixture.color_transfer,
                "color_matrix": fixture.color_matrix,
                "hdr10": fixture.hdr10,
                "hdr10_plus": fixture.hdr10_plus,
                "dolby_vision": fixture.dolby_vision,
                "mastering_metadata": fixture.mastering_metadata,
                "content_light_metadata": fixture.content_light_metadata,
                "dolby_vision_profile": fixture.dolby_vision_profile,
                "dolby_vision_has_hdr10_fallback": fixture.dolby_vision_has_hdr10_fallback,
                "is_default": True,
                "is_forced": False,
            }
        ],
        "audio_streams": audio_streams_for_fixture(fixture),
        "subtitle_streams": subtitle_streams,
        "chapters_present": False,
        "attachments_present": False,
    }


def audio_streams_for_fixture(fixture: MediaFixture) -> list[dict[str, Any]]:
    streams = [
        {
            "index": 1,
            "codec": fixture.audio_codec,
            "profile": None,
            "channels": 2,
            "channel_layout": "stereo",
            "sample_rate": 48000,
            "bitrate_bps": 192000,
            "language": "eng",
            "title": "English",
            "is_default": True,
            "is_forced": False,
        }
    ]
    if fixture.alternate_audio:
        streams.append(
            {
                "index": 2,
                "codec": fixture.audio_codec,
                "profile": None,
                "channels": 2,
                "channel_layout": "stereo",
                "sample_rate": 48000,
                "bitrate_bps": 192000,
                "language": "jpn",
                "title": "Alternate",
                "is_default": False,
                "is_forced": False,
            }
        )
    return streams


def seed_fixture(db_path: Path, media_dir: Path, fixture: MediaFixture) -> dict[str, str]:
    path = media_dir / fixture.file_name
    item_id = str(uuid.uuid4())
    file_id = str(uuid.uuid4())
    episode_ids: list[str] = []
    with sqlite3.connect(db_path) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        if fixture.episode:
            series_id = item_id
            season_id = str(uuid.uuid4())
            conn.execute(
                "INSERT INTO media_items (id, type, external_ids, title, year, runtime_seconds) VALUES (?, 'series', '{}', ?, 2026, ?)",
                (series_id, "Phase 16 Fixture Series", fixture.duration_seconds),
            )
            conn.execute(
                "INSERT INTO series (id, title, year, library_type) VALUES (?, ?, 2026, 'tv')",
                (series_id, "Phase 16 Fixture Series"),
            )
            conn.execute(
                "INSERT INTO seasons (id, series_id, season_number, title) VALUES (?, ?, 1, 'Season 1')",
                (season_id, series_id),
            )
            for episode_number in range(1, max(1, fixture.episode_count) + 1):
                episode_id = str(uuid.uuid4())
                episode_ids.append(episode_id)
                conn.execute(
                    "INSERT INTO episodes (id, series_id, season_id, season_number, episode_number, title, runtime_seconds, has_file) VALUES (?, ?, ?, 1, ?, ?, ?, 1)",
                    (
                        episode_id,
                        series_id,
                        season_id,
                        episode_number,
                        f"Direct Play Episode {episode_number}",
                        fixture.duration_seconds,
                    ),
                )
        else:
            conn.execute(
                "INSERT INTO media_items (id, type, external_ids, title, year, runtime_seconds) VALUES (?, 'movie', '{}', ?, 2026, ?)",
                (item_id, f"Phase 16 {fixture.name.replace('_', ' ').title()}", fixture.duration_seconds),
            )
            conn.execute(
                "INSERT INTO movies (id, title, year, runtime_seconds) VALUES (?, ?, 2026, ?)",
                (item_id, f"Phase 16 {fixture.name.replace('_', ' ').title()}", fixture.duration_seconds),
            )

        conn.execute(
            """
            INSERT INTO media_files
                (id, media_item_id, path, size_bytes, container, video_codec, audio_codec,
                 width, height, bitrate_bps, scan_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ok')
            """,
            (
                file_id,
                item_id,
                str(path),
                path.stat().st_size,
                fixture.container,
                fixture.video_codec,
                fixture.audio_codec,
                fixture.width,
                fixture.height,
                fixture.bitrate_bps,
            ),
        )
        if fixture.episode:
            for episode_id in episode_ids:
                conn.execute(
                    "INSERT INTO episode_files (episode_id, media_file_id) VALUES (?, ?)",
                    (episode_id, file_id),
                )
        else:
            conn.execute(
                "INSERT INTO movie_files (movie_id, media_file_id) VALUES (?, ?)",
                (item_id, file_id),
            )
        probe = normalized_probe(fixture, path)
        conn.execute(
            """
            INSERT INTO media_file_probes
                (media_file_id, probe_version, ffprobe_version, probe_status, source_mtime_ms,
                 source_size_bytes, normalized_json, raw_json, error)
            VALUES (?, ?, 'phase16-client-fixture', 'ok', ?, ?, ?, NULL, NULL)
            """,
            (
                file_id,
                MEDIA_CAPABILITIES_PROBE_VERSION,
                int(path.stat().st_mtime * 1000),
                path.stat().st_size,
                json.dumps(probe, separators=(",", ":"), sort_keys=True),
            ),
        )
        if fixture.external_subtitle is not None:
            sidecar = external_subtitle_path(media_dir, fixture)
            conn.execute(
                """
                INSERT INTO external_subtitles
                    (id, media_file_id, path, language, title, format, is_default, is_forced,
                     is_hearing_impaired, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                (
                    str(uuid.uuid4()),
                    file_id,
                    str(sidecar),
                    fixture.external_subtitle.language,
                    fixture.external_subtitle.title,
                    fixture.external_subtitle.extension,
                    int(fixture.external_subtitle.is_default),
                    int(fixture.external_subtitle.is_forced),
                ),
            )
        if fixture.midm_segment_type:
            segment_id = str(uuid.uuid4())
            candidate_id = str(uuid.uuid4())
            segment_item_type = "episode" if fixture.episode else "movie"
            segment_item_id = episode_ids[0] if fixture.episode else item_id
            conn.execute(
                """
                INSERT INTO media_segment_candidates
                    (id, media_file_id, item_type, item_id, segment_type, start_seconds,
                     end_seconds, provider_kind, provider_id, provider_version, confidence,
                     validation_state, validation_reason, identity_strength, source_payload_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'fixture', 'client_automation', '1',
                        0.99, 'accepted', 'fixture_seeded', 'file_fingerprint', '{}')
                """,
                (
                    candidate_id,
                    file_id,
                    segment_item_type,
                    segment_item_id,
                    fixture.midm_segment_type,
                    fixture.midm_segment_start_seconds,
                    fixture.midm_segment_end_seconds,
                ),
            )
            conn.execute(
                """
                INSERT INTO media_segments
                    (id, media_file_id, item_type, item_id, segment_type, start_seconds,
                     end_seconds, canonical_candidate_id, source_label, confidence, locked,
                     status, metadata_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'MIDM client automation fixture',
                        0.99, 0, 'active', '{}')
                """,
                (
                    segment_id,
                    file_id,
                    segment_item_type,
                    segment_item_id,
                    fixture.midm_segment_type,
                    fixture.midm_segment_start_seconds,
                    fixture.midm_segment_end_seconds,
                    candidate_id,
                ),
            )
        conn.commit()
    return {
        "item_id": item_id,
        "file_id": file_id,
        "episode_id": episode_ids[0] if episode_ids else "",
        "next_episode_id": episode_ids[1] if len(episode_ids) > 1 else "",
    }


def signup(base_url: str) -> str:
    email = f"phase16-{uuid.uuid4()}@example.com"
    status, body, _headers = http_request(
        base_url,
        "POST",
        "/api/v1/auth/signup",
        body={"email": email, "password": "strongpassword"},
        timeout=10,
    )
    if status != 200 or not isinstance(body, dict):
        raise RuntimeError(f"signup failed status={status} body={body}")
    token = body.get("access_token") or body.get("accessToken")
    if not token:
        raise RuntimeError(f"signup response missing token: {body}")
    return str(token)


def seed_midhm_user_preferences(db_path: Path) -> None:
    with sqlite3.connect(db_path) as conn:
        row = conn.execute("SELECT id FROM users LIMIT 1").fetchone()
        if row is None:
            raise RuntimeError("MIDM fixture preferences require a seeded user")
        user_id = str(row[0])
        conn.execute(
            """
            INSERT INTO user_playback_preferences
                (user_id, skip_intro_behavior, skip_recap_behavior, skip_preview_behavior,
                 skip_credits_behavior, skip_outro_behavior, autoplay_enabled,
                 autoplay_countdown_seconds, autoplay_max_consecutive,
                 autoplay_max_elapsed_minutes, segment_provider_settings_json,
                 created_at, updated_at)
            VALUES (?, 'prompt', 'prompt', 'prompt', 'auto', 'prompt', 1, 1, 3, 180,
                    ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT(user_id) DO UPDATE SET
                skip_intro_behavior = excluded.skip_intro_behavior,
                skip_recap_behavior = excluded.skip_recap_behavior,
                skip_preview_behavior = excluded.skip_preview_behavior,
                skip_credits_behavior = excluded.skip_credits_behavior,
                skip_outro_behavior = excluded.skip_outro_behavior,
                autoplay_enabled = excluded.autoplay_enabled,
                autoplay_countdown_seconds = excluded.autoplay_countdown_seconds,
                autoplay_max_consecutive = excluded.autoplay_max_consecutive,
                autoplay_max_elapsed_minutes = excluded.autoplay_max_elapsed_minutes,
                segment_provider_settings_json = excluded.segment_provider_settings_json,
                updated_at = CURRENT_TIMESTAMP
            """,
            (
                user_id,
                json.dumps(
                    {
                        "theintrodb": {"enabled": False},
                        "aniskip": {"enabled": False},
                        "local_audio_recurring": {"enabled": False},
                        "local_visual_recurring": {"enabled": False},
                    },
                    separators=(",", ":"),
                    sort_keys=True,
                ),
            ),
        )
        conn.commit()


def play_request_for_case(case: dict[str, Any]) -> dict[str, Any]:
    body = {
        "media_item_id": case["media_item_id"],
        "network_type": case.get("network_type", "lan"),
        "client_capabilities": case["client_capabilities"],
    }
    if case.get("media_file_id"):
        body["preferred_file_id"] = case["media_file_id"]
    if case.get("episode_id"):
        body["preferred_episode_id"] = case["episode_id"]
    return body


def assert_path_value(value: Any, path: str, expected: Any) -> None:
    current = value
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            raise AssertionError(f"missing {path} in {value}")
        current = current[part]
    if current != expected:
        raise AssertionError(f"{path} expected {expected!r}, got {current!r}")


def preflight_case(base_url: str, token: str, case: dict[str, Any]) -> None:
    headers = {"authorization": f"Bearer {token}"}
    status, body, _headers = http_request(
        base_url,
        "POST",
        "/api/v1/play",
        headers=headers,
        body=play_request_for_case(case),
        timeout=20,
    )
    if status != 200 or not isinstance(body, dict):
        raise RuntimeError(f"{case['name']} play preflight failed status={status} body={body}")
    if body.get("mode") != case["expect_mode"]:
        raise RuntimeError(f"{case['name']} expected mode {case['expect_mode']}, got {body}")
    if body.get("delivery") != case["expect_delivery"]:
        raise RuntimeError(f"{case['name']} expected delivery {case['expect_delivery']}, got {body}")
    session_id = body.get("session_id") or body.get("sessionId")
    if not session_id:
        raise RuntimeError(f"{case['name']} missing session id: {body}")
    status, poll, _headers = http_request(
        base_url,
        "GET",
        f"/api/v1/sessions/{session_id}/poll",
        headers=headers,
        timeout=10,
    )
    if status != 200 or not isinstance(poll, dict):
        raise RuntimeError(f"{case['name']} poll preflight failed status={status} body={poll}")
    for key, expected in case.get("expect_server", {}).items():
        assert_path_value(compact_server_poll(poll), key, expected)
    http_request(base_url, "POST", f"/api/v1/sessions/{session_id}/end", headers=headers, timeout=10)


def compact_server_poll(poll: dict[str, Any]) -> dict[str, Any]:
    plan_summary = poll.get("plan_summary") if isinstance(poll.get("plan_summary"), dict) else {}
    active_rung = poll.get("active_rung") if isinstance(poll.get("active_rung"), dict) else {}
    return {
        "mode": poll.get("mode"),
        "delivery": poll.get("delivery"),
        "server_seek_required": poll.get("server_seek_required"),
        "selected_audio_track": plan_summary.get("selected_audio_track"),
        "selected_subtitle_track": plan_summary.get("selected_subtitle_track"),
        "video_action": plan_summary.get("video_action"),
        "audio_action": plan_summary.get("audio_action"),
        "subtitle_action": plan_summary.get("subtitle_action"),
        "hdr_action": plan_summary.get("hdr_action"),
        "video_transcode_reason": plan_summary.get("video_transcode_reason"),
        "tone_map": plan_summary.get("tone_map"),
        "adaptive": plan_summary.get("adaptive"),
        "active_rung": active_rung,
    }


def manifest_cases(ids: dict[str, dict[str, str]]) -> list[dict[str, Any]]:
    browser_fixed = dict(BROWSER_CAPS)
    browser_fixed["max_bitrate_bps"] = 20_000_000
    browser_low = dict(BROWSER_CAPS)
    browser_low["max_bitrate_bps"] = 3_000_000
    browser_auto = dict(BROWSER_CAPS)
    browser_auto["quality_mode"] = "automatic"
    browser_auto["abr_support_type"] = "hls.js"
    browser_auto["max_bitrate_bps"] = 20_000_000
    browser_ass_burn_in = dict(BROWSER_CAPS)
    browser_ass_burn_in["supported_containers"] = ["mkv", "mp4"]
    browser_ass_burn_in["ass_complexity_support"] = "burn_in"
    browser_ass_burn_in["max_bitrate_bps"] = 20_000_000
    browser_image_burn_in = dict(BROWSER_CAPS)
    browser_image_burn_in["supported_containers"] = ["mkv", "mp4"]
    browser_image_burn_in["max_bitrate_bps"] = 20_000_000
    browser_sdr_hevc_capable = dict(BROWSER_CAPS)
    browser_sdr_hevc_capable["supported_video_codecs"] = ["h264", "hevc"]
    browser_sdr_hevc_capable["max_bitrate_bps"] = 20_000_000
    native = dict(NATIVE_EXPECTED_CAPS)

    cases = [
        {
            "name": "direct-play-native-mpv-movie",
            "profile": "native_mpv",
            "media_item_id": ids["direct_play"]["item_id"],
            "media_file_id": ids["direct_play"]["file_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
                "subtitle_action": "disabled",
            },
            "exercise_controls": True,
        },
        {
            "name": "direct-play-native-mpv-episode",
            "profile": "native_mpv",
            "media_item_id": ids["direct_play_episode"]["item_id"],
            "episode_id": ids["direct_play_episode"]["episode_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
            },
        },
        {
            "name": "midm-skip-prompt-native-mpv",
            "profile": "native_mpv",
            "media_item_id": ids["midm_skip_prompt"]["item_id"],
            "media_file_id": ids["midm_skip_prompt"]["file_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
                "subtitle_action": "disabled",
            },
            "automation_actions": "wait:2,skip_active_segment,stop",
        },
        {
            "name": "midm-auto-skip-native-mpv",
            "profile": "native_mpv",
            "media_item_id": ids["midm_auto_skip"]["item_id"],
            "media_file_id": ids["midm_auto_skip"]["file_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
                "subtitle_action": "disabled",
            },
            "automation_actions": "wait:2,stop",
            "expect_event": ["segment_skip_requested"],
        },
        {
            "name": "midm-up-next-cancel-native-mpv",
            "profile": "native_mpv",
            "media_item_id": ids["midm_up_next"]["item_id"],
            "episode_id": ids["midm_up_next"]["episode_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
            },
            "automation_actions": "wait:1,up_next_cancel,stop",
            "expect_event": [
                "up_next_countdown_started",
                "automation_up_next_cancel",
                "up_next_cancelled",
            ],
        },
        {
            "name": "midm-up-next-play-now-native-mpv",
            "profile": "native_mpv",
            "media_item_id": ids["midm_up_next"]["item_id"],
            "episode_id": ids["midm_up_next"]["episode_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
            },
            "automation_actions": "wait:1,up_next_play_now,wait:1,stop",
            "expect_event": [
                "up_next_countdown_started",
                "automation_up_next_play_now",
                "up_next_play_now",
            ],
        },
        {
            "name": "midm-up-next-autoplay-native-mpv",
            "profile": "native_mpv",
            "media_item_id": ids["midm_up_next"]["item_id"],
            "episode_id": ids["midm_up_next"]["episode_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
            },
            "automation_actions": "wait:3,stop",
            "expect_event": [
                "up_next_countdown_started",
                "up_next_autoplay_starting",
            ],
        },
        {
            "name": "direct-play-native-mpv-audio-track-switch",
            "profile": "native_mpv",
            "media_item_id": ids["direct_play_audio_switch"]["item_id"],
            "media_file_id": ids["direct_play_audio_switch"]["file_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
                "subtitle_action": "disabled",
            },
            "automation_actions": "audio_next,stop",
            "expect_event": ["audio_track_switch_requested"],
        },
        {
            "name": "direct-stream-browser-like-mkv-to-hls",
            "profile": "browser_like",
            "media_item_id": ids["direct_stream"]["item_id"],
            "media_file_id": ids["direct_stream"]["file_id"],
            "expect_mode": "direct_stream",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_fixed,
            "expect_server": {
                "server_seek_required": True,
                "video_action": "copy",
                "audio_action": "copy",
            },
        },
        {
            "name": "direct-stream-browser-like-hls-seek-restart",
            "profile": "browser_like",
            "media_item_id": ids["direct_stream"]["item_id"],
            "media_file_id": ids["direct_stream"]["file_id"],
            "expect_mode": "direct_stream",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_fixed,
            "expect_server": {
                "server_seek_required": True,
                "video_action": "copy",
                "audio_action": "copy",
            },
            "automation_actions": "seek_forward,seek_backward,stop",
            "require_server_seek_restart": True,
        },
        {
            "name": "direct-play-native-mpv-retry-from-current",
            "profile": "native_mpv",
            "media_item_id": ids["direct_play"]["item_id"],
            "media_file_id": ids["direct_play"]["file_id"],
            "expect_mode": "direct_play",
            "expect_delivery": "direct_file",
            "network_type": "lan",
            "client_capabilities": native,
            "expect_server": {
                "server_seek_required": False,
                "selected_audio_track": 1,
                "video_action": "passthrough",
                "audio_action": "passthrough",
                "subtitle_action": "disabled",
            },
            "automation_actions": "wait:2,retry_from_current,wait,stop",
            "require_session_restart": True,
            "invalidate_session_before_retry": True,
        },
        {
            "name": "audio-transcode-browser-like-ac3-to-aac",
            "profile": "browser_like",
            "media_item_id": ids["audio_transcode"]["item_id"],
            "media_file_id": ids["audio_transcode"]["file_id"],
            "expect_mode": "audio_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_fixed,
            "expect_server": {
                "server_seek_required": True,
                "video_action": "copy",
                "audio_action": "transcode",
            },
        },
        {
            "name": "subtitle-transcode-webvtt-browser-like-srt",
            "profile": "browser_like",
            "media_item_id": ids["subtitle_transcode"]["item_id"],
            "media_file_id": ids["subtitle_transcode"]["file_id"],
            "expect_mode": "subtitle_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_fixed,
            "expect_server": {
                "server_seek_required": True,
                "selected_subtitle_track": 2,
                "subtitle_action": "convert_text_to_webvtt",
            },
            "require_subtitle_selection": True,
            "automation_actions": "subtitle_next,stop",
            "expect_event": ["subtitle_track_switch_requested"],
        },
        {
            "name": "video-transcode-browser-like-bitrate-cap",
            "profile": "browser_like",
            "media_item_id": ids["video_transcode"]["item_id"],
            "media_file_id": ids["video_transcode"]["file_id"],
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "wan",
            "client_capabilities": browser_low,
            "expect_server": {
                "server_seek_required": True,
                "video_action": "transcode",
                "audio_action": "transcode",
            },
        },
        {
            "name": "subtitle-burn-in-browser-like-complex-ass",
            "profile": "browser_like",
            "media_item_id": ids["complex_ass_burn_in"]["item_id"],
            "media_file_id": ids["complex_ass_burn_in"]["file_id"],
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_ass_burn_in,
            "expect_server": {
                "server_seek_required": True,
                "selected_subtitle_track": 2,
                "video_action": "transcode",
                "subtitle_action": "burn_in",
                "video_transcode_reason": "subtitle_not_supported",
            },
            "require_subtitle_selection": True,
            "require_bright_region": "ass_overlay:0.05:0.50:0.90:0.45:1:120",
        },
        {
            "name": "image-subtitle-burn-in-browser-like-pgs",
            "profile": "browser_like",
            "media_item_id": ids["pgs_burn_in"]["item_id"],
            "media_file_id": ids["pgs_burn_in"]["file_id"],
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_image_burn_in,
            "expect_server": {
                "server_seek_required": True,
                "selected_subtitle_track": 2,
                "video_action": "transcode",
                "subtitle_action": "burn_in",
                "video_transcode_reason": "subtitle_requires_burn_in",
            },
            "require_subtitle_selection": True,
            "require_bright_region": "pgs_overlay:0.25:0.70:0.55:0.25:20:120",
        },
        {
            "name": "image-subtitle-burn-in-browser-like-pgs-transparent-overlay",
            "profile": "browser_like",
            "media_item_id": ids["pgs_transparent_overlay"]["item_id"],
            "media_file_id": ids["pgs_transparent_overlay"]["file_id"],
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_image_burn_in,
            "expect_server": {
                "server_seek_required": True,
                "selected_subtitle_track": 2,
                "video_action": "transcode",
                "subtitle_action": "burn_in",
                "video_transcode_reason": "subtitle_requires_burn_in",
            },
            "require_subtitle_selection": True,
            "require_bright_region": [
                "pgs_transparent_left:0.25:0.77:0.13:0.12:200:230",
                "pgs_transparent_right:0.625:0.77:0.13:0.12:200:230",
                "pgs_transparent_gap:0.46:0.77:0.08:0.12:80:100:190:220",
            ],
            "require_timing_evidence": True,
            "min_position_sample_count": 4,
            "min_position_span_seconds": 6.0,
            "max_position_regression_seconds": 0.75,
        },
        {
            "name": "image-subtitle-burn-in-browser-like-pgs-transparent-overlay-long-timing",
            "profile": "browser_like",
            "media_item_id": ids["pgs_transparent_overlay_long_timing"]["item_id"],
            "media_file_id": ids["pgs_transparent_overlay_long_timing"]["file_id"],
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_image_burn_in,
            "expect_server": {
                "server_seek_required": True,
                "selected_subtitle_track": 2,
                "video_action": "transcode",
                "subtitle_action": "burn_in",
                "video_transcode_reason": "subtitle_requires_burn_in",
            },
            "automation_actions": "wait:22,stop",
            "expect_event": ["automation_wait", "stop_requested"],
            "timeout_seconds": 90,
            "require_subtitle_selection": True,
            "require_bright_region": [
                "pgs_long_left:0.25:0.77:0.13:0.12:200:230",
                "pgs_long_right:0.625:0.77:0.13:0.12:200:230",
                "pgs_long_gap:0.46:0.77:0.08:0.12:80:100:190:220",
            ],
            "require_timing_evidence": True,
            "min_position_sample_count": 10,
            "min_position_span_seconds": 20.0,
            "max_position_regression_seconds": 0.75,
        },
        {
            "name": "image-subtitle-burn-in-browser-like-dvdsub-transparent-overlay",
            "profile": "browser_like",
            "media_item_id": ids["dvdsub_transparent_overlay"]["item_id"],
            "media_file_id": ids["dvdsub_transparent_overlay"]["file_id"],
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_image_burn_in,
            "expect_server": {
                "server_seek_required": True,
                "selected_subtitle_track": 2,
                "video_action": "transcode",
                "subtitle_action": "burn_in",
                "video_transcode_reason": "subtitle_requires_burn_in",
            },
            "require_subtitle_selection": True,
            "require_bright_region": [
                "dvdsub_left:0.25:0.77:0.13:0.12:200:230",
                "dvdsub_right:0.625:0.77:0.13:0.12:200:230",
                "dvdsub_gap:0.46:0.77:0.08:0.12:80:100:190:220",
            ],
        },
        {
            "name": "external-image-subtitle-burn-in-browser-like-pgs-sidecar-transparent-overlay",
            "profile": "browser_like",
            "media_item_id": ids["external_pgs_sidecar_transparent_overlay"]["item_id"],
            "media_file_id": ids["external_pgs_sidecar_transparent_overlay"]["file_id"],
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_image_burn_in,
            "expect_server": {
                "server_seek_required": True,
                "selected_subtitle_track": -100000,
                "video_action": "transcode",
                "subtitle_action": "burn_in",
                "video_transcode_reason": "subtitle_requires_burn_in",
            },
            "require_subtitle_selection": True,
            "require_bright_region": [
                "external_pgs_left:0.25:0.77:0.13:0.12:200:230",
                "external_pgs_right:0.625:0.77:0.13:0.12:200:230",
                "external_pgs_gap:0.46:0.77:0.08:0.12:80:100:190:220",
            ],
        },
        {
            "name": "hdr-tonemap-browser-like-hdr10-to-sdr",
            "profile": "browser_like",
            "media_item_id": ids["hdr10_tonemap"]["item_id"],
            "media_file_id": ids["hdr10_tonemap"]["file_id"],
            "expect_mode": "video_transcode",
            "expect_delivery": "hls_fmp4",
            "network_type": "lan",
            "client_capabilities": browser_sdr_hevc_capable,
            "expect_server": {
                "server_seek_required": True,
                "video_action": "transcode",
                "hdr_action": "tone_map_to_sdr",
                "video_transcode_reason": "hdr_tone_mapping_required",
                "tone_map.output_primaries": "bt709",
                "tone_map.output_transfer": "bt709",
                "tone_map.output_matrix": "bt709",
            },
            "require_hdr_objective": True,
            "hdr_objective_args": [
                "--max-clipped-fraction",
                "0.99",
                "--min-output-mean-luma",
                "32",
                "--max-output-mean-luma",
                "224",
                "--min-output-luma-range",
                "64",
                "--min-output-luma-stddev",
                "16",
            ],
        },
        {
            "name": "adaptive-transcode-browser-like-automatic",
            "profile": "browser_like",
            "media_item_id": ids["adaptive_transcode"]["item_id"],
            "media_file_id": ids["adaptive_transcode"]["file_id"],
            "expect_mode": "adaptive_transcode",
            "expect_delivery": "hls_adaptive_fmp4",
            "network_type": "wan",
            "client_capabilities": browser_auto,
            "expect_server": {
                "server_seek_required": True,
                "adaptive": True,
                "video_action": "transcode",
            },
            "automation_actions": "lower_quality,stop",
        },
    ]
    if "traffic2_vobsub_visual" in ids:
        cases.append(
            {
                "name": TRAFFIC2_VOBSUB_VISUAL_CASE,
                "profile": "browser_like",
                "media_item_id": ids["traffic2_vobsub_visual"]["item_id"],
                "media_file_id": ids["traffic2_vobsub_visual"]["file_id"],
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "network_type": "lan",
                "client_capabilities": browser_image_burn_in,
                "expect_server": {
                    "server_seek_required": True,
                    "selected_subtitle_track": -100000,
                    "video_action": "transcode",
                    "subtitle_action": "burn_in",
                    "video_transcode_reason": "subtitle_requires_burn_in",
                },
                "require_visual_review": True,
                "visual_review_type": "external_vobsub",
                "require_bright_region": "traffic2_vobsub_overlay:0.25:0.86:0.50:0.10:130:220",
            }
        )
    if "kodi_hdr10plus_profile_b_visual" in ids:
        cases.append(
            {
                "name": KODI_HDR10PLUS_PROFILE_B_VISUAL_CASE,
                "profile": "browser_like",
                "media_item_id": ids["kodi_hdr10plus_profile_b_visual"]["item_id"],
                "media_file_id": ids["kodi_hdr10plus_profile_b_visual"]["file_id"],
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "network_type": "lan",
                "client_capabilities": browser_sdr_hevc_capable,
                "expect_server": {
                    "server_seek_required": True,
                    "video_action": "transcode",
                    "audio_action": "transcode",
                    "hdr_action": "tone_map_to_sdr",
                    "video_transcode_reason": "hdr_tone_mapping_required",
                    "tone_map.output_primaries": "bt709",
                    "tone_map.output_transfer": "bt709",
                    "tone_map.output_matrix": "bt709",
                },
                "require_visual_review": True,
                "visual_review_type": "hdr10_plus",
                "timeout_seconds": 180,
            }
        )
    if "kodi_hybrid_hdr10plus_dv_visual" in ids:
        cases.append(
            {
                "name": KODI_HYBRID_HDR10PLUS_DV_VISUAL_CASE,
                "profile": "browser_like",
                "media_item_id": ids["kodi_hybrid_hdr10plus_dv_visual"]["item_id"],
                "media_file_id": ids["kodi_hybrid_hdr10plus_dv_visual"]["file_id"],
                "expect_mode": "video_transcode",
                "expect_delivery": "hls_fmp4",
                "network_type": "lan",
                "client_capabilities": browser_sdr_hevc_capable,
                "expect_server": {
                    "server_seek_required": True,
                    "video_action": "transcode",
                    "audio_action": "transcode",
                    "hdr_action": "tone_map_to_sdr",
                    "video_transcode_reason": "hdr_tone_mapping_required",
                    "tone_map.output_primaries": "bt709",
                    "tone_map.output_transfer": "bt709",
                    "tone_map.output_matrix": "bt709",
                },
                "require_visual_review": True,
                "visual_review_type": "dolby_vision_hdr10_plus",
                "timeout_seconds": 240,
            }
        )
    return cases


def write_manifest(
    artifact_dir: Path,
    client_bin: Path,
    base_url: str,
    token: str,
    ids: dict[str, dict[str, str]],
    *,
    release_candidate_evidence: dict[str, Any] | None = None,
    hardware_hdr_certification_artifacts: list[dict[str, Any]] | None = None,
) -> Path:
    cases = manifest_cases(ids)
    manifest = {
        "required_profiles": ["native_mpv", "browser_like"],
        "required_modes": [
            "direct_play",
            "direct_stream",
            "audio_transcode",
            "subtitle_transcode",
            "video_transcode",
            "adaptive_transcode",
        ],
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
        "client_bin": str(client_bin),
        "server_url": base_url,
        "auth_token": token,
        "artifact_dir": str(artifact_dir / "matrix"),
        "cases": cases,
    }
    required_visual_review_cases = [
        name
        for key, name in [
            ("traffic2_vobsub_visual", TRAFFIC2_VOBSUB_VISUAL_CASE),
            ("kodi_hdr10plus_profile_b_visual", KODI_HDR10PLUS_PROFILE_B_VISUAL_CASE),
            ("kodi_hybrid_hdr10plus_dv_visual", KODI_HYBRID_HDR10PLUS_DV_VISUAL_CASE),
        ]
        if key in ids
    ]
    if required_visual_review_cases:
        manifest["required_visual_review_cases"] = required_visual_review_cases
    if release_candidate_evidence is not None:
        manifest["release_candidate_evidence"] = release_candidate_evidence
    if hardware_hdr_certification_artifacts:
        manifest["hardware_hdr_certification_artifacts"] = hardware_hdr_certification_artifacts
    manifest_path = artifact_dir / "playback-client-fixture-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True))
    return manifest_path


def main() -> int:
    args = parse_args()
    try:
        release_evidence = release_candidate_evidence_from_args(args)
        hardware_evidence = hardware_certification_evidence_from_paths(args.hardware_certification_json)
    except Exception as exc:
        print(f"fixture evidence configuration failed: {exc}", file=sys.stderr)
        return 2
    client_bin = Path(args.client_bin)
    if not client_bin.exists():
        print(f"client executable not found: {client_bin}", file=sys.stderr)
        return 2
    server_bin = Path(args.server_bin).expanduser().resolve() if args.server_bin else default_server_binary()
    if args.server_bin and (server_bin is None or not server_bin.exists()):
        print(f"server executable not found: {args.server_bin}", file=sys.stderr)
        return 2
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found; install ffmpeg to generate playback fixtures", file=sys.stderr)
        return 2

    temp_root = Path(tempfile.mkdtemp(prefix="elixir-phase16-client-"))
    artifact_dir = Path(args.artifact_dir) if args.artifact_dir else temp_root / "artifacts"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    media_dir = temp_root / "media"
    media_dir.mkdir(parents=True, exist_ok=True)
    scan_root = temp_root / "empty-library-scan-root"
    scan_root.mkdir(parents=True, exist_ok=True)
    db_path = temp_root / "elixir.db"
    db_path.touch()
    base_url = f"http://{HOST}:{args.port}"
    server: subprocess.Popen[str] | None = None
    try:
        fixtures = fixtures_for_run(args.include_public_visual_fixtures)
        if not args.no_generate_media:
            for fixture in fixtures.values():
                generate_media(media_dir, fixture)
        server = start_server(
            base_url,
            db_path,
            scan_root,
            args.port,
            args.server_timeout_seconds,
            server_bin,
        )
        token = signup(base_url)
        ids = {name: seed_fixture(db_path, media_dir, fixture) for name, fixture in fixtures.items()}
        seed_midhm_user_preferences(db_path)
        manifest_path = write_manifest(
            artifact_dir,
            client_bin,
            base_url,
            token,
            ids,
            release_candidate_evidence=release_evidence,
            hardware_hdr_certification_artifacts=hardware_evidence,
        )
        for case in manifest_cases(ids):
            preflight_case(base_url, token, case)
        log(f"wrote manifest {manifest_path}")
        if args.prepare_only:
            log("prepare-only requested; server will stop after manifest generation")
            return 0
        matrix_script = CLIENT_ROOT / "scripts" / "playback_client_automation_matrix.py"
        command = [
            sys.executable,
            str(matrix_script),
            "--manifest",
            str(manifest_path),
            "--client-bin",
            str(client_bin),
            "--server-url",
            base_url,
            "--auth-token",
            token,
            "--artifact-dir",
            str(artifact_dir / "matrix"),
            "--timeout-seconds",
            str(args.timeout_seconds),
        ]
        completed = subprocess.run(command, check=False)
        return completed.returncode
    finally:
        if server is not None:
            stop_server(server)
        if args.keep_temp:
            log(f"kept temporary root {temp_root}")
        else:
            shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
