#!/usr/bin/env python3
"""Sol's look fixes, baked into his source textures in place (round 3, critic C2 + C3).

  1. the neck: under the chin the stylised head's texture is a stretched orange-peach smear; it is
     re-toned to the cheeks' skin in the jaw's shadow (darker, the streaks flattened), fading in below
     the jaw line;
  2. the boots: they rendered pale grey, like socks; they are darkened and desaturated toward a dark
     leather (with the soles darkest);
  3. the coat hem: a beige band (the lining) showed at the hem; it is toned to the coat's own black.

Each fix scales a region toward an absolute target, so running the tool twice changes almost nothing.
The textures stay where the glTF import put them (the built sol_modular.scn points at them), so no
rebuild of the scene is needed; Godot re-imports them (Lossy, 1024 px).

    cd game
    godot --headless -s res://tools/dump_sol_meshes.gd -- /tmp/solmesh
    python3 tools/sol_texture_fixes.py /tmp/solmesh [--preview out.jpg]
"""
import struct, sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SOL = os.path.join(HERE, '..', 'assets', 'characters', 'sol')
TEX = {
    'HeadMesh': 'sol_mod_head_src_Color_e808d4cd-80cc-4547-8bef-cdaece89963c.jpg',
    'Body': 'sol_mod_body_src_Color_4b1b096e-cc0b-40bd-9456-cd1ea7a6e254.jpg',
    'Coat': 'sol_mod_coat_src_Color_35b4b241-49b0-48e6-9a07-e7ec9d577eda.jpg',
}


def load(d, nm):
    b = open(os.path.join(d, nm + '.bin'), 'rb').read()
    nv, ni = struct.unpack('<II', b[:8])
    o = 8
    v = np.frombuffer(b, '<f4', nv * 3, o).reshape(-1, 3); o += nv * 12
    n = np.frombuffer(b, '<f4', nv * 3, o).reshape(-1, 3); o += nv * 12
    uv = np.frombuffer(b, '<f4', nv * 2, o).reshape(-1, 2); o += nv * 8
    idx = np.frombuffer(b, '<u4', ni, o).reshape(-1, 3)
    return v, n, uv, idx


