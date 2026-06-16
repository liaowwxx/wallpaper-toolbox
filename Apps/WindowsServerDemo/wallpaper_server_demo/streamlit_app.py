from __future__ import annotations

from base64 import b64encode
from pathlib import Path
from typing import Optional
import importlib.util
import os
import ipaddress
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import streamlit as st

DEMO_ROOT = Path(__file__).resolve().parents[1]
if str(DEMO_ROOT) not in sys.path:
    sys.path.insert(0, str(DEMO_ROOT))

from wallpaper_server_demo.config import CONFIG_ENV, ServerConfig, load_config, save_config
from wallpaper_server_demo.library import build_and_write_manifest, scan_library


def main() -> None:
    st.set_page_config(page_title="Wallpaper Server Demo", layout="wide")
    st.title("Wallpaper Gallery Windows Server Demo")

    config = load_config()
    initialize_session_state(config)
    config = render_config_form(config)

    st.divider()
    render_actions(config)
    st.divider()
    render_library_preview(config)


def render_config_form(config: ServerConfig) -> ServerConfig:
    st.subheader("Configuration")

    st.caption("Use Browse buttons on the Windows PC running this Streamlit app. Manual paths still work.")
    render_directory_picker("Wallpaper library root", "library_root", r"D:\WallpaperLibrary")
    render_executable_picker("RePKG executable", "repkg_path", "RePKG.exe", required=True)
    render_executable_picker("miniserve executable", "miniserve_path", "miniserve.exe", required=False)
    render_executable_picker("ffmpeg executable", "ffmpeg_path", "ffmpeg.exe", required=False)

    col1, col2, col3 = st.columns(3)
    with col1:
        st.text_input("API host", key="api_host")
    with col2:
        st.number_input("API port", key="api_port", min_value=1, max_value=65535)
    with col3:
        st.number_input("miniserve port", key="miniserve_port", min_value=1, max_value=65535)

    auth_col1, auth_col2 = st.columns(2)
    with auth_col1:
        st.text_input("API username", key="api_username")
    with auth_col2:
        st.text_input("API password", key="api_password", type="password")
    if not st.session_state.api_username and not st.session_state.api_password:
        st.warning("API Basic Auth is disabled. Set an API username/password to require login from iOS.")

    suggested_host = get_recommended_host()
    st.text_input(
        "Public API base URL for iOS (Tailscale preferred)",
        key="public_api_base_url",
        placeholder=f"http://{suggested_host}:{int(st.session_state.api_port)}",
    )
    st.text_input(
        "Public static base URL",
        key="public_static_base_url",
        placeholder="Leave blank to keep files behind the API allow-list",
    )
    st.text_input("miniserve auth user:password", key="miniserve_auth")

    updated = ServerConfig(
        library_root=st.session_state.library_root.strip(),
        repkg_path=st.session_state.repkg_path.strip() or "RePKG.exe",
        ffmpeg_path=st.session_state.ffmpeg_path.strip() or "ffmpeg",
        api_host=st.session_state.api_host.strip() or "0.0.0.0",
        api_port=int(st.session_state.api_port),
        api_username=st.session_state.api_username.strip(),
        api_password=st.session_state.api_password,
        public_api_base_url=st.session_state.public_api_base_url.strip().rstrip("/"),
        public_static_base_url=st.session_state.public_static_base_url.strip().rstrip("/"),
        miniserve_path=st.session_state.miniserve_path.strip() or "miniserve.exe",
        miniserve_port=int(st.session_state.miniserve_port),
        miniserve_auth=st.session_state.miniserve_auth.strip(),
    )
    if needs_recommended_url_rewrite(updated.public_api_base_url, suggested_host):
        updated.public_api_base_url = f"http://{suggested_host}:{updated.api_port}"
    if st.button("Save configuration", type="primary"):
        path = save_config(updated)
        st.success(f"Saved {path}")
    return updated


