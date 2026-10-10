#!/bin/bash
# Build AppIcon.icns from a selected candidate PNG.
#
# macOS icon grid: the icon body occupies 824x824 of a 1024x1024 canvas, with
# transparent margin around it, and the body's corners use the system
# continuous-corner radius (~22.37% of the side).
#
# Usage: scripts/make-icon.sh [source.png] [out.icns]
#   ICON_MARGIN (default 1.03) is the padding kept around the detected artwork.
#   Values near 1.0 fill the icon body; larger values leave more background.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$ROOT/icons/selected.png}"
OUT="${2:-$ROOT/icons/AppIcon.icns}"
MARGIN="${ICON_MARGIN:-1.03}"
PY="${DSH_PYTHON:-/Users/thomas/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3}"

[ -f "$SRC" ] || { echo "source not found: $SRC" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

"$PY" - "$SRC" "$WORK/master.png" "$MARGIN" <<'PY'
import sys
import numpy as np
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
CANVAS, BODY = 1024, 824
MARGIN = float(sys.argv[3])   # padding around the detected artwork, as a multiple of its size
SS = 4                        # supersampling factor for the corner mask

im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(int)

# Treat the near-uniform border colour as background.
bg = a[4, 4]
mask = np.abs(a - bg).sum(axis=2) > 18
ys, xs = np.where(mask)
if len(xs) == 0:
    raise SystemExit("could not detect artwork bounds")

cx = (xs.min() + xs.max()) / 2.0
cy = (ys.min() + ys.max()) / 2.0
side = max(xs.max() - xs.min(), ys.max() - ys.min()) * MARGIN
half = side / 2.0

left, top = int(round(cx - half)), int(round(cy - half))
right, bottom = int(round(cx + half)), int(round(cy + half))
# Clamp while keeping a square window, so the artwork is never distorted.
if left < 0:
    right -= left; left = 0
if top < 0:
    bottom -= top; top = 0
if right > im.width:
    left -= right - im.width; right = im.width
if bottom > im.height:
    top -= bottom - im.height; bottom = im.height
left, top = max(left, 0), max(top, 0)

body = im.crop((left, top, right, bottom)).resize((BODY, BODY), Image.LANCZOS)

# Continuous-corner ("squircle") mask, drawn large and downsampled for clean edges.
radius = int(round(BODY * 0.2237))
big = BODY * SS
m = Image.new("L", (big, big), 0)
ImageDraw.Draw(m).rounded_rectangle((0, 0, big - 1, big - 1), radius=radius * SS, fill=255)
m = m.resize((BODY, BODY), Image.LANCZOS)

canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
off = (CANVAS - BODY) // 2
canvas.paste(body, (off, off), m)
canvas.save(out)
print(f"artwork crop {left},{top},{right},{bottom} -> icon body {BODY}px on {CANVAS}px canvas")
PY

# Standard macOS iconset: each logical size at 1x and 2x.
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/master.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    dbl=$((size * 2))
    sips -z "$dbl" "$dbl" "$WORK/master.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
