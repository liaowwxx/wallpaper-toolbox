from __future__ import annotations

from pathlib import Path
from typing import Optional
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

import streamlit as st

from wallpaper_server_demo.config import CONFIG_ENV, ServerConfig, config_path, load_config, save_config
from wallpaper_server_demo.library import build_and_write_manifest, scan_library


DEMO_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    st.set_page_config(page_title="Wallpaper Server Demo", layout="wide")
    st.title("Wallpaper Gallery Windows Server Demo")

    config = load_config()
    config = render_config_form(config)

    st.divider()
    render_actions(config)
    st.divider()
    render_library_preview(config)


def render_config_form(config: ServerConfig) -> ServerConfig:
    st.subheader("Configuration")

    with st.form("server-config"):
        library_root = st.text_input(
            "Wallpaper library root",
            value=config.library_root,
            placeholder=r"D:\WallpaperLibrary",
        )
        repkg_path = st.text_input("RePKG executable", value=config.repkg_path)
        ffmpeg_path = st.text_input("ffmpeg executable", value=config.ffmpeg_path)

        col1, col2, col3 = st.columns(3)
        with col1:
            api_host = st.text_input("API host", value=config.api_host)
        with col2:
            api_port = st.number_input("API port", value=config.api_port, min_value=1, max_value=65535)
        with col3:
            miniserve_port = st.number_input(
                "miniserve port",
                value=config.miniserve_port,
                min_value=1,
                max_value=65535,
            )

        suggested_host = get_lan_ip()
        public_api_base_url = st.text_input(
            "Public API base URL for iOS",
            value=config.public_api_base_url or f"http://{suggested_host}:{api_port}",
        )
        public_static_base_url = st.text_input(
            "Public static base URL",
            value=config.public_static_base_url,
            placeholder=f"http://{suggested_host}:{miniserve_port} (optional; blank uses API /files)",
        )

        miniserve_path = st.text_input("miniserve executable", value=config.miniserve_path)
        miniserve_auth = st.text_input("miniserve auth user:password", value=config.miniserve_auth)

        submitted = st.form_submit_button("Save configuration")

    updated = ServerConfig(
        library_root=library_root.strip(),
        repkg_path=repkg_path.strip() or "RePKG.exe",
        ffmpeg_path=ffmpeg_path.strip() or "ffmpeg",
        api_host=api_host.strip() or "0.0.0.0",
        api_port=int(api_port),
        public_api_base_url=public_api_base_url.strip().rstrip("/"),
        public_static_base_url=public_static_base_url.strip().rstrip("/"),
        miniserve_path=miniserve_path.strip() or "miniserve.exe",
        miniserve_port=int(miniserve_port),
        miniserve_auth=miniserve_auth.strip(),
    )
    if submitted:
        path = save_config(updated)
        st.success(f"Saved {path}")
    return updated


def render_actions(config: ServerConfig) -> None:
    st.subheader("Service")
    config_file = save_config(config)

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        if st.button("Generate thumbnails + manifest", type="primary"):
            run_manifest_build(config)
    with col2:
        if st.button("Start API server"):
            start_api_server(config, config_file)
    with col3:
        if st.button("Start miniserve"):
            start_miniserve(config)
    with col4:
        if st.button("Rescan through API"):
            call_rescan(config)

    api_process = st.session_state.get("api_process")
    miniserve_process = st.session_state.get("miniserve_process")
    st.caption(f"API process: {process_status(api_process)}")
    st.caption(f"miniserve process: {process_status(miniserve_process)}")

    st.code(
        f"iOS Settings URL: {config.normalized_public_api_base_url or f'http://{get_lan_ip()}:{config.api_port}'}",
        language="text",
    )


def render_library_preview(config: ServerConfig) -> None:
    st.subheader("Library Preview")
    if not config.library_root:
        st.info("Set a library root first.")
        return
    if not config.root_path.exists():
        st.warning(f"Library root does not exist: {config.root_path}")
        return

    records = scan_library(config)
    st.write(f"{len(records)} wallpapers found")

    if config.manifest_path.exists():
        st.caption(f"Manifest: {config.manifest_path}")
    else:
        st.caption("Manifest has not been generated yet.")

    for record in records[:80]:
        with st.container(border=True):
            cols = st.columns([1, 3, 2])
            with cols[0]:
                if record.thumbnail_relative_path:
                    st.image(str(config.root_path / record.thumbnail_relative_path), width=128)
                else:
                    st.write("No thumbnail")
            with cols[1]:
                st.markdown(f"**{record.title}**")
                st.caption(f"id: `{record.id}`")
                st.write(f"type: `{record.type}`")
            with cols[2]:
                st.write(f"assets: {len(record.assets)}")
                st.write("pkg: yes" if record.pkg_path else "pkg: no")
                st.write("unpacked: yes" if record.is_unpacked else "unpacked: no")


def run_manifest_build(config: ServerConfig) -> None:
    if not config.library_root:
        st.error("Set library root first.")
        return
    with st.spinner("Generating thumbnails and library.json..."):
        result = build_and_write_manifest(config)
    st.success(f"Generated {len(result.records)} items at {config.manifest_path}")


def start_api_server(config: ServerConfig, config_file: Path) -> None:
    process = st.session_state.get("api_process")
    if is_running(process):
        st.info("API server is already running.")
        return

    env = os.environ.copy()
    env[CONFIG_ENV] = str(config_file)
    command = [
        sys.executable,
        "-m",
        "uvicorn",
        "wallpaper_server_demo.api:app",
        "--host",
        config.api_host,
        "--port",
        str(config.api_port),
    ]
    st.session_state["api_process"] = subprocess.Popen(command, cwd=DEMO_ROOT, env=env)
    time.sleep(0.8)
    st.success(f"API server started on {config.api_host}:{config.api_port}")


def start_miniserve(config: ServerConfig) -> None:
    process = st.session_state.get("miniserve_process")
    if is_running(process):
        st.info("miniserve is already running.")
        return
    if not config.library_root:
        st.error("Set library root first.")
        return

    command = [
        config.miniserve_path,
        "-i",
        "0.0.0.0",
        "-p",
        str(config.miniserve_port),
        "--qrcode",
        "--no-symlinks",
    ]
    if config.miniserve_auth:
        command += ["--auth", config.miniserve_auth]
    command.append(str(config.root_path))

    st.session_state["miniserve_process"] = subprocess.Popen(command, cwd=DEMO_ROOT)
    time.sleep(0.8)
    st.success(f"miniserve started on port {config.miniserve_port}")


def call_rescan(config: ServerConfig) -> None:
    url = f"{config.normalized_public_api_base_url}/api/library/rescan"
    request = urllib.request.Request(url, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            st.success(f"API rescan returned HTTP {response.status}")
    except urllib.error.URLError as error:
        st.error(f"API rescan failed: {error}")


def is_running(process: Optional[subprocess.Popen]) -> bool:
    return process is not None and process.poll() is None


def process_status(process: Optional[subprocess.Popen]) -> str:
    if process is None:
        return "not started"
    if process.poll() is None:
        return f"running (pid {process.pid})"
    return f"exited ({process.returncode})"


def get_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
    except OSError:
        return "localhost"


if __name__ == "__main__":
    main()
