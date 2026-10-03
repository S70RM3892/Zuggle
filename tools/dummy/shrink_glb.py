"""MeshyのGLBを軽くする：ポリゴンを減らし、テクスチャを縮める。
使い方: python3 tools/dummy/shrink_glb.py 元.glb 出力.glb [三角形の数] [テクスチャの辺(px)]
必要: pip install numpy pillow meshoptimizer
"""
import io
import json
import struct
import sys

import meshoptimizer as mo
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
target_tris = int(sys.argv[3]) if len(sys.argv) > 3 else 40000
tex_size = int(sys.argv[4]) if len(sys.argv) > 4 else 1024

data = open(src, "rb").read()
json_len = struct.unpack("<I", data[12:16])[0]
gltf = json.loads(data[20:20 + json_len])
binary = data[20 + json_len + 8:]


def accessor(i):
    a = gltf["accessors"][i]
    bv = gltf["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a["componentType"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = np.frombuffer(binary, dtype=dt, count=a["count"] * n, offset=off)
    return arr.reshape(-1, n) if n > 1 else arr


prim = gltf["meshes"][0]["primitives"][0]
pos = np.ascontiguousarray(accessor(prim["attributes"]["POSITION"]), dtype=np.float32)
nrm = np.ascontiguousarray(accessor(prim["attributes"]["NORMAL"]), dtype=np.float32)
uv = np.ascontiguousarray(accessor(prim["attributes"]["TEXCOORD_0"]), dtype=np.float32)
idx = np.ascontiguousarray(accessor(prim["indices"]), dtype=np.uint32)

out = np.zeros_like(idx)
err = np.zeros(1, dtype=np.float32)
n = mo.simplify(out, idx, pos, target_index_count=target_tris * 3, target_error=0.02, result_error=err)
out = out[:n]
print(f"三角形 {len(idx) // 3} → {n // 3}（誤差 {err[0]:.4f}）")

# 使われている頂点だけを残す
used, remap = np.unique(out, return_inverse=True)
pos, nrm, uv = pos[used], nrm[used], uv[used]
out = remap.astype(np.uint32)
print(f"頂点 {len(used)}")

images = []
for img in gltf["images"]:
    bv = gltf["bufferViews"][img["bufferView"]]
    raw = binary[bv["byteOffset"]:bv["byteOffset"] + bv["byteLength"]]
    im = Image.open(io.BytesIO(raw)).convert("RGB").resize((tex_size, tex_size), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=88)
    images.append(buf.getvalue())

chunks, views = [], []


def add(raw, target=None):
    off = sum(len(c) for c in chunks)
    chunks.append(raw + b"\0" * ((4 - len(raw) % 4) % 4))
    v = {"buffer": 0, "byteOffset": off, "byteLength": len(raw)}
    if target:
        v["target"] = target
    views.append(v)
    return len(views) - 1


accessors = [
    {"bufferView": add(pos.tobytes(), 34962), "componentType": 5126, "count": len(pos), "type": "VEC3",
     "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
    {"bufferView": add(uv.tobytes(), 34962), "componentType": 5126, "count": len(uv), "type": "VEC2"},
    {"bufferView": add(nrm.tobytes(), 34962), "componentType": 5126, "count": len(nrm), "type": "VEC3"},
    {"bufferView": add(out.tobytes(), 34963), "componentType": 5125, "count": len(out), "type": "SCALAR"},
]
for i, raw in enumerate(images):
    gltf["images"][i] = {"mimeType": "image/jpeg", "bufferView": add(raw)}
gltf["accessors"] = accessors
gltf["bufferViews"] = views
body = b"".join(chunks)
gltf["buffers"] = [{"byteLength": len(body)}]
gltf["asset"] = {"version": "2.0", "generator": "zuggle shrink_glb.py"}
js = json.dumps(gltf, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
total = 12 + 8 + len(js) + 8 + len(body)
with open(dst, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, total))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(body), 0x004E4942) + body)
print(f"{dst}: {total / 1e6:.1f} MB")
