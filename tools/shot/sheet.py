"""build/shots の画像を種類ごとに並べて sheet_<種類>.png にする（Pillowが要る）。"""
import collections
import pathlib
import sys

from PIL import Image

out = pathlib.Path(sys.argv[1])
groups = collections.defaultdict(list)
for f in sorted(out.glob("*.png")):
    if not f.name.startswith("sheet_"):
        groups[f.stem.split("_", 1)[0]].append(f)
for name, files in groups.items():
    ims = [Image.open(f).convert("RGB") for f in files]
    w, h = 480, 270
    cols = 4 if len(ims) > 4 else 2
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (w * cols, h * rows))
    for i, im in enumerate(ims):
        sheet.paste(im.resize((w, h)), ((i % cols) * w, (i // cols) * h))
    sheet.save(out / f"sheet_{name}.png")
    print(out / f"sheet_{name}.png")
