"""Compare nimkivy's scene and trace output with Kivy's (reference/out).

Run from nimkivy/:
    <kiosk>/.venv/bin/python reference/compare.py tests/out [scene ...]
    <kiosk>/.venv/bin/python reference/compare.py tests/out --traces [trace ...]
    <kiosk>/.venv/bin/python reference/compare.py tests/out --pixels scene ...

For each scene: <scene>.txt (widget geometry) must be equal line for line; <scene>.png may
differ in at most BUDGET of its pixels by more than TOLERANCE in any channel (rasterization,
glyph and JPEG differences, see the GAPs in PORTING.md). Traces must be equal line for line.
Writes <out>/diff/<scene>.png (differing pixels in red) for every scene over budget.
--pixels compares only the .png, for the scenes drawn before Widget exists (layers 3 to 5),
which have no geometry yet. Exit status 1 if anything fails.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops

REF = Path(__file__).resolve().parent / "out"
TOLERANCE = 24  # per channel, 0..255
BUDGET = {"default": 0.005, "label": 0.03, "msaa": 0.03, "jpg": 0.01}


def budget(scene):
    if scene.startswith("label") or scene.startswith("modal"):
        return BUDGET["label"]
    if scene.endswith("_msaa"):
        return BUDGET["msaa"]
    if scene in ("graphics_texture", "image_misc"):
        return BUDGET["jpg"]
    return BUDGET["default"]


def known_diffs():
    """(scene, kivy line, nimkivy line) triples listed in known-geometry-diffs.txt."""
    known = set()
    for line in (REF.parent / "known-geometry-diffs.txt").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            known.add(tuple(part.strip() for part in line.split(" | ")))
    return known


def compare_text(ref, got):
    if not got.exists():
        return f"missing {got}"
    a, b = ref.read_text().splitlines(), got.read_text().splitlines()
    known = known_diffs()
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y and (ref.stem, x, y) not in known:
            return f"line {i + 1}: kivy {x!r} / nimkivy {y!r}"
    if len(a) != len(b):
        return f"{len(a)} lines in kivy, {len(b)} in nimkivy"
    return None


def compare_png(scene, ref, got, diff_dir):
    if not got.exists():
        return f"missing {got}"
    a, b = Image.open(ref).convert("RGB"), Image.open(got).convert("RGB")
    if a.size != b.size:
        return f"size {a.size} / {b.size}"
    d = ImageChops.difference(a, b)
    mask = Image.eval(d, lambda v: 255 if v > TOLERANCE else 0).convert("L").point(lambda v: 255 if v else 0)
    bad = sum(1 for v in mask.getdata() if v)
    share = bad / (a.size[0] * a.size[1])
    if share > budget(scene):
        diff_dir.mkdir(parents=True, exist_ok=True)
        red = Image.new("RGB", a.size, (255, 0, 0))
        Image.composite(red, a.point(lambda v: v // 3 + 170), mask).save(diff_dir / f"{scene}.png")
        return f"{share:.2%} pixels differ (budget {budget(scene):.2%})"
    return None


def compare_traces(out, names):
    """Compares the named traces (all when none are named); True if all match."""
    ok = True
    refs = [REF / "traces" / f"{n}.txt" for n in names] or sorted((REF / "traces").glob("*.txt"))
    for ref in refs:
        err = compare_text(ref, out / "traces" / ref.name)
        print(f"{'FAIL' if err else 'ok  '} trace {ref.stem}{': ' + err if err else ''}")
        ok = ok and not err
    return ok


def main():
    out = Path(sys.argv[1]).resolve()
    if sys.argv[2:3] == ["--traces"]:
        sys.exit(0 if compare_traces(out, sys.argv[3:]) else 1)
    pixels_only = sys.argv[2:3] == ["--pixels"]
    scenes = sys.argv[3 if pixels_only else 2:] or sorted(p.stem for p in REF.glob("*.png"))
    failed = False
    for scene in scenes:
        checks = [] if pixels_only else [
            ("geometry", compare_text(REF / f"{scene}.txt", out / f"{scene}.txt"))]
        checks.append(("pixels", compare_png(scene, REF / f"{scene}.png", out / f"{scene}.png",
                                             out / "diff")))
        for kind, err in checks:
            print(f"{'FAIL' if err else 'ok  '} {scene} {kind}{': ' + err if err else ''}")
            failed |= bool(err)
    if len(sys.argv) == 2:
        failed |= not compare_traces(out, [])
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
