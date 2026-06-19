from __future__ import annotations

from base64 import b64decode
from binascii import Error as Base64Error
from hmac import compare_digest
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse, urlunparse
import tempfile
import zipfile

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response
from starlette.background import BackgroundTask

from .config import ServerConfig, load_config
from .library import build_and_write_manifest, load_manifest, scan_library, unpack_wallpaper


app = FastAPI(title="Wallpaper Gallery Windows Demo API", version="0.1.0")
jobs: dict[str, dict[str, Any]] = {}

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def basic_auth_middleware(request: Request, call_next):
    config = load_config()
    if not is_api_auth_enabled(config) or is_authorized(request, config):
        return await call_next(request)
    return Response(
        status_code=401,
        headers={"WWW-Authenticate": 'Basic realm="Wallpaper Gallery"'},
    )


@app.get("/api/status")
def status() -> dict[str, Any]:
    config = load_config()
    return {
        "status": "ok",
        "libraryRoot": str(config.root_path) if config.library_root else "",
        "manifestExists": config.manifest_path.exists() if config.library_root else False,
        "features": ["rangeStreaming", "staticManifest", "unpackJobs", "thumbnails", "sourceFolderDownloads"],
    }


@app.get("/library.json")
def root_manifest(request: Request) -> dict[str, Any]:
    return api_library(request)


@app.get("/api/library")
def api_library(request: Request) -> dict[str, Any]:
    config = require_config()
    return manifest_for_request(load_manifest(config), request)


@app.get("/api/wallpapers")
def wallpapers(request: Request) -> list[dict[str, Any]]:
    return api_library(request)["items"]


@app.get("/api/wallpapers/{item_id}")
def wallpaper(item_id: str, request: Request) -> dict[str, Any]:
    for item in api_library(request)["items"]:
        if item["id"] == item_id:
            return item
    raise HTTPException(status_code=404, detail="Wallpaper not found")


@app.post("/api/wallpapers/{item_id}/unpack")
def unpack(item_id: str) -> JSONResponse:
    config = require_config()
    try:
        job = unpack_wallpaper(config, item_id)
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    jobs[job["jobId"]] = job
    return JSONResponse(job)


@app.get("/api/wallpapers/{item_id}/download")
def download_source_folder(item_id: str) -> FileResponse:
    config = require_config()
    record = next((item for item in scan_library(config) if item.id == item_id), None)
    if record is None:
        raise HTTPException(status_code=404, detail="Wallpaper not found")
    if not record.source_dir.exists() or not record.source_dir.is_dir():
        raise HTTPException(status_code=404, detail="Wallpaper source folder not found")

    temp_file = tempfile.NamedTemporaryFile(prefix=f"{record.id}-", suffix=".zip", delete=False)
    archive_path = temp_file.name
    temp_file.close()
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        add_directory_to_archive(record.source_dir, archive, record.source_dir.name)
    Path(archive_path).chmod(0o600)

    filename = f"{record.source_dir.name}.zip"
    return FileResponse(
        archive_path,
        filename=filename,
        media_type="application/zip",
        background=BackgroundTask(lambda: Path(archive_path).unlink(missing_ok=True)),
    )


@app.get("/api/jobs/{job_id}")
def job(job_id: str) -> dict[str, Any]:
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    return jobs[job_id]


@app.post("/api/library/rescan")
def rescan() -> dict[str, Any]:
    config = require_config()
    return build_and_write_manifest(config).manifest


@app.get("/files/{relative_path:path}")
def file(relative_path: str) -> FileResponse:
    config = require_config()
    normalized_path = normalize_manifest_relative_path(relative_path)
    if normalized_path not in allowed_file_paths(config):
        raise HTTPException(status_code=403, detail="File is not published by the manifest")
    target = safe_library_path(config.root_path, normalized_path)
    if not target.exists() or not target.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(target)


@app.get("/api/debug/records")
def debug_records() -> list[dict[str, Any]]:
    config = require_config()
    records = scan_library(config)
    return [
        {
            "id": record.id,
            "title": record.title,
            "type": record.type,
            "pkg": str(record.pkg_path) if record.pkg_path else None,
            "assets": [asset.relative_path for asset in record.assets],
        }
        for record in records
    ]


