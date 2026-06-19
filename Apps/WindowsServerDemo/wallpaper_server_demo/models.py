from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional
import hashlib
import json
import re


IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".gif",
    ".bmp",
    ".webp",
    ".tiff",
    ".tif",
    ".heic",
    ".heif",
}

VIDEO_EXTENSIONS = {
    ".mp4",
    ".mov",
    ".avi",
    ".mkv",
    ".webm",
    ".m4v",
    ".wmv",
    ".flv",
    ".mpg",
    ".mpeg",
}

PREVIEW_NAMES = ("preview.jpg", "preview.png", "preview.gif", "preview.webp")
SKIP_DIRS = {"thumbs", "extracted", "packages", ".git", "__pycache__"}
MEDIA_SKIP_DIRS = SKIP_DIRS - {"extracted"}


@dataclass
class ProjectInfo:
    title: Optional[str] = None
    type: Optional[str] = None
    file: Optional[str] = None
    content_rating: str = "Everyone"
    tags: list[str] = field(default_factory=list)
    collections: list[str] = field(default_factory=list)


@dataclass
class AssetInfo:
    id: str
    name: str
    kind: str
    relative_path: str
    size: int

    def to_manifest(self, url: str) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "kind": self.kind,
            "url": url,
            "size": self.size,
        }


@dataclass
class WallpaperRecord:
    id: str
    title: str
    type: str
    source_dir: Path
    relative_dir: str
    pkg_path: Optional[Path]
    preview_path: Optional[Path]
    thumbnail_relative_path: Optional[str]
    is_unpacked: bool
    content_rating: str
    tags: list[str]
    collections: list[str]
    assets: list[AssetInfo]

    def to_manifest(self, thumbnail_url: Optional[str], assets: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "id": self.id,
            "title": self.title,
            "type": self.type,
            "relativeDir": self.relative_dir,
            "thumbnail": thumbnail_url,
            "sourceArchive": f"/api/wallpapers/{self.id}/download",
            "isUnpacked": self.is_unpacked,
            "contentRating": self.content_rating,
            "tags": self.tags,
            "collections": self.collections,
            "assets": assets,
        }


def read_project_info(directory: Path) -> ProjectInfo:
    project_path = directory / "project.json"
    if not project_path.exists():
        return ProjectInfo()
    try:
        data = json.loads(project_path.read_text(encoding="utf-8-sig"))
    except Exception:
        return ProjectInfo()

    tags = data.get("preview_tagger") or data.get("tags") or []
    collections = data.get("repkgcollection") or data.get("collections") or []

    return ProjectInfo(
        title=data.get("title"),
        type=(data.get("type") or "").lower() or None,
        file=data.get("file"),
        content_rating=normalize_content_rating(data.get("contentrating") or data.get("contentRating")),
        tags=[str(tag) for tag in tags if str(tag).strip()],
        collections=[str(item) for item in collections if str(item).strip()],
    )


def normalize_content_rating(value: Any) -> str:
    normalized = str(value or "Everyone").strip().lower()
    if normalized == "mature":
        return "Mature"
    if normalized == "questionable":
        return "Questionable"
    return "Everyone"


def stable_id(relative_dir: str) -> str:
    cleaned = sanitize(relative_dir.replace("\\", "/").strip("/"))
    if cleaned:
        return cleaned
    return hashlib.sha1(relative_dir.encode("utf-8")).hexdigest()[:12]


def sanitize(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-._")
    return value[:80]


def kind_for_path(path: Path) -> Optional[str]:
    ext = path.suffix.lower()
    if ext in IMAGE_EXTENSIONS:
        return "image"
    if ext in VIDEO_EXTENSIONS:
        return "video"
    return None
