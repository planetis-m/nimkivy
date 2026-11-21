"""Make the test images the reference scenes use (deterministic, with Pillow).

Run from nimkivy/:
    <kiosk>/.venv/bin/python reference/make_assets.py
"""

import math
import struct
import wave
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent / "assets"


def grid(w, h, a, b, step):
    """A two-colour checker of w x h with a diagonal, so scaling and flips are visible."""
    im = Image.new("RGBA", (w, h), a)
    d = ImageDraw.Draw(im)
    for y in range(0, h, step):
        for x in range(0, w, step):
            if (x // step + y // step) % 2:
                d.rectangle([x, y, x + step - 1, y + step - 1], fill=b)
    d.line([0, 0, w - 1, h - 1], fill=(0, 0, 0, 255), width=3)
    d.rectangle([0, 0, w // 6, h // 6], fill=(220, 30, 30, 255))  # marks the top-left corner
    return im


def main():
    OUT.mkdir(exist_ok=True)
    grid(400, 200, (240, 200, 80, 255), (60, 120, 200, 255), 25).save(OUT / "landscape.png")
    grid(100, 200, (90, 180, 90, 255), (250, 250, 250, 255), 20).save(OUT / "portrait.png")
    grid(40, 30, (200, 90, 160, 255), (30, 30, 30, 255), 10).save(OUT / "small.png")
    grid(400, 200, (240, 200, 80, 255), (60, 120, 200, 255), 25).convert("RGB").save(
        OUT / "landscape.jpg", quality=92)
    # Semi-transparent round "flag" like the kiosk's circle flags.
    flag = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(flag)
    d.ellipse([0, 0, 127, 127], fill=(0, 90, 170, 255))
    d.rectangle([0, 52, 127, 75], fill=(255, 255, 255, 255))
    d.rectangle([52, 0, 75, 127], fill=(255, 255, 255, 255))
    flag.save(OUT / "flag.png")
    half = Image.new("RGBA", (64, 64), (200, 40, 40, 128))
    half.save(OUT / "half_alpha.png")
    # 1.402 s of a 440 Hz tone: the length of Kivy's tests/sample1.ogg, for the ported test_audio.
    rate, n = 44100, round(44100 * 1.402)
    with wave.open(str(OUT / "tone.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / rate)))
                               for i in range(n)))


if __name__ == "__main__":
    main()
