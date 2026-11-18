#!/usr/bin/env python3
"""Offline "scan" step of the face-scan pipeline (docs/face_scans/README.md).

Takes a multiview reconstruction of a head (a raw GLB) and the capture photos it was made from, and
turns them into a game-ready head:

  1. orient the raw mesh (+Y up, +Z = face), decimate it to the in-game budget and unwrap it (xatlas)
  2. fit one camera per capture photo: its nominal angle is known (front, +-30, +-60, +-90, back, above,
     below), the zoom, offset and a few degrees of yaw / pitch / roll are fitted by matching the mesh's
     silhouette to the photo's foreground (the photos are on a flat grey background)
  3. project the photos into UV space: every texel is looked up in every photo that sees it (z-buffer
     visibility test), weighted by how squarely the camera faces the surface and by its distance from
     the silhouette edges, then blended; per-photo colour gains are matched to the front photo first so
     the views agree. Texels no photo sees take the reconstruction's own texture; UV seams are dilated.
  4. bake from the full-resolution scan to the decimated head: a tangent-space normal map and ambient
     occlusion; derive roughness (oilier T-zone, matte cheeks, rough beard and hair) and a detail mask;
     turn the close-up skin plate into a tiling detail normal and the stubble plate into beard relief
  5. place the head in skeleton space (metres) by its eyes (interpupillary distance and eye-line target
     from the scan config) and write it out with an eyes.json the rig builder uses for the eyeballs.

Run (needs numpy, pillow, scipy, trimesh, numba, xatlas, fast_simplification, embreex):
  python3 game/tools/project_face_texture.py docs/face_scans/sol/scan.json
"""
import json
import math
import os
import sys
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage, optimize
import trimesh
import numba
import xatlas
import fast_simplification

# --------------------------------------------------------------------------- rasterisers


@numba.njit(cache=True)
def _raster_depth(sx, sy, sz, faces, w, h, zbuf, tid):
    """z-buffer: sz = distance from the camera (smaller is nearer)."""
    for f in range(faces.shape[0]):
        a, b, c = faces[f, 0], faces[f, 1], faces[f, 2]
        x0, y0, x1, y1, x2, y2 = sx[a], sy[a], sx[b], sy[b], sx[c], sy[c]
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-12:
            continue
        mnx = max(int(math.floor(min(x0, min(x1, x2)))), 0)
        mxx = min(int(math.ceil(max(x0, max(x1, x2)))), w - 1)
        mny = max(int(math.floor(min(y0, min(y1, y2)))), 0)
        mxy = min(int(math.ceil(max(y0, max(y1, y2)))), h - 1)
        for py in range(mny, mxy + 1):
            for px in range(mnx, mxx + 1):
                qx = px + 0.5
                qy = py + 0.5
                w0 = ((x1 - qx) * (y2 - qy) - (x2 - qx) * (y1 - qy)) / area
                w1 = ((x2 - qx) * (y0 - qy) - (x0 - qx) * (y2 - qy)) / area
                w2 = 1.0 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                z = w0 * sz[a] + w1 * sz[b] + w2 * sz[c]
                if z < zbuf[py, px]:
                    zbuf[py, px] = z
                    tid[py, px] = f


@numba.njit(cache=True)
def _raster_uv(ux, uy, faces, w, h, tid, bary):
    """Which triangle covers each texel (UV space), with barycentrics. Slightly conservative."""
    for f in range(faces.shape[0]):
        a, b, c = faces[f, 0], faces[f, 1], faces[f, 2]
        x0, y0, x1, y1, x2, y2 = ux[a], uy[a], ux[b], uy[b], ux[c], uy[c]
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-12:
            continue
        mnx = max(int(math.floor(min(x0, min(x1, x2)))) - 1, 0)
        mxx = min(int(math.ceil(max(x0, max(x1, x2)))) + 1, w - 1)
        mny = max(int(math.floor(min(y0, min(y1, y2)))) - 1, 0)
        mxy = min(int(math.ceil(max(y0, max(y1, y2)))) + 1, h - 1)
        tol = 0.6 / math.sqrt(abs(area))
        for py in range(mny, mxy + 1):
            for px in range(mnx, mxx + 1):
                qx = px + 0.5
                qy = py + 0.5
                w0 = ((x1 - qx) * (y2 - qy) - (x2 - qx) * (y1 - qy)) / area
                w1 = ((x2 - qx) * (y0 - qy) - (x0 - qx) * (y2 - qy)) / area
                w2 = 1.0 - w0 - w1
                if w0 < -tol or w1 < -tol or w2 < -tol:
                    continue
                inside = w0 >= 0 and w1 >= 0 and w2 >= 0
                if tid[py, px] >= 0 and not inside:
                    continue
                tid[py, px] = f
                bary[py, px, 0] = w0
                bary[py, px, 1] = w1
                bary[py, px, 2] = w2


# --------------------------------------------------------------------------- helpers

def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def bilinear(img, x, y):
    h, w = img.shape[:2]
    x = np.clip(x - 0.5, 0, w - 1.001)
    y = np.clip(y - 0.5, 0, h - 1.001)
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    a = img[y0, x0]
    b = img[y0, x0 + 1]
    c = img[y0 + 1, x0]
    d = img[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def dilate(img, mask, iters):
    """Grow the covered texels (mask) outward by averaging covered neighbours: fills UV seams."""
    img = img.copy()
    m = mask.astype(np.float32)
    for _ in range(iters):
        if m.min() > 0:
            break
        k = np.ones((3, 3), np.float32)
        cnt = ndimage.convolve(m, k, mode='nearest')
        acc = np.stack([ndimage.convolve(img[..., c] * m, k, mode='nearest') for c in range(img.shape[2])], -1)
        grow = (m == 0) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        m = np.maximum(m, grow.astype(np.float32))
    return img


def vertex_normals(v, f):
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    vn = np.zeros_like(v)
    for k in range(3):
        np.add.at(vn, f[:, k], fn)
    return vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)


