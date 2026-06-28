from __future__ import annotations

from base64 import b64encode
from pathlib import Path
from typing import Any
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

from .config import CONFIG_ENV, ServerConfig, load_config
from .library import build_and_write_manifest, scan_library


def main() -> int:
    parser = argparse.ArgumentParser(description="Bridge commands for the Tauri desktop shell.")
    parser.add_argument("command", choices=["generate-manifest", "scan-preview", "rescan-api"])
    parser.add_argument("config_path")
    args = parser.parse_args()

    os.environ[CONFIG_ENV] = str(Path(args.config_path).expanduser().resolve())
    config = load_config()

    if args.command == "generate-manifest":
        output(generate_manifest(config))
        return 0
    if args.command == "scan-preview":
        output(scan_preview(config))
        return 0
    if args.command == "rescan-api":
        output(rescan_api(config))
        return 0
    return 1


def generate_manifest(config: ServerConfig) -> dict[str, Any]:
    result = build_and_write_manifest(config)
    return {
        "ok": True,
        "count": len(result.records),
        "manifestPath": str(config.manifest_path),
    }


def scan_preview(config: ServerConfig) -> dict[str, Any]:
    records = scan_library(config)
    return {
        "ok": True,
        "count": len(records),
        "manifestPath": str(config.manifest_path),
        "items": [
            {
                "id": record.id,
                "title": record.title,
                "type": record.type,
                "thumbnailPath": str(config.root_path / record.thumbnail_relative_path)
                if record.thumbnail_relative_path
                else "",
                "assetCount": len(record.assets),
                "hasPackage": record.pkg_path is not None,
                "isUnpacked": record.is_unpacked,
            }
            for record in records[:120]
        ],
    }


def rescan_api(config: ServerConfig) -> dict[str, Any]:
    url = f"{config.normalized_public_api_base_url}/api/library/rescan"
    request = urllib.request.Request(url, method="POST")
    apply_api_auth(request, config)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return {"ok": True, "status": response.status}
    except urllib.error.URLError as error:
        return {"ok": False, "error": str(error)}


def apply_api_auth(request: urllib.request.Request, config: ServerConfig) -> None:
    if not config.api_username and not config.api_password:
        return
    token = b64encode(f"{config.api_username}:{config.api_password}".encode("utf-8")).decode("ascii")
    request.add_header("Authorization", f"Basic {token}")


def output(payload: dict[str, Any]) -> None:
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    raise SystemExit(main())
