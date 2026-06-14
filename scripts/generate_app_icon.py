#!/usr/bin/env python3
import argparse
import io
import struct
from collections import deque
from pathlib import Path

from PIL import Image


ICNS_TYPES = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 64),
    ("ic12", 256),
    ("ic13", 512),
    ("ic14", 1024),
]


def remove_border_background(image: Image.Image, threshold: int) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    queue: deque[tuple[int, int]] = deque()
    seen: set[tuple[int, int]] = set()

    def is_background(x: int, y: int) -> bool:
        r, g, b, _ = pixels[x, y]
        return r <= threshold and g <= threshold and b <= threshold

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or not (0 <= x < width and 0 <= y < height):
            continue
        seen.add((x, y))
        if not is_background(x, y):
            continue
        pixels[x, y] = (0, 0, 0, 0)
        queue.append((x + 1, y))
        queue.append((x - 1, y))
        queue.append((x, y + 1))
        queue.append((x, y - 1))

    return rgba


def fit_square(image: Image.Image, size: int) -> Image.Image:
    image.thumbnail((size, size), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - image.width) // 2
    y = (size - image.height) // 2
    canvas.alpha_composite(image, (x, y))
    return canvas


def write_icns(master: Image.Image, path: Path) -> None:
    entries: list[tuple[bytes, bytes]] = []
    for icon_type, size in ICNS_TYPES:
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        buffer = io.BytesIO()
        resized.save(buffer, format="PNG")
        entries.append((icon_type.encode("ascii"), buffer.getvalue()))

    total_length = 8 + sum(8 + len(data) for _, data in entries)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(b"icns")
        handle.write(struct.pack(">I", total_length))
        for icon_type, data in entries:
            handle.write(icon_type)
            handle.write(struct.pack(">I", 8 + len(data)))
            handle.write(data)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate macOS PNG and ICNS app icon assets.")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--png", required=True, type=Path)
    parser.add_argument("--icns", required=True, type=Path)
    parser.add_argument("--threshold", type=int, default=28)
    args = parser.parse_args()

    source = Image.open(args.input)
    cleaned = remove_border_background(source, args.threshold)
    master = fit_square(cleaned, 1024)

    args.png.parent.mkdir(parents=True, exist_ok=True)
    master.save(args.png)
    write_icns(master, args.icns)


if __name__ == "__main__":
    main()