def initialize_session_state(config: ServerConfig) -> None:
    defaults = {
        "library_root": config.library_root,
        "repkg_path": config.repkg_path,
        "ffmpeg_path": config.ffmpeg_path,
        "api_host": config.api_host,
        "api_port": config.api_port,
        "api_username": config.api_username,
        "api_password": config.api_password,
        "public_api_base_url": config.public_api_base_url,
        "public_static_base_url": config.public_static_base_url,
        "miniserve_path": config.miniserve_path,
        "miniserve_port": config.miniserve_port,
        "miniserve_auth": config.miniserve_auth,
    }
    for key, value in defaults.items():
        st.session_state.setdefault(key, value)
        pending_key = f"_{key}_pending"
        if pending_key in st.session_state:
            st.session_state[key] = st.session_state.pop(pending_key)


def render_directory_picker(label: str, key: str, placeholder: str) -> None:
    cols = st.columns([5, 1.2])
    with cols[0]:
        st.text_input(label, key=key, placeholder=placeholder)
    with cols[1]:
        st.write("")
        if st.button("Browse", key=f"{key}_browse"):
            selected = choose_directory(label, st.session_state.get(key, ""))
            if selected:
                st.session_state[f"_{key}_pending"] = selected
                st.rerun()

    path = Path(st.session_state.get(key, "")).expanduser()
    if st.session_state.get(key):
        if path.exists() and path.is_dir():
            st.caption("Directory found")
        else:
            st.warning(f"Directory not found: {path}")


def render_executable_picker(label: str, key: str, default_name: str, required: bool) -> None:
    cols = st.columns([5, 1.2])
    with cols[0]:
        st.text_input(label, key=key, placeholder=default_name)
    with cols[1]:
        st.write("")
        if st.button("Browse", key=f"{key}_browse"):
            selected = choose_executable(label, st.session_state.get(key, ""))
            if selected:
                st.session_state[f"_{key}_pending"] = selected
                st.rerun()

    value = st.session_state.get(key, "").strip()
    found = executable_exists(value)
    if found:
        st.caption(f"Found: {found}")
    elif required:
        st.warning(f"Required executable not found: {value or default_name}")
    else:
        st.caption(f"Optional executable not found: {value or default_name}")

    if key == "ffmpeg_path":
        st.caption("ffmpeg is optional. Without it, video thumbnails only work when a preview image exists.")


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
        f"iOS Settings URL: {config.normalized_public_api_base_url or f'http://{get_recommended_host()}:{config.api_port}'}",
        language="text",
    )
    if config.api_username or config.api_password:
        st.caption("API Basic Auth is enabled. Enter the same username/password in the iOS settings screen.")


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
    missing_modules = missing_api_modules()
    if missing_modules:
        st.error(
            "API server dependencies are missing: "
            + ", ".join(missing_modules)
            + ". Run: py -m pip install -r Apps\\WindowsServerDemo\\requirements.txt"
        )
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
    if st.session_state["api_process"].poll() is not None:
        st.error(f"API server exited immediately with code {st.session_state['api_process'].returncode}.")
        return
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
        "127.0.0.1",
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
    st.success(f"miniserve started on 127.0.0.1:{config.miniserve_port} for local testing only")


def call_rescan(config: ServerConfig) -> None:
    url = f"{config.normalized_public_api_base_url}/api/library/rescan"
    request = urllib.request.Request(url, method="POST")
    apply_api_auth(request, config)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            st.success(f"API rescan returned HTTP {response.status}")
    except urllib.error.URLError as error:
        st.error(f"API rescan failed: {error}")


def apply_api_auth(request: urllib.request.Request, config: ServerConfig) -> None:
    if not config.api_username and not config.api_password:
        return
    token = b64encode(f"{config.api_username}:{config.api_password}".encode("utf-8")).decode("ascii")
    request.add_header("Authorization", f"Basic {token}")


def choose_directory(title: str, initial_value: str) -> str:
    try:
        import tkinter as tk
        from tkinter import filedialog
    except Exception as error:
        st.error(f"Native folder picker is unavailable: {error}")
        return ""

    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    initial_dir = initial_value if Path(initial_value).exists() else str(Path.home())
    try:
        selected = filedialog.askdirectory(title=title, initialdir=initial_dir)
    finally:
        root.destroy()
    return selected or ""


