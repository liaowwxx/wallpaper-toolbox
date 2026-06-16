from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
from urllib.parse import quote
import json
import shutil
import subprocess
import uuid

from PIL import Image, ImageOps

from . import __version__
from .config import ServerConfig
from .models import (
    IMAGE_EXTENSIONS,
    MEDIA_SKIP_DIRS,
    PREVIEW_NAMES,
    SKIP_DIRS,
    AssetInfo,
    WallpaperRecord,
    kind_for_path,
    read_project_info,
    stable_id,
)


THUMBNAIL_GENERATOR_VERSION = "2"


@dataclass
class BuildResult:
    manifest: dict[str, Any]
    records: list[WallpaperRecord]


def build_and_write_manifest(config: ServerConfig) -> BuildResult:
    records = scan_library(config)
    manifest = build_manifest(config, records)
    config.root_path.mkdir(parents=True, exist_ok=True)
    config.manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return BuildResult(manifest=manifest, records=records)


def load_manifest(config: ServerConfig) -> dict[str, Any]:
    if not config.manifest_path.exists():
        return build_and_write_manifest(config).manifest
    return json.loads(config.manifest_path.read_text(encoding="utf-8"))


def scan_library(config: ServerConfig) -> list[WallpaperRecord]:
    root = config.root_path
    if not root.exists():
        return []

    config.thumbs_path.mkdir(parents=True, exist_ok=True)
    config.extracted_path.mkdir(parents=True, exist_ok=True)

    records: list[WallpaperRecord] = []
    for entry in sorted(root.iterdir(), key=lambda path: path.name.lower()):
        if not entry.is_dir() or entry.name in SKIP_DIRS:
            continue

        record = scan_wallpaper_directory(config, entry)
        if record:
            records.append(record)

    return records


def scan_wallpaper_directory(config: ServerConfig, directory: Path) -> Optional[WallpaperRecord]:
    root = config.root_path
    project = read_project_info(directory)
    relative_dir = directory.relative_to(root).as_posix()
    item_id = stable_id(relative_dir)

    preview = find_preview(directory)
    pkg = next(directory.glob("*.pkg"), None)
    direct_assets = scan_media_assets(root, directory, item_id, prefix="source")
    extracted_dir = config.extracted_path / item_id
    extracted_assets = scan_media_assets(root, extracted_dir, item_id, prefix="extracted") if extracted_dir.exists() else []

    inferred_type = project.type or infer_type(pkg, direct_assets, extracted_assets)
    title = project.title or directory.name

    if pkg is None and preview is None and not direct_assets and not extracted_assets:
        return None

    thumbnail_source = preview or first_asset_path(root, direct_assets) or first_asset_path(root, extracted_assets)
    thumbnail_relative = generate_thumbnail(config, item_id, thumbnail_source) if thumbnail_source else None

    assets = choose_visible_assets(
        wallpaper_type=inferred_type,
        has_pkg=pkg is not None,
        direct_assets=direct_assets,
        extracted_assets=extracted_assets,
    )
    return WallpaperRecord(
        id=item_id,
        title=title,
        type=inferred_type,
        source_dir=directory,
        relative_dir=relative_dir,
        pkg_path=pkg,
        preview_path=preview,
        thumbnail_relative_path=thumbnail_relative,
        is_unpacked=bool(extracted_assets) or (inferred_type == "video" and bool(direct_assets)),
        content_rating=project.content_rating,
        tags=project.tags,
        collections=project.collections,
        assets=assets,
    )


def build_manifest(config: ServerConfig, records: list[WallpaperRecord]) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "serverVersion": f"windows-demo-{__version__}",
        "generatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "apiBaseURL": config.normalized_public_api_base_url or None,
        "features": ["rangeStreaming", "staticManifest", "unpackJobs", "thumbnails"],
        "items": [record_to_manifest(config, record) for record in records],
    }


def record_to_manifest(config: ServerConfig, record: WallpaperRecord) -> dict[str, Any]:
    thumbnail_url = public_url(config, record.thumbnail_relative_path) if record.thumbnail_relative_path else None
    assets = [
        asset.to_manifest(public_url(config, asset.relative_path))
        for asset in record.assets
    ]
    return record.to_manifest(thumbnail_url, assets)


def unpack_wallpaper(config: ServerConfig, item_id: str) -> dict[str, Any]:
    records = scan_library(config)
    record = next((item for item in records if item.id == item_id), None)
    if record is None:
        raise ValueError(f"Unknown wallpaper id: {item_id}")
    if record.pkg_path is None:
        return make_job(item_id, "done", "No package found; nothing to unpack.")

    output_dir = config.extracted_path / record.id
    output_dir.mkdir(parents=True, exist_ok=True)

    command = [
        config.repkg_path,
        "extract",
        "-o",
        str(output_dir),
        "-s",
        "--overwrite",
        str(record.pkg_path),
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "RePKG failed").strip()
        return make_job(item_id, "failed", message[-1000:])

    build_and_write_manifest(config)
    return make_job(item_id, "done", "Package unpacked and library.json regenerated.")