def vertex_tangents(v, f, uv, vn):
    """Per-vertex tangents (xyz + handedness) from UV gradients, like the MikkTSpace result on a smooth mesh."""
    p0, p1, p2 = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    t0, t1, t2 = uv[f[:, 0]], uv[f[:, 1]], uv[f[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = t1 - t0, t2 - t0
    r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.where(np.abs(r) < 1e-12, 1e-12, r)
    sdir = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / r[:, None]
    tdir = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / r[:, None]
    tan = np.zeros_like(v)
    bit = np.zeros_like(v)
    for k in range(3):
        np.add.at(tan, f[:, k], sdir)
        np.add.at(bit, f[:, k], tdir)
    tan = tan - vn * np.sum(tan * vn, 1, keepdims=True)
    tan /= np.maximum(np.linalg.norm(tan, axis=1, keepdims=True), 1e-12)
    hand = np.where(np.sum(np.cross(vn, tan) * bit, 1) < 0, -1.0, 1.0)
    return tan, hand


# --------------------------------------------------------------------------- cameras

class Cam:
    """Perspective camera orbiting the head: az > 0 = toward the subject's left (+X), el > 0 = above."""

    def __init__(self, az, el, w, h, dist):
        self.az, self.el = math.radians(az), math.radians(el)
        self.w, self.h, self.dist = w, h, dist
        # 85 mm on a 36 mm-tall (portrait) frame
        self.f0 = h * 85.0 / 36.0
        self.p = np.zeros(6)  # log zoom, tx, ty (px), d-yaw, d-pitch, roll (rad)

    def rot(self):
        return rot_z(self.p[5]) @ rot_x(self.el + self.p[4]) @ rot_y(-(self.az + self.p[3]))

    def project(self, pts):
        c = pts @ self.rot().T
        depth = self.dist - c[:, 2]
        f = self.f0 * math.exp(self.p[0])
        x = self.w * 0.5 + self.p[1] + f * c[:, 0] / depth
        y = self.h * 0.5 + self.p[2] - f * c[:, 1] / depth
        return x, y, depth

    def eye(self):
        return self.rot().T @ np.array([0.0, 0.0, self.dist])

    def ray(self, px, py):
        f = self.f0 * math.exp(self.p[0])
        d = np.array([(px - self.w * 0.5 - self.p[1]) / f, -(py - self.h * 0.5 - self.p[2]) / f, -1.0])
        d = self.rot().T @ d
        return self.eye(), d / np.linalg.norm(d)


def zbuffer(cam, v, f, scale=1.0):
    w, h = int(cam.w * scale), int(cam.h * scale)
    x, y, z = cam.project(v)
    zb = np.full((h, w), np.inf)
    tid = np.full((h, w), -1, np.int64)
    _raster_depth(x * scale, y * scale, z, f, w, h, zb, tid)
    return zb, tid


def photo_mask(img):
    a = img.astype(np.float32)
    corners = np.concatenate([a[:24, :24].reshape(-1, 3), a[:24, -24:].reshape(-1, 3)])
    bg = np.median(corners, 0)
    m = np.linalg.norm(a - bg, axis=2) > 26
    m = ndimage.binary_opening(m, iterations=2)
    m = ndimage.binary_fill_holes(m)
    lab, n = ndimage.label(m)
    if n > 1:
        sizes = ndimage.sum(m, lab, range(1, n + 1))
        m = lab == (1 + int(np.argmax(sizes)))
    return m


def fit_camera(cam, v, f, mask, y_max_frac, log):
    """Silhouette fit at quarter resolution: maximise IoU above the neck crop line."""
    s = 0.25
    small = np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).resize(
        (int(cam.w * s), int(cam.h * s)), Image.BILINEAR)) > 127
    hs, ws = small.shape
    rows = np.arange(hs)[:, None]
    ys = np.where(small.any(1))[0]
    xs = np.where(small.any(0))[0]
    # initial zoom / offset from the bounding boxes (the mesh's top and centre vs the photo's)
    zb, _ = zbuffer(cam, v, f, s)
    mm = np.isfinite(zb)
    my = np.where(mm.any(1))[0]
    mx = np.where(mm.any(0))[0]
    limit = int(y_max_frac * hs)
    ph = min(limit, ys[-1]) - ys[0]
    mh = my[-1] - my[0]
    cam.p[0] = math.log(max(ph, 1) / max(mh, 1))
    zb, _ = zbuffer(cam, v, f, s)
    mm = np.isfinite(zb)
    my = np.where(mm.any(1))[0]
    cam.p[2] += (ys[0] - my[0]) / s
    row_m = mm[min(my[0] + 5, hs - 1):limit].any(0)
    row_p = small[ys[0] + 5:limit].any(0)
    if row_m.any() and row_p.any():
        cam.p[1] += (np.mean(np.where(row_p)[0]) - np.mean(np.where(row_m)[0])) / s
    band = rows < limit

    def cost(p):
        cam.p = p
        zb, _ = zbuffer(cam, v, f, s)
        m = np.isfinite(zb)
        inter = np.sum(m & small & band)
        union = np.sum((m | small) & band)
        # priors: the silhouette alone cannot tell a frontal view's yaw, so the angle stays near nominal
        prior = (math.degrees(p[3]) / cam.yaw_tol) ** 2 + (math.degrees(p[4]) / 12.0) ** 2 + (math.degrees(p[5]) / 8.0) ** 2
        return 1.0 - inter / max(union, 1) + 0.01 * prior

    p0 = cam.p.copy()
    best = (cost(p0), p0.copy())
    # coarse yaw scan first: generated photos are only roughly at their nominal angle
    for dyaw in np.radians([d for d in (-20, -12, -6, 0, 6, 12, 20) if abs(d) <= cam.yaw_tol]):
        p = best[1].copy() if dyaw == 0 else p0.copy()
        p[3] = dyaw
        c = cost(p)
        if c < best[0]:
            best = (c, p.copy())
    simplex = np.vstack([best[1], best[1] + np.diag([0.04, 12.0, 12.0, 0.08, 0.06, 0.04])])
    res = optimize.minimize(cost, best[1], method='Nelder-Mead',
                            options={'xatol': 1e-3, 'fatol': 1e-4, 'maxiter': 500, 'initial_simplex': simplex})
    cam.p = res.x if res.fun < best[0] else best[1]
    iou = 1.0 - min(res.fun, best[0])
    log('  fit %-14s az %+6.1f  zoom %.3f  t (%+.0f, %+.0f) px  dyaw %+.1f dpitch %+.1f roll %+.1f  IoU %.3f' % (
        cam.name, math.degrees(cam.az), math.exp(cam.p[0]), cam.p[1], cam.p[2], math.degrees(cam.p[3]),
        math.degrees(cam.p[4]), math.degrees(cam.p[5]), iou))
    return iou


