"""models/hand.glb（Meshy製、骨なし）を解析し、関節の位置と頂点ごとの骨を tools/rig/rig.json に書き出す。
次に build_hand.tscn を実行すると、骨入りの models/hand_rigged.scn ができる。

    pip install numpy scipy
    python3 tools/rig/analyze_hand.py
    godot --headless --path . res://tools/rig/build_hand.tscn

やり方：
- 形の主成分で座標を取る。t：指先(-)→前腕(+)、u：小指(-)→親指(+)、s：手のひら(-)→手の甲(+)
- 4本の指は付け根の高さから指先へ輪切りにして中心線をとり、長さの45%・75%を関節にする
- 親指は手のひらの縁より外の頂点の主軸から付け根・関節・先を決める
- 頂点は一番近い骨の線分に割り当てる。メカの手は部品が分かれているので、
  8割以上が同じ骨の部品は部品ごとその骨に固定する（重みはすべて1）
数値はこのモデル用に合わせてある。別のモデルでは FINGERS の位置などを見直す。
"""
import json
import os
import struct

import numpy as np
import scipy.sparse as sp
from scipy.sparse.csgraph import connected_components

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = os.path.join(ROOT, "models", "hand.glb")
OUT = os.path.join(os.path.dirname(__file__), "rig.json")

# 指の名前、付け根でのuの位置、付け根のtの位置
FINGERS = [("index", 0.17, -0.67), ("middle", -0.04, -0.68), ("ring", -0.22, -0.66), ("pinky", -0.36, -0.60)]
JOINT_AT = [0.0, 0.45, 0.75, 1.0]  # 指の長さに対する関節の位置
RADIUS = {"index": 0.085, "middle": 0.085, "ring": 0.085, "pinky": 0.075, "thumb": 0.11}
BONES = ["hand"] + ["%s_%d" % (f, i) for f in ["index", "middle", "ring", "pinky", "thumb"] for i in (1, 2, 3)]


def load_glb(path):
    d = open(path, "rb").read()
    ln = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + ln])
    off = 20 + ln
    binc = d[off + 8:off + 8 + struct.unpack("<I", d[off:off + 4])[0]]
    types = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}
    sizes = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        n = sizes[a["type"]]
        arr = np.frombuffer(binc, dtype=types[a["componentType"]], count=a["count"] * n,
                            offset=bv.get("byteOffset", 0) + a.get("byteOffset", 0))
        return arr.reshape(-1, n) if n > 1 else arr

    p = j["meshes"][0]["primitives"][0]
    return acc(p["attributes"]["POSITION"]).astype(np.float64), acc(p["indices"]).reshape(-1, 3).astype(np.int64)


def seg_dist(x, p, q):
    d = q - p
    r = np.clip(((x - p) @ d) / (d @ d), 0, 1)
    return np.linalg.norm(x - (p + np.outer(r, d)), axis=1)


