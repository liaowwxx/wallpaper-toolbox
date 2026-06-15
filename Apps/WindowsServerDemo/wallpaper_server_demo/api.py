from __future__ import annotations

from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse

from .config import load_config
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


@app.get("/api/status")
def status() -> dict[str, Any]:
    config = load_config()
    return {
        "status": "ok",
        "libraryRoot": str(config.root_path) if config.library_root else "",
        "manifestExists": config.manifest_path.exists() if config.library_root else False,
        "features": ["rangeStreaming", "staticManifest", "unpackJobs", "thumbnails"],
    }


@app.get("/library.json")
def root_manifest() -> dict[str, Any]:
    return api_library()


@app.get("/api/library")
def api_library() -> dict[str, Any]:
    config = require_config()
    return load_manifest(config)


@app.get("/api/wallpapers")
def wallpapers() -> list[dict[str, Any]]:
    return api_library()["items"]


@app.get("/api/wallpapers/{item_id}")
def wallpaper(item_id: str) -> dict[str, Any]:
    for item in api_library()["items"]:
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
    target = safe_library_path(config.root_path, relative_path)
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


def safe_library_path(root: Path, relative_path: str) -> Path:
    target = (root / relative_path).resolve()
    try:
        target.relative_to(root.resolve())
    except ValueError as error:
        raise HTTPException(status_code=403, detail="Path escapes library root") from error
    return target