def require_config():
    config = load_config()
    if not config.library_root:
        raise HTTPException(status_code=400, detail="library_root is not configured")
    if not config.root_path.exists():
        raise HTTPException(status_code=400, detail=f"library root does not exist: {config.root_path}")
    return config


def is_api_auth_enabled(config: ServerConfig) -> bool:
    return bool(config.api_username or config.api_password)


def is_authorized(request: Request, config: ServerConfig) -> bool:
    credentials = parse_basic_auth(request.headers.get("authorization", ""))
    if credentials is None:
        return False
    username, password = credentials
    return constant_time_equals(username, config.api_username) and constant_time_equals(password, config.api_password)


def parse_basic_auth(value: str) -> tuple[str, str] | None:
    scheme, _, encoded = value.partition(" ")
    if scheme.lower() != "basic" or not encoded:
        return None
    try:
        decoded = b64decode(encoded, validate=True).decode("utf-8")
    except (Base64Error, UnicodeDecodeError):
        return None
    username, separator, password = decoded.partition(":")
    if not separator:
        return None
    return username, password


def constant_time_equals(value: str, expected: str) -> bool:
    return compare_digest(value.encode("utf-8"), expected.encode("utf-8"))


def safe_library_path(root: Path, relative_path: str) -> Path:
    target = (root / relative_path).resolve()
    try:
        target.relative_to(root.resolve())
    except ValueError as error:
        raise HTTPException(status_code=403, detail="Path escapes library root") from error
    return target


def add_directory_to_archive(directory: Path, archive: zipfile.ZipFile, root_name: str) -> None:
    for path in directory.rglob("*"):
        if path.is_dir():
            continue
        relative = path.relative_to(directory)
        if any(part in {"__pycache__", ".git"} for part in relative.parts):
            continue
        archive.write(path, Path(root_name) / relative)


def allowed_file_paths(config: ServerConfig) -> set[str]:
    manifest = load_manifest(config)
    allowed: set[str] = set()
    for item in manifest.get("items", []):
        add_manifest_file_path(allowed, item.get("thumbnail"))
        for asset in item.get("assets", []):
            add_manifest_file_path(allowed, asset.get("url"))
    return allowed


def add_manifest_file_path(allowed: set[str], value: Any) -> None:
    if not isinstance(value, str) or not value:
        return
    parsed = urlparse(value)
    path = parsed.path if parsed.scheme or parsed.netloc else value
    if not path.startswith("/files/"):
        return
    allowed.add(normalize_manifest_relative_path(path.removeprefix("/files/")))


def normalize_manifest_relative_path(value: str) -> str:
    return unquote(value).replace("\\", "/").lstrip("/")


def manifest_for_request(manifest: dict[str, Any], request: Request) -> dict[str, Any]:
    base_url = str(request.base_url).rstrip("/")
    rewritten = dict(manifest)
    rewritten["apiBaseURL"] = base_url
    rewritten["items"] = [
        item_for_request(item, base_url)
        for item in manifest.get("items", [])
    ]
    return rewritten


def item_for_request(item: dict[str, Any], base_url: str) -> dict[str, Any]:
    rewritten = dict(item)
    rewritten["thumbnail"] = rewrite_file_url(item.get("thumbnail"), base_url)
    rewritten["assets"] = [
        asset_for_request(asset, base_url)
        for asset in item.get("assets", [])
    ]
    return rewritten


def asset_for_request(asset: dict[str, Any], base_url: str) -> dict[str, Any]:
    rewritten = dict(asset)
    rewritten["url"] = rewrite_file_url(asset.get("url"), base_url)
    return rewritten


def rewrite_file_url(value: Any, base_url: str) -> Any:
    if not isinstance(value, str) or not value:
        return value
    if value.startswith("/files/"):
        return value
    parsed = urlparse(value)
    if parsed.path.startswith("/files/"):
        return urlunparse(("", "", parsed.path, "", parsed.query, parsed.fragment))
    return value