# --------------------------------------------------------------------------- main

def main(cfg_path):
    cfg = json.load(open(cfg_path))
    base = os.path.dirname(os.path.abspath(cfg_path))
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

    def rp(p):
        return p if os.path.isabs(p) else os.path.join(repo, p)

    out_dir = rp(cfg['out_dir'])
    prefix = cfg['out_prefix']
    os.makedirs(out_dir, exist_ok=True)
    dbg = rp(cfg.get('debug_dir', os.path.join(tempfile.gettempdir(), 'face_scan_debug', cfg['out_prefix'])))
    os.makedirs(dbg, exist_ok=True)
    report = []

    def log(s):
        print(s)
        report.append(s)

    # ---------------------------------------------------------------- 1. mesh
    raw = trimesh.load(rp(cfg['raw_mesh']), force='mesh', process=False)
    tex_img = None
    raw_uv = None
    if hasattr(raw.visual, 'uv') and raw.visual.uv is not None:
        raw_uv = np.asarray(raw.visual.uv, np.float64)
        mat = raw.visual.material
        im = getattr(mat, 'baseColorTexture', None) or getattr(mat, 'image', None)
        if im is not None:
            tex_img = np.asarray(im.convert('RGB'), np.float32) / 255.0
    hv = np.asarray(raw.vertices, np.float64)
    hf = np.asarray(raw.faces, np.int64)
    R0 = rot_y(math.radians(cfg.get('scan_yaw', 0.0))) @ rot_x(math.radians(cfg.get('scan_pitch', 0.0)))
    hv = hv @ R0.T
    lo, hi = hv.min(0), hv.max(0)
    centre = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2])
    size = hi[1] - lo[1]
    hv = (hv - centre) / size  # normalised: 1 unit tall, centred
    log('raw scan: %d verts, %d tris, texture %s' % (len(hv), len(hf), None if tex_img is None else tex_img.shape))
    # weld for decimation (UV seams split the raw vertices)
    wm = trimesh.Trimesh(hv, hf, process=False)
    wm.merge_vertices(merge_tex=True, merge_norm=True, digits_vertex=6)
    wm.remove_unreferenced_vertices()
    target = cfg.get('target_tris', 36000)
    lv, lf = fast_simplification.simplify(np.asarray(wm.vertices, np.float32), np.asarray(wm.faces, np.int32),
                                          target_reduction=max(0.0, 1.0 - target / len(wm.faces)))
    lv = lv.astype(np.float64)
    lf = lf.astype(np.int64)
    lm = trimesh.Trimesh(lv, lf, process=True)
    # keep the largest connected piece (drops floating crumbs)
    parts = lm.split(only_watertight=False)
    lm = max(parts, key=lambda m: len(m.faces))
    lv, lf = np.asarray(lm.vertices), np.asarray(lm.faces, np.int64)
    log('decimated: %d verts, %d tris' % (len(lv), len(lf)))

    # ---------------------------------------------------------------- 2. cameras
    cams = []
    for vcfg in cfg['views']:
        img = np.asarray(Image.open(os.path.join(base, vcfg['img'])).convert('RGB'))
        h, w = img.shape[:2]
        cam = Cam(vcfg['az'], vcfg.get('el', 0.0), w, h, cfg.get('cam_dist', 4.0))
        cam.name = vcfg['img']
        cam.img = img
        cam.weight = vcfg.get('weight', 1.0)
        cam.priority = vcfg.get('priority', 0.0)  # added to the view's cosine when choosing the best view
        cam.crop = vcfg.get('crop_y', 0.80)
        cam.yaw_tol = vcfg.get('yaw_tol', 15.0)
        cam.mask = photo_mask(img)
        cam.iou = fit_camera(cam, lv, lf, cam.mask, cam.crop, log)
        cams.append(cam)

    # ---------------------------------------------------------------- 3. eyes (front photo landmarks)
    front = cams[0]
    hmesh = trimesh.Trimesh(hv, hf, process=False)
    ray = trimesh.ray.ray_pyembree.RayMeshIntersector(hmesh)
    eyes = []
    for ex, ey in cfg['eyes_px']:
        o, d = front.ray(ex, ey)
        loc, _, _ = ray.intersects_location([o], [d], multiple_hits=False)
        eyes.append(loc[0])
    eyes = np.array(eyes)  # [subject's right eye (image left), left eye]
    ipd = np.linalg.norm(eyes[0] - eyes[1])
    log('eyes (normalised): %s  IPD %.4f' % (np.round(eyes, 4).tolist(), ipd))

    # ---------------------------------------------------------------- 4. UV unwrap of the game mesh
    # The face (the front-facing skin between the ears, brow to chin) is unwrapped on its own and
    # given `face_texel_boost` times the texel density of the hair, ears and neck: it is what the
    # camera looks at in close-ups, and the hair's grooves would otherwise cut it into many charts.
    mid0 = eyes.mean(0)
    lfn = np.cross(lv[lf[:, 1]] - lv[lf[:, 0]], lv[lf[:, 2]] - lv[lf[:, 0]])
    lfn /= np.maximum(np.linalg.norm(lfn, axis=1, keepdims=True), 1e-12)
    rc = (lv[lf].mean(1) - mid0) / ipd
    face_sel = (lfn[:, 2] > 0.3) & (np.abs(rc[:, 0]) < 1.25) & (rc[:, 1] < 1.3) & (rc[:, 1] > -2.3) & (rc[:, 2] > -1.0)
    adj = trimesh.graph.face_adjacency(lf[face_sel]) if face_sel.any() else np.zeros((0, 2), int)
    comps = trimesh.graph.connected_components(adj, nodes=np.arange(face_sel.sum()))
    biggest = max(comps, key=len)
    idx_sel = np.where(face_sel)[0]
    is_face = np.zeros(len(lf), bool)
    is_face[idx_sel[biggest]] = True
    boost = cfg.get('face_texel_boost', 2.0)

    def submesh(part):
        pf = lf[part]
        used = np.unique(pf)
        remap = -np.ones(len(lv), np.int64)
        remap[used] = np.arange(len(used))
        return used, remap[pf]

    # layout: the face chart fills a strip on the left (face_strip of the width), the rest of the head
    # is charted by xatlas into the square at the top right
    fw = cfg.get('face_strip', 0.45)
    S0 = cfg.get('albedo_size', 2048)
    pad = 8.0 / S0
    r_used, r_f = submesh(~is_face)
    a1 = xatlas.Atlas()
    a1.add_mesh(lv[r_used].astype(np.float32), r_f.astype(np.uint32))
    co = xatlas.ChartOptions()
    co.max_cost = 4.0
    p1 = xatlas.PackOptions()
    p1.resolution = int(S0 * (1.0 - fw))
    p1.padding = 4
    p1.bilinear = True
    a1.generate(co, p1)
    r_vmap, r_f2, r_uv = a1[0]
    side = 1.0 - fw - pad  # the rest's square, in units of the texture width
    # the face: one planar (front) chart, aspect kept, top of the face at the top of the strip
    f_used, f_f = submesh(is_face)
    fx, fy = lv[f_used, 0], lv[f_used, 1]
    sc = (fw - 2 * pad) / (fx.max() - fx.min())
    f_uv = np.stack([(fx - fx.min()) * sc + pad, (fy.max() - fy) * sc + pad], 1)
    # texture height: whatever both need (non-square, a multiple of 16 px)
    H0 = int(math.ceil(max((fy.max() - fy.min()) * sc + 2 * pad, side + pad) * S0 / 16.0)) * 16
    hr = S0 / H0
    f_uv[:, 1] *= hr
    r_uv = np.asarray(r_uv, np.float64) * side
    r_uv[:, 0] += fw + pad
    r_uv[:, 1] *= hr
    vmap = np.concatenate([f_used, r_used[r_vmap]])
    gf = np.concatenate([f_f, r_f2.astype(np.int64) + len(f_used)])
    guv = np.concatenate([f_uv, r_uv])
    log('atlas %d x %d px; face chart %.0f x %.0f px (%.1f px per mm)' % (
        S0, H0, (fx.max() - fx.min()) * sc * S0, (fy.max() - fy.min()) * sc * S0, sc * S0 * ipd / 64.0))
    gv = lv[vmap]
    gn = vertex_normals(lv, lf)[vmap]
    log('unwrapped: %d verts (UV splits), %d tris, %d charts besides the face (%d face tris)' % (
        len(gv), len(gf), a1.chart_count, is_face.sum()))

    S, SH = S0, H0
    tid = np.full((SH, S), -1, np.int64)
    bary = np.zeros((SH, S, 3))
    _raster_uv(guv[:, 0] * S, guv[:, 1] * SH, gf, S, SH, tid, bary)
    cov = tid >= 0
    tt = np.where(cov, tid, 0)
    fa, fb, fc = gf[tt, 0], gf[tt, 1], gf[tt, 2]
    b0, b1, b2 = bary[..., 0:1], bary[..., 1:2], bary[..., 2:3]
    P = gv[fa] * b0 + gv[fb] * b1 + gv[fc] * b2
    N = gn[fa] * b0 + gn[fb] * b1 + gn[fc] * b2
    N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-12)
    Pc, Nc = P[cov], N[cov]
    log('texels covered: %.1f%%' % (100.0 * cov.mean()))

    # ---------------------------------------------------------------- 5. projection
    samples = []
    cam_cos = []
    for cam in cams:
        zb, _ = zbuffer(cam, gv, gf)
        x, y, depth = cam.project(Pc)
        xi = np.clip(x.astype(np.int64), 0, cam.w - 1)
        yi = np.clip(y.astype(np.int64), 0, cam.h - 1)
        inb = (x >= 0) & (x < cam.w) & (y >= 0) & (y < cam.h)
        # visibility: the texel must be the nearest surface at its pixel (small tolerance)
        zf = np.where(np.isfinite(zb), zb, 1e9)
        zs = bilinear(zf[..., None], x, y)[:, 0]
        vis = inb & (depth <= np.minimum(zs, zf[yi, xi]) + 0.005)
        view = cam.eye()[None, :] - Pc
        view /= np.linalg.norm(view, axis=1, keepdims=True)
        cosv = np.clip(np.sum(view * Nc, 1), 0, 1)
        # feather near the mesh's silhouette and the photo's foreground edge (misalignment lives there)
        mesh_in = np.isfinite(zb)
        dm = ndimage.distance_transform_edt(mesh_in)
        dp = ndimage.distance_transform_edt(cam.mask)
        edge = np.clip(np.minimum(dm, dp)[yi, xi] / 10.0, 0, 1)
        crop = np.clip((cam.crop * cam.h - y) / 30.0, 0, 1)
        wgt = vis * (cosv ** 5) * edge * crop * cam.weight
        cam_cos.append(np.where(wgt > 0, cosv + cam.priority, -1.0))
        col = srgb_to_lin(bilinear(cam.img.astype(np.float32) / 255.0, x, y))
        samples.append((wgt, col, cosv))
        log('  %-14s sees %.1f%% of the texels' % (cam.name, 100.0 * np.mean(wgt > 0.05)))

    sharp = cfg.get('view_sharpness', 0.06)
    cmax = np.max(np.stack(cam_cos), 0)
    sharpened = [(wgt * np.exp((cc - cmax) / sharp), col, cosv) for (wgt, col, cosv), cc in zip(samples, cam_cos)]

    # colour harmonisation: per-view RGB gains so overlapping views agree with the front photo
    gains = [np.ones(3) for _ in cams]
    for it in range(3):
        wsum = sum(s[0] for s in samples) + 1e-9
        blend = sum(s[0][:, None] * s[1] * g for s, g in zip(samples, gains)) / wsum[:, None]
        for i, (wgt, col, _) in enumerate(samples):
            if i == 0:
                continue
            sel = (wgt > 0.15) & (wsum > wgt * 1.4)  # texels this view shares with others
            if sel.sum() < 500:
                continue
            g = np.sum(blend[sel] * wgt[sel, None], 0) / np.maximum(np.sum(col[sel] * wgt[sel, None], 0), 1e-6)
            gains[i] = np.clip(g, 0.6, 1.6)
    for c, g in zip(cams, gains):
        log('  gain %-14s %s' % (c.name, np.round(g, 3).tolist()))
    samples = sharpened  # gains come from the soft blend, the texture from the near-best view
    wsum = sum(s[0] for s in samples)
    albedo_c = sum(s[0][:, None] * s[1] * g for s, g in zip(samples, gains)) / np.maximum(wsum, 1e-9)[:, None]
    # second pass for texels only seen at grazing angles
    weak = wsum < 0.02
    # (the visibility test is reused: a cos^5 weight > 0 means visible; re-weighted by cos^1)
    wg = np.zeros_like(wsum)
    cg = np.zeros_like(albedo_c)
    for (wgt, col, cosv), g in zip(samples, gains):
        ww = np.where(wgt > 0, (wgt / np.maximum(cosv ** 5, 1e-9)) * cosv, 0.0)
        wg += ww
        cg += ww[:, None] * col * g
    fix = weak & (wg > 1e-4)
    albedo_c[fix] = cg[fix] / wg[fix][:, None]
    seen = (wsum >= 0.02) | fix
    log('texels from photos: %.1f%%, from the reconstruction texture: %.1f%%' % (
        100.0 * seen.mean(), 100.0 * (~seen).mean()))

    # fallback: the reconstruction's own texture (nearest surface along the normal)
    if tex_img is not None and (~seen).any():
        idx = np.where(~seen)[0]
        o = Pc[idx] + Nc[idx] * 0.01
        locs, ri, tri = ray.intersects_location(o, -Nc[idx], multiple_hits=False)
        got = np.zeros(len(idx), bool)
        if len(ri):
            bc = trimesh.triangles.points_to_barycentric(hmesh.triangles[tri], locs)
            uvh = np.einsum('nk,nkj->nj', bc, raw_uv[hf[tri]])
            th, tw = tex_img.shape[:2]
            c = bilinear(tex_img, uvh[:, 0] * tw, (1.0 - uvh[:, 1]) * th)
            # match the reconstruction texture's tone to the projected photos
            albedo_c[idx[ri]] = srgb_to_lin(c)
            got[ri] = True
        lum_ph = np.median(albedo_c[seen], 0)
        if got.any():
            lum_tx = np.median(albedo_c[idx[got]], 0)
            albedo_c[idx[got]] *= np.clip(lum_ph / np.maximum(lum_tx, 1e-4), 0.5, 2.0)
        rest = idx[~got]
        albedo_c[rest] = np.median(albedo_c[seen], 0)

    # The neck under the jaw is only ever seen at grazing angles (and the photos' necks are lit
    # differently), so its tone is matched to the cheeks: a gain fading in below the chin.
    relc = (Pc - eyes.mean(0)) / ipd
    lumc = albedo_c @ np.array([0.2126, 0.7152, 0.0722])
    cheek = (relc[:, 1] > -1.3) & (relc[:, 1] < -0.4) & (np.abs(relc[:, 0]) > 0.55) & (np.abs(relc[:, 0]) < 1.1) & (Nc[:, 2] > 0.3)
    neck_t = np.clip((-relc[:, 1] - 2.0) / 0.6, 0, 1) * (relc[:, 2] > -1.6)
    skinish = lumc > np.percentile(lumc[cheek], 20) * 0.6
    nz = (neck_t > 0.5) & skinish
    log('tone match: %d cheek texels, %d neck texels' % (cheek.sum(), nz.sum()))
    if cheek.sum() > 100 and nz.sum() > 100:
        g = np.median(albedo_c[cheek], 0) / np.maximum(np.median(albedo_c[nz], 0), 1e-4)
        g = np.clip(g, 0.4, 1.5)
        albedo_c *= (1.0 + (g[None, :] - 1.0) * neck_t[:, None])
        log('neck tone gain %s' % np.round(g, 3).tolist())
    # debug: which photo each texel came from
    src = np.argmax(np.stack([s[0] for s in samples]), 0)
    pal = np.array([[255, 255, 255], [255, 80, 80], [80, 255, 80], [255, 160, 0], [0, 200, 255], [255, 0, 255],
                    [0, 120, 255], [120, 60, 0], [255, 255, 0], [0, 255, 200]] * 2, np.uint8)
    dbg_src = np.zeros((SH, S, 3), np.uint8)
    dbg_src[cov] = np.where(seen[:, None], pal[src], 0)
    Image.fromarray(dbg_src).resize((1024, 1024 * SH // S), Image.NEAREST).save(os.path.join(dbg, 'source_view.png'))

    alb = np.zeros((SH, S, 3))
    alb[cov] = albedo_c
    tone = cfg.get('albedo_gain', [1.0, 1.0, 1.0])
    alb = alb * np.array(tone)
    alb = dilate(alb, cov, 24)
    alb_srgb = lin_to_srgb(alb)
    Image.fromarray((alb_srgb * 255 + 0.5).astype(np.uint8)).save(os.path.join(out_dir, prefix + '_albedo.jpg'), quality=92)
    wm_img = np.zeros((SH, S))
    wm_img[cov] = np.clip(wsum, 0, 1)
    Image.fromarray((wm_img * 255).astype(np.uint8)).resize((512, 512 * SH // S)).save(os.path.join(dbg, 'coverage.png'))

    # ---------------------------------------------------------------- 6. bakes from the full-res scan
    T = cfg.get('map_size', 1024)
    TH = T * H0 // S0
    tid2 = np.full((TH, T), -1, np.int64)
    bary2 = np.zeros((TH, T, 3))
    _raster_uv(guv[:, 0] * T, guv[:, 1] * TH, gf, T, TH, tid2, bary2)
    cov2 = tid2 >= 0
    t2 = np.where(cov2, tid2, 0)
    fa, fb, fc = gf[t2, 0], gf[t2, 1], gf[t2, 2]
    b0, b1, b2 = bary2[..., 0:1], bary2[..., 1:2], bary2[..., 2:3]
    P2 = (gv[fa] * b0 + gv[fb] * b1 + gv[fc] * b2)[cov2]
    N2 = (gn[fa] * b0 + gn[fb] * b1 + gn[fc] * b2)[cov2]
    N2 /= np.linalg.norm(N2, axis=1, keepdims=True)
    gtan, ghand = vertex_tangents(gv, gf, guv * np.array([1.0, -1.0]) + np.array([0.0, 1.0]), gn)
    T2 = (gtan[fa] * b0 + gtan[fb] * b1 + gtan[fc] * b2)[cov2]
    H2 = ghand[fa][cov2]
    T2 = T2 - N2 * np.sum(T2 * N2, 1, keepdims=True)
    T2 /= np.maximum(np.linalg.norm(T2, axis=1, keepdims=True), 1e-12)
    B2 = np.cross(N2, T2) * H2[:, None]
    # smooth normals across the raw mesh's UV seams (vertices split there share a position)
    _, weld = np.unique(np.round(hv, 6), axis=0, return_inverse=True)
    weld = weld.ravel()
    fn = np.cross(hv[hf[:, 1]] - hv[hf[:, 0]], hv[hf[:, 2]] - hv[hf[:, 0]])
    acc = np.zeros((weld.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, weld[hf[:, k]], fn)
    hn = acc[weld]
    hn /= np.maximum(np.linalg.norm(hn, axis=1, keepdims=True), 1e-12)
    # cast both ways along the low normal, keep the nearer hit
    hitn = N2.copy()
    best = np.full(len(P2), np.inf)
    for sgn in (1.0, -1.0):
        o = P2 + N2 * 0.012 * sgn
        locs, ri, tri = ray.intersects_location(o, -N2 * sgn, multiple_hits=False)
        if len(ri) == 0:
            continue
        dist = np.linalg.norm(locs - P2[ri], axis=1)
        bc = trimesh.triangles.points_to_barycentric(hmesh.triangles[tri], locs)
        n = np.einsum('nk,nkj->nj', bc, hn[hf[tri]])
        n /= np.linalg.norm(n, axis=1, keepdims=True)
        upd = (dist < best[ri]) & (dist < 0.012)
        best[ri[upd]] = dist[upd]
        hitn[ri[upd]] = n[upd]
    tn = np.stack([np.sum(hitn * T2, 1), np.sum(hitn * B2, 1), np.sum(hitn * N2, 1)], 1)
    tn /= np.linalg.norm(tn, axis=1, keepdims=True)

    # face regions in the normalised head frame (eyes known): used by roughness, beard relief and detail mask
    mid = eyes.mean(0)
    up = np.array([0.0, 1.0, 0.0])
    rel = (P2 - mid) / ipd  # in interpupillary units
    facing = N2[:, 2]
    front_face = np.clip((facing - 0.1) / 0.4, 0, 1)
    # albedo at map resolution
    alb_small = np.asarray(Image.fromarray((alb_srgb * 255).astype(np.uint8)).resize((T, TH), Image.LANCZOS), np.float32) / 255
    a2 = alb_small[cov2]
    lum = a2 @ np.array([0.2126, 0.7152, 0.0722])
    sat = (a2.max(1) - a2.min(1)) / np.maximum(a2.max(1), 1e-4)
    hairish = np.clip((0.16 - lum) / 0.08, 0, 1) * np.clip((0.45 - sat) / 0.25, 0, 1)
    # beard: below the nose on the jaw and chin; hair: above the hairline / behind the ears
    jaw = np.clip((-0.75 - rel[:, 1]) / 0.25, 0, 1) * np.clip((rel[:, 2] + 1.2) / 0.5, 0, 1)
    beard = np.clip(hairish * 1.4, 0, 1) * jaw
    hair = np.clip(hairish * 1.4, 0, 1) * (1 - jaw)
    gauss = lambda d2, s: np.exp(-d2 / (2 * s * s))
    tz_fore = gauss((rel[:, 0] / 0.9) ** 2 + ((rel[:, 1] - 0.75) / 0.45) ** 2, 1.0)
    tz_nose = gauss((rel[:, 0] / 0.28) ** 2 + ((rel[:, 1] + 0.45) / 0.55) ** 2, 1.0)
    tzone = np.clip(np.maximum(tz_fore, tz_nose) * front_face, 0, 1)
    lips = gauss((rel[:, 0] / 0.55) ** 2 + ((rel[:, 1] + 1.15) / 0.13) ** 2, 1.0) * front_face * (1 - beard)
    rough = 0.58 - 0.14 * tzone - 0.08 * lips
    rough = rough * (1 - beard) + 0.74 * beard
    rough = rough * (1 - hair) + 0.82 * hair

    # beard relief from the stubble plate, tiled in UV space where the beard is
    if cfg.get('beard_plate'):
        bp = np.asarray(Image.open(os.path.join(base, cfg['beard_plate'])).convert('L'), np.float32) / 255
        hp = bp - ndimage.gaussian_filter(bp, 6)
        hp /= max(hp.std(), 1e-4)
        tile = cfg.get('beard_tile', 6.0)
        gy, gx = np.gradient(ndimage.gaussian_filter(hp, 0.8))
        uvc = np.stack(np.where(cov2), 1)[:, ::-1].astype(np.float64) / T  # isotropic: both by width
        bx = (uvc[:, 0] * tile * bp.shape[1]) % bp.shape[1]
        by = (uvc[:, 1] * tile * bp.shape[0]) % bp.shape[0]
        dx = bilinear(gx[..., None], bx, by)[:, 0]
        dy = bilinear(gy[..., None], bx, by)[:, 0]
        k = 0.22 * beard
        tn = tn + np.stack([-dx * k, dy * k, np.zeros_like(dx)], 1)
        tn /= np.linalg.norm(tn, axis=1, keepdims=True)

    nm = np.zeros((TH, T, 3))
    nm[..., 2] = 1.0
    nm[cov2] = tn
    nm = dilate(nm, cov2, 16)
    nm /= np.maximum(np.linalg.norm(nm, axis=2, keepdims=True), 1e-6)
    Image.fromarray(((nm * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out_dir, prefix + '_normal.png'))

    # ambient occlusion from the full-res scan (per game vertex, interpolated)
    rng = np.random.default_rng(7)
    nray = 48
    dirs = rng.normal(size=(nray, 3))
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    ao_v = np.zeros(len(gv))
    uniq, inv = np.unique(vmap, return_inverse=True)
    lvn = vertex_normals(lv, lf)
    pts = lv[uniq]
    nrm = lvn[uniq]
    occ = np.zeros(len(pts))
    for d in dirs:
        dd = np.where((nrm @ d)[:, None] < 0, -d, d)
        o = pts + nrm * 0.004
        hit = ray.intersects_any(o, dd)
        # only nearby geometry counts (cavities, not the whole skull)
        if hit.any():
            hi_idx = np.where(hit)[0]
            locs, ri, _ = ray.intersects_location(o[hi_idx], dd[hi_idx], multiple_hits=False)
            near = np.zeros(len(hi_idx), bool)
            near[ri] = np.linalg.norm(locs - o[hi_idx][ri], axis=1) < 0.08
            occ[hi_idx[near]] += 1.0
    ao_u = 1.0 - occ / nray
    ao_v = ao_u[inv]
    ao = (ao_v[fa] * b0[..., 0] + ao_v[fb] * b1[..., 0] + ao_v[fc] * b2[..., 0])[cov2]
    ao = np.clip(0.35 + 0.65 * ao, 0, 1) ** 1.2
    # cavity from the albedo's fine dark detail (pores, creases)
    lum_full = np.zeros((TH, T))
    lum_full[cov2] = lum
    cav = lum_full - ndimage.gaussian_filter(lum_full, 2.0)
    cavity = np.clip(1.0 + cav[cov2] * 2.5, 0.75, 1.0)
    ao = ao * cavity

    orm = np.zeros((TH, T, 3))
    orm[..., 0] = 1.0
    orm[..., 1] = 0.6
    orm[cov2, 0] = ao
    orm[cov2, 1] = rough
    orm = dilate(orm, cov2, 16)
    Image.fromarray((orm * 255 + 0.5).astype(np.uint8)).save(os.path.join(out_dir, prefix + '_orm.png'))

    # detail mask: full pore detail on bare skin, little in the beard, none in the hair
    dmask = np.zeros((TH, T, 3))
    dmask[cov2, 0] = np.clip(1.0 - hair - 0.7 * beard, 0, 1)
    dmask = dilate(dmask, cov2, 16)
    dm = Image.fromarray((dmask[..., 0] * 255).astype(np.uint8)).resize((512, 512 * TH // T), Image.LANCZOS)
    dm.save(os.path.join(out_dir, prefix + '_detail_mask.png'))

    # tiling detail normal from the skin plate
    if cfg.get('skin_plate'):
        sp = np.asarray(Image.open(os.path.join(base, cfg['skin_plate'])).convert('L'), np.float32) / 255
        n0 = 512
        sp = np.asarray(Image.fromarray((sp * 255).astype(np.uint8)).resize((n0, n0), Image.LANCZOS), np.float32) / 255
        hp = sp - ndimage.gaussian_filter(sp, 10)
        hp /= max(hp.std(), 1e-4)
        # seamless: cross-fade with a half-period roll, weighted away from the edges
        r = np.roll(np.roll(hp, n0 // 2, 0), n0 // 2, 1)
        e = np.minimum(np.arange(n0), n0 - 1 - np.arange(n0)) / (n0 / 2)
        wgt = np.clip(np.minimum(e[:, None], e[None, :]) * 2.0, 0, 1)
        ht = hp * wgt + r * (1 - wgt)
        ht = ndimage.gaussian_filter(ht, 0.7, mode='wrap')
        gx = (np.roll(ht, -1, 1) - np.roll(ht, 1, 1)) * 0.5
        gy = (np.roll(ht, -1, 0) - np.roll(ht, 1, 0)) * 0.5
        st = cfg.get('detail_strength', 0.35)
        dn = np.stack([-gx * st, gy * st, np.ones_like(gx)], -1)
        dn /= np.linalg.norm(dn, axis=2, keepdims=True)
        Image.fromarray(((dn * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out_dir, prefix + '_detail_normal.png'))

    # ---------------------------------------------------------------- 7. placement + export
    pl = cfg['placement']
    s = pl['ipd_m'] / ipd
    tgt = np.array(pl['eye_mid'])
    xf = lambda p: (p - mid) * s + tgt
    ov = xf(gv)
    # cut below the collar line (keeps an open neck the rig builder tucks into the collar)
    cut_y = pl.get('cut_y', -1e9)
    keep = np.all(ov[gf][:, :, 1] > cut_y, axis=1)
    gf_k = gf[keep]
    used = np.unique(gf_k)
    remap = -np.ones(len(ov), np.int64)
    remap[used] = np.arange(len(used))
    mesh_out = trimesh.Trimesh(ov[used], remap[gf_k], process=False)
    mesh_out.visual = trimesh.visual.TextureVisuals(uv=guv[used] * np.array([1.0, -1.0]) + np.array([0.0, 1.0]))
    mesh_out.vertex_normals  # computed
    glb = os.path.join(out_dir, prefix + '.glb')
    mesh_out.export(glb)
    log('head: %d tris after the collar cut -> %s' % (len(gf_k), glb))

    iris = []
    for k, (ex, ey) in enumerate(cfg['eyes_px']):
        r = 4
        patch = front.img[int(ey) - r:int(ey) + r, int(ex) - r:int(ex) + r].reshape(-1, 3).astype(np.float32) / 255
        iris.append(np.median(patch, 0).tolist())
    eyes_out = {
        'eyes': [xf(e).tolist() for e in eyes],
        'iris_srgb': np.mean(iris, 0).tolist(),
        'scale': s,
        'note': 'eye surface points of the scan in skeleton space (subject right, left)',
    }
    json.dump(eyes_out, open(os.path.join(out_dir, prefix + '_eyes.json'), 'w'), indent=1)
    log('eyes in skeleton space: %s' % np.round(np.array(eyes_out['eyes']), 4).tolist())

    # debug: per-view projection overlays (mesh silhouette edge on the photo)
    for cam in cams:
        zb, _ = zbuffer(cam, lv, lf, 0.5)
        m = np.isfinite(zb)
        edge = m ^ ndimage.binary_erosion(m, iterations=1)
        im = np.asarray(Image.fromarray(cam.img).resize((m.shape[1], m.shape[0])), np.uint8).copy()
        im[edge] = [255, 40, 40]
        Image.fromarray(im).save(os.path.join(dbg, 'fit_' + os.path.splitext(cam.name)[0] + '.png'))
    open(os.path.join(dbg, 'report.txt'), 'w').write('\n'.join(report) + '\n')


if __name__ == '__main__':
    main(sys.argv[1])