def main():
    P, F = load_glb(SRC)
    n = len(P)
    adj = sp.coo_matrix((np.ones(F.size), (F.T.ravel(), F[:, [1, 2, 0]].T.ravel())), shape=(n, n))
    k, lab = connected_components(adj, directed=False)

    c = P.mean(0)
    _, v = np.linalg.eigh(np.cov((P - c).T))
    a, b, cc = v[:, 2], v[:, 1], v[:, 0]
    t, u, s = (P - c) @ a, (P - c) @ b, (P - c) @ cc
    L = np.stack([t, u, s], 1)

    def to_model(q):
        return list(c + q[0] * a + q[1] * b + q[2] * cc)

    out = {}
    for name, cu, base_t in FINGERS:
        pts, cur = [], cu
        tip_t = t[np.abs(u - cu) < 0.08].min()
        for tt in np.arange(base_t, tip_t, -0.02):
            m = (t <= tt) & (t > tt - 0.03) & (np.abs(u - cur) < 0.065)
            if m.sum() < 20:
                break
            cur = u[m].mean()
            pts.append((tt - 0.015, cur, (s[m].max() + s[m].min()) / 2))
        pts = np.array(pts)
        poly = np.vstack([pts, [tip_t, pts[-1, 1], pts[-1, 2]]])
        seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
        cum = np.concatenate([[0], np.cumsum(seg)])

        def at(f):
            dd = f * cum[-1]
            i = np.clip(np.searchsorted(cum, dd) - 1, 0, len(seg) - 1)
            return poly[i] + (poly[i + 1] - poly[i]) * ((dd - cum[i]) / seg[i])

        out[name] = [to_model(at(f)) for f in JOINT_AT]

    # 親指
    m = (u > 0.27) & (t < -0.3) & (t > -1.0)
    Q = L[m]
    qc = Q.mean(0)
    _, qv = np.linalg.eigh(np.cov((Q - qc).T))
    ax = qv[:, 2] if qv[1, 2] > 0 else -qv[:, 2]
    pr = (Q - qc) @ ax
    tip, base = Q[np.argmax(pr)], qc + ax * pr.min()
    cmc = base - ax * np.linalg.norm(tip - base) * 0.45

    def thumb_pt(f):
        p = base + (tip - base) * f
        rel = Q - p
        near = (np.linalg.norm(rel - np.outer(rel @ ax, ax), axis=1) < 0.09) & (np.abs(rel @ ax) < 0.03)
        if near.sum() > 10:
            cen = Q[near].mean(0)
            return p + (cen - p) - ax * ((cen - p) @ ax)
        return p

    out["thumb"] = [to_model(q) for q in [cmc, thumb_pt(0.0), thumb_pt(0.5), tip]]
    mm = np.abs(t) < 0.03
    out["wrist"] = to_model([0.0, u[mm].mean(), (s[mm].max() + s[mm].min()) / 2])
    out["frame"] = {"c": list(c), "a": list(a), "b": list(b), "cc": list(cc)}

    # 頂点ごとの骨
    J = {f: [np.array(x) for x in out[f]] for f in ["index", "middle", "ring", "pinky", "thumb"]}
    bone = np.zeros(n, int)
    best = np.full(n, np.inf)
    for f, j in J.items():
        for i in range(3):
            dist = seg_dist(P, j[i], j[i + 1])
            ok = dist < RADIUS[f]
            if f != "thumb":
                ok &= t < (j[0] - c) @ a + 0.01  # 付け根より手首側は手のひら
            elif i == 0:
                ok &= u > 0.21  # 親指の付け根の骨は手のひらの縁より外だけ
            m = ok & (dist < best)
            bone[m] = BONES.index("%s_%d" % (f, i + 1))
            best[m] = dist[m]
    # 指の付け根より先にあるのに手のひらに残った頂点（指の甲側の細い部品など）は一番近い指の骨へ
    rest = np.where(bone == 0)[0]
    bestd = np.full(len(rest), np.inf)
    bestb = np.zeros(len(rest), int)
    for f in ["index", "middle", "ring", "pinky"]:
        j = J[f]
        for i in range(3):
            dist = seg_dist(P[rest], j[i], j[i + 1])
            ok = (t[rest] < (j[0] - c) @ a - 0.02) & (dist < bestd)
            bestd[ok] = dist[ok]
            bestb[ok] = BONES.index("%s_%d" % (f, i + 1))
    sel = np.isfinite(bestd) & (bestd < 0.2)
    bone[rest[sel]] = bestb[sel]
    # 部品ごとの多数決
    for comp in range(k):
        m = lab == comp
        cnt = np.bincount(bone[m], minlength=len(BONES))
        if cnt.max() >= 0.8 * m.sum():
            bone[m] = cnt.argmax()
    # 手のひらに残った小さな部品で、重心が指の付け根より先にあるものは近い指の根元の骨へ
    for comp in range(k):
        m = lab == comp
        if bone[m][0] != 0 or m.sum() > 500:
            continue
        cen = P[m].mean(0)
        f = min(["index", "middle", "ring", "pinky"], key=lambda f: abs((J[f][0] - c) @ b - (cen - c) @ b))
        if (cen - c) @ a < (J[f][0] - c) @ a:
            bone[m] = BONES.index(f + "_1")

    print({name: int((bone == i).sum()) for i, name in enumerate(BONES)})
    keys = {"%.4f,%.4f,%.4f" % tuple(p): int(bi) for p, bi in zip(P, bone)}
    json.dump({"joints": out, "bones": BONES, "map": keys}, open(OUT, "w"))
    print("書き出し", OUT)


if __name__ == "__main__":
    main()
