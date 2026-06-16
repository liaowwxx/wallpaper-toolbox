from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Optional
import json
import os


CONFIG_ENV = "WALLPAPER_SERVER_CONFIG"
DEFAULT_CONFIG_PATH = Path("server-config.json")


@dataclass
class ServerConfig:
    library_root: str = ""
    repkg_path: str = "RePKG.exe"
    ffmpeg_path: str = "ffmpeg"
    api_host: str = "0.0.0.0"
    api_port: int = 8090
    api_username: str = ""
    api_password: str = ""
    public_api_base_url: str = "http://localhost:8090"
    public_static_base_url: str = ""
    miniserve_path: str = "miniserve.exe"
    miniserve_port: int = 8080
    miniserve_auth: str = ""

    @property
    def root_path(self) -> Path:
        return Path(self.library_root).expanduser().resolve()

    @property
    def thumbs_path(self) -> Path:
        return self.root_path / "thumbs"

    @property
    def extracted_path(self) -> Path:
        return self.root_path / "extracted"

    @property
    def manifest_path(self) -> Path:
        return self.root_path / "library.json"

    @property
    def normalized_public_api_base_url(self) -> str:
        return self.public_api_base_url.rstrip("/")

    @property
    def normalized_public_static_base_url(self) -> str:
        return self.public_static_base_url.rstrip("/")


def config_path() -> Path:
    return Path(os.environ.get(CONFIG_ENV, DEFAULT_CONFIG_PATH)).expanduser().resolve()


def load_config(path: Optional[Path] = None) -> ServerConfig:
    path = path or config_path()
    if not path.exists():
        return ServerConfig()
    raw = json.loads(path.read_text(encoding="utf-8"))
    allowed = {field.name for field in ServerConfig.__dataclass_fields__.values()}
    return ServerConfig(**{key: value for key, value in raw.items() if key in allowed})


def save_config(config: ServerConfig, path: Optional[Path] = None) -> Path:
    path = path or config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(config), indent=2), encoding="utf-8")
    return path