def make_job(item_id: str, state: str, message: str) -> dict[str, Any]:
    return {
        "jobId": str(uuid.uuid4()),
        "itemId": item_id,
        "state": state,
        "message": message,
    }


def find_preview(directory: Path) -> Optional[Path]:
    for name in PREVIEW_NAMES:
        candidate = directory / name
        if candidate.exists():
            return candidate
    return None


def infer_type(pkg: Optional[Path], direct_assets: list[AssetInfo], extracted_assets: list[AssetInfo]) -> str:
    assets = direct_assets or extracted_assets
    if assets and all(asset.kind == "video" for asset in assets):
        return "video"
    if assets and all(asset.kind == "image" for asset in assets):
        return "image"
    if pkg:
        return "pkg"
    return "unknown"


def choose_visible_assets(
    wallpaper_type: str,
    has_pkg: bool,
    direct_assets: list[AssetInfo],
    extracted_assets: list[AssetInfo],
) -> list[AssetInfo]:
    if extracted_assets:
        return extracted_assets
    if wallpaper_type == "video" and direct_assets:
        return direct_assets
    if has_pkg:
        return []
    return direct_assets


def scan_media_assets(root: Path, directory: Path, item_id: str, prefix: str) -> list[AssetInfo]:
    if not directory.exists():
        return []

    assets: list[AssetInfo] = []
    for path in sorted(directory.rglob("*"), key=lambda item: item.as_posix().lower()):
        if not path.is_file():
            continue
        if prefix == "source" and path.name.lower() in PREVIEW_NAMES:
            continue
        if any(part in MEDIA_SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        kind = kind_for_path(path)
        if kind is None:
            continue
        relative_path = path.relative_to(root).as_posix()
        assets.append(
            AssetInfo(
                id=f"{item_id}-{prefix}-{len(assets)}",
                name=path.name,
                kind=kind,
                relative_path=relative_path,
                size=path.stat().st_size,
            )
        )
    return assets


def first_asset_path(root: Path, assets: list[AssetInfo]) -> Optional[Path]:
    if not assets:
        return None
    return root / assets[0].relative_path


def generate_thumbnail(config: ServerConfig, item_id: str, source: Path) -> Optional[str]:
    output = config.thumbs_path / f"{item_id}.jpg"
    version_path = output.with_suffix(".version")
    if (
        output.exists()
        and output.stat().st_mtime >= source.stat().st_mtime
        and version_path.exists()
        and version_path.read_text(encoding="utf-8").strip() == THUMBNAIL_GENERATOR_VERSION
    ):
        return output.relative_to(config.root_path).as_posix()

    if source.suffix.lower() in IMAGE_EXTENSIONS:
        if generate_image_thumbnail(source, output):
            version_path.write_text(THUMBNAIL_GENERATOR_VERSION, encoding="utf-8")
            return output.relative_to(config.root_path).as_posix()

    if generate_video_thumbnail(config, source, output):
        version_path.write_text(THUMBNAIL_GENERATOR_VERSION, encoding="utf-8")
        return output.relative_to(config.root_path).as_posix()

    return None


def generate_image_thumbnail(source: Path, output: Path) -> bool:
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(source) as image:
            try:
                image.seek(0)
            except EOFError:
                pass
            image = ImageOps.exif_transpose(image)
            if image.mode in ("RGBA", "LA") or "transparency" in image.info:
                image = image.convert("RGBA")
                background = Image.new("RGBA", image.size, (24, 24, 28, 255))
                background.alpha_composite(image)
                image = background.convert("RGB")
            else:
                image = image.convert("RGB")
            thumbnail = ImageOps.fit(image, (512, 512), method=Image.Resampling.LANCZOS)
            thumbnail.save(output, "JPEG", quality=86, optimize=True)
        return True
    except Exception:
        return False


def generate_video_thumbnail(config: ServerConfig, source: Path, output: Path) -> bool:
    if not shutil.which(config.ffmpeg_path) and not Path(config.ffmpeg_path).exists():
        return False
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        config.ffmpeg_path,
        "-y",
        "-ss",
        "00:00:01",
        "-i",
        str(source),
        "-frames:v",
        "1",
        "-vf",
        "scale=512:512:force_original_aspect_ratio=decrease,pad=512:512:(ow-iw)/2:(oh-ih)/2",
        str(output),
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    return result.returncode == 0 and output.exists()


def public_url(config: ServerConfig, relative_path: Optional[str]) -> str:
    if not relative_path:
        return ""
    encoded = "/".join(quote(part) for part in relative_path.replace("\\", "/").split("/"))
    if config.normalized_public_static_base_url:
        return f"{config.normalized_public_static_base_url}/{encoded}"
    return f"/files/{encoded}"