def smooth(a, lo, hi):
    """0 at lo, 1 at hi (either order)."""
    t = np.clip((a - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def weight_map(uv, idx, w_vert, size, feather):
    """Rasterise per-face weights (mean of the vertex weights) into a float map in [0, 1]."""
    W, H = size
    im = Image.new('L', (W, H), 0)
    dr = ImageDraw.Draw(im)
    wf = w_vert[idx].mean(1)
    order = np.argsort(wf)  # strongest last
    for fi in order:
        if wf[fi] <= 0.004:
            continue
        pts = [(float(uv[i, 0] * W), float(uv[i, 1] * H)) for i in idx[fi]]
        dr.polygon(pts, fill=int(round(wf[fi] * 255)), outline=int(round(wf[fi] * 255)))
    if feather > 0:
        im = im.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(feather))
    return np.asarray(im).astype(np.float32) / 255.0


def region_mean(img, uv, sel):
    px = (uv[sel] * np.array([img.shape[1], img.shape[0]])).astype(int)
    px[:, 0] = px[:, 0].clip(0, img.shape[1] - 1)
    px[:, 1] = px[:, 1].clip(0, img.shape[0] - 1)
    return np.median(img[px[:, 1], px[:, 0]], axis=0)


def retone(img, wmap, src_mean, dst_mean, detail=1.0):
    """Move the region (weighted by wmap) from src_mean to dst_mean: per-channel gain, with the
    pixel's own luminance variation kept (scaled by `detail`)."""
    lum = img.mean(2, keepdims=True)
    src_l = max(float(np.mean(src_mean)), 1.0)
    var = (lum / src_l - 1.0) * detail  # the texel's brightness relative to the region
    target = np.clip(dst_mean[None, None, :] * (1.0 + var), 0, 255)
    w = wmap[..., None]
    return img * (1 - w) + target * w


def fix_neck(d, prev):
    v, n, uv, idx = load(d, 'HeadMesh')
    path = os.path.join(SOL, TEX['HeadMesh'])
    img = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    # cheeks: the skin beside the nose, above the beard line, facing forward
    cheek = (v[:, 1] > 1.69) & (v[:, 1] < 1.735) & (np.abs(v[:, 0]) > 0.035) & (np.abs(v[:, 0]) < 0.065) & (n[:, 2] > 0.4)
    # the neck: below the jaw (y < 1.615), all round the front and sides, plus the down-facing under-jaw
    neck_w = smooth(v[:, 1], 1.625, 1.598) * (v[:, 2] > -0.06)
    neck_w = np.maximum(neck_w, smooth(v[:, 1], 1.655, 1.625) * smooth(-n[:, 1], 0.35, 0.7) * (v[:, 2] > 0.0))
    sel = neck_w > 0.6
    # the throat sits in the jaw's shadow: the cheeks' skin, darker and a little less saturated, and
    # with most of the stretched streaks flattened out (low detail)
    ck = region_mean(img, uv, cheek)
    dst = (ck * 0.65 + ck.mean() * 0.35) * 0.62
    src = region_mean(img, uv, sel)
    wmap = weight_map(uv, idx, neck_w, (img.shape[1], img.shape[0]), 6)
    out = retone(img, wmap, src, dst, 0.25)
    print('neck: %d verts, %s -> %s (cheeks)' % (sel.sum(), src.round(0), dst.round(0)))
    prev.append(('neck', img, out, uv[sel]))
    return path, out


def fix_boots(d, prev):
    v, n, uv, idx = load(d, 'Body')
    path = os.path.join(SOL, TEX['Body'])
    img = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    boot_w = smooth(v[:, 1], 0.2, 0.14)  # the boots end at mid-shin under the trousers
    sole_w = smooth(v[:, 1], 0.035, 0.012)
    sel = boot_w > 0.6
    src = region_mean(img, uv, sel)
    dst = np.array([19.0, 17.0, 15.0])  # dark worn leather (sRGB)
    wmap = weight_map(uv, idx, boot_w, (img.shape[1], img.shape[0]), 4)
    out = retone(img, wmap, src, dst, 0.8)
    smap = weight_map(uv, idx, sole_w, (img.shape[1], img.shape[0]), 3)
    out = out * (1 - 0.5 * smap[..., None])
    print('boots: %d verts, %s -> %s' % (sel.sum(), src.round(0), dst))
    prev.append(('boots', img, out, uv[sel]))
    return path, out


def fix_hem(d, prev):
    v, n, uv, idx = load(d, 'Coat')
    path = os.path.join(SOL, TEX['Coat'])
    img = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    y0 = float(v[:, 1].min())
    body = (v[:, 1] > y0 + 0.17) & (v[:, 1] < y0 + 0.4)
    hem_w = smooth(v[:, 1], y0 + 0.14, y0 + 0.05)
    sel = hem_w > 0.6
    src = region_mean(img, uv, sel)
    dst = region_mean(img, uv, body)
    wmap = weight_map(uv, idx, hem_w, (img.shape[1], img.shape[0]), 4)
    out = retone(img, wmap, src, dst, 0.7)
    print('coat hem: %d verts, %s -> %s (the coat above)' % (sel.sum(), src.round(0), dst.round(0)))
    prev.append(('hem', img, out, uv[sel]))
    return path, out


def preview(items, out_path):
    tiles = []
    for name, a, b, uvs in items:
        h, w = a.shape[:2]
        lo = (uvs.min(0) * [w, h]).astype(int) - 40
        hi = (uvs.max(0) * [w, h]).astype(int) + 40
        lo = np.maximum(lo, 0)
        hi = np.minimum(hi, [w, h])
        for img in (a, b):
            crop = Image.fromarray(img[lo[1]:hi[1], lo[0]:hi[0]].clip(0, 255).astype(np.uint8))
            crop.thumbnail((420, 420))
            tiles.append(crop)
    W = 2 * 420
    H = 420 * len(items)
    sheet = Image.new('RGB', (W, H))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 2) * 420, (i // 2) * 420))
    sheet.save(out_path, quality=88)
    print('preview', out_path)


def main():
    d = sys.argv[1]
    prev = []
    results = [fix_neck(d, prev), fix_boots(d, prev), fix_hem(d, prev)]
    if '--preview' in sys.argv:
        preview(prev, sys.argv[sys.argv.index('--preview') + 1])
    if '--dry' in sys.argv:
        return
    for path, img in results:
        Image.fromarray(img.clip(0, 255).astype(np.uint8)).save(path, quality=92, subsampling=0)
        print('wrote', os.path.relpath(path, HERE))


if __name__ == '__main__':
    main()