def choose_executable(title: str, initial_value: str) -> str:
    try:
        import tkinter as tk
        from tkinter import filedialog
    except Exception as error:
        st.error(f"Native file picker is unavailable: {error}")
        return ""

    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    current = Path(initial_value)
    initial_dir = str(current.parent) if current.parent.exists() else str(Path.home())
    filetypes = [
        ("Executable files", "*.exe"),
        ("All files", "*.*"),
    ]
    try:
        selected = filedialog.askopenfilename(title=title, initialdir=initial_dir, filetypes=filetypes)
    finally:
        root.destroy()
    return selected or ""


def executable_exists(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    path = Path(value).expanduser()
    if path.exists() and path.is_file():
        return str(path)
    found = shutil.which(value)
    return found or ""


def is_running(process: Optional[subprocess.Popen]) -> bool:
    return process is not None and process.poll() is None


def process_status(process: Optional[subprocess.Popen]) -> str:
    if process is None:
        return "not started"
    if process.poll() is None:
        return f"running (pid {process.pid})"
    return f"exited ({process.returncode})"


def get_recommended_host() -> str:
    candidates = local_ipv4_candidates()
    if candidates:
        return candidates[0]
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            candidate = sock.getsockname()[0]
            if is_usable_lan_ip(candidate):
                return candidate
    except OSError:
        pass
    return "localhost"


def local_ipv4_candidates() -> list[str]:
    addresses: set[str] = set()
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            addresses.add(info[4][0])
    except OSError:
        pass
    addresses.update(ipconfig_ipv4_addresses())
    return sorted(addresses, key=ip_sort_key)


def ipconfig_ipv4_addresses() -> set[str]:
    try:
        output = subprocess.check_output(["ipconfig"], text=True, encoding="utf-8", errors="ignore")
    except Exception:
        return set()
    return set(re.findall(r"(?:IPv4[^\r\n:]*|IPv4 Address[^\r\n:]*):\s*([0-9.]+)", output))


def ip_sort_key(value: str) -> tuple[int, str]:
    if not is_usable_lan_ip(value):
        return (4, value)
    if is_tailscale_ip(value):
        return (0, value)
    if value.startswith("10."):
        return (1, value)
    if value.startswith("192.168."):
        return (2, value)
    if is_private_172(value):
        return (3, value)
    return (4, value)


def is_usable_lan_ip(value: str) -> bool:
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        return False
    if address.is_loopback or address.is_link_local or address.is_multicast:
        return False
    if value.startswith("198.18.") or value.startswith("198.19."):
        return False
    return address.is_private or is_tailscale_ip(value)


def is_tailscale_ip(value: str) -> bool:
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        return False
    return address.version == 4 and ipaddress.ip_address("100.64.0.0") <= address <= ipaddress.ip_address("100.127.255.255")


def is_private_172(value: str) -> bool:
    parts = value.split(".")
    return len(parts) == 4 and parts[0] == "172" and 16 <= int(parts[1]) <= 31


def is_localhost_url(value: str) -> bool:
    lowered = value.lower()
    return "://localhost" in lowered or "://127.0.0.1" in lowered


def needs_recommended_url_rewrite(value: str, recommended_host: str) -> bool:
    if not value:
        return True
    if is_localhost_url(value):
        return True
    host = urllib.parse.urlparse(value).hostname
    if host is None:
        return False
    if not is_usable_lan_ip(host):
        return is_ip_address(host)
    return is_tailscale_ip(recommended_host) and is_ip_address(host) and not is_tailscale_ip(host)


def is_ip_address(value: str) -> bool:
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def missing_api_modules() -> list[str]:
    return [
        module
        for module in ("fastapi", "uvicorn")
        if importlib.util.find_spec(module) is None
    ]


if __name__ == "__main__":
    main()
