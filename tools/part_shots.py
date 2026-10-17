"""Part pictures (T41): the PC-side half of tools/part_shots.lua.

  python tools/part_shots.py matte [--src DIR] [--size 128]
      every <part>_b.png / <part>_w.png pair in DIR/raw (the same part on a black and on a white card) becomes a transparent <part>.png in DIR:
      alpha and colour are recovered from the two shots (difference matting: no halo, glass stays see-through), the part is cropped to its
      outline, fitted into a square with a little margin and scaled to SIZE (default 128).
  python tools/part_shots.py ship --dest DIR [--src DIR]
      copies the finished PNGs into the mod (DIR = the Street Legal mod's art/street_legal/parts), shrinks each to a palette PNG and writes
      manifest.json (the list of parts that have a picture; sl/partinfo shows a picture only for those).
  python tools/part_shots.py selftest
      builds a fake pair and checks the matting.

DIR defaults to the game's settings/street_legal/part_shots folder in BeamNG's user folder.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

DEFAULT = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'BeamNG', 'BeamNG.drive', 'current', 'settings', 'street_legal', 'part_shots')


def border_median(a, frac=0.02):
    """the card's colour: the median over the picture's outer strip (nothing of the part reaches it). The white card is not 255 on screen and is
    different from shot to shot (the game's exposure adapts), so it is measured in each shot."""
    h, w = a.shape[:2]
    t = max(2, int(min(h, w) * frac))
    strip = np.concatenate([a[:t].reshape(-1, a.shape[2]), a[-t:].reshape(-1, a.shape[2]),
                            a[:, :t].reshape(-1, a.shape[2]), a[:, -t:].reshape(-1, a.shape[2])])
    return np.median(strip, axis=0)


def matte(black, white):
    """black, white: float arrays (h, w, 3) in 0..1 of the same part on a black and a white card. Returns RGBA (h, w, 4), 0..1.
    Alpha comes from the difference of the two shots; the white card bleeds a little light onto the part (bloom), so an opaque part measures
    0.8-0.95 and not 1: the measure is stretched so the part's own core is fully opaque. Colour comes from the black shot alone (the black card
    adds no light): colour = black / alpha."""
    bg_b, bg_w = border_median(black), border_median(white)
    span = np.maximum(bg_w - bg_b, 1e-3)
    raw = 1.0 - np.clip((white - black) / span, 0, 1).mean(axis=2)
    core = raw[raw > 0.5]
    hi = float(np.clip(np.percentile(core, 90), 0.7, 1.0)) if core.size else 1.0
    lo = 0.08
    alpha = np.clip((raw - lo) / (hi - lo), 0, 1)
    a3 = alpha[..., None]
    colour = np.where(a3 > 0.03, (black - (1 - a3) * bg_b) / np.maximum(a3, 0.03), 0)
    return np.dstack([np.clip(colour, 0, 1), alpha])


def keep_main(alpha, thr=0.1, share=0.05):
    """clear specks and leftovers: keep the connected pieces that are at least `share` of the biggest (needs scipy; without it nothing is cleared)"""
    try:
        from scipy import ndimage
    except ImportError:
        return alpha
    lab, n = ndimage.label(alpha > thr)
    if n <= 1:
        return alpha
    areas = ndimage.sum(np.ones_like(alpha), lab, index=range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = areas >= areas.max() * share
    return np.where(keep[lab], alpha, 0)


def fit(rgba, size, margin=0.06):
    """crop to the outline, centre in a square with a margin, scale to size x size"""
    rgba = rgba.copy()
    rgba[..., 3] = keep_main(rgba[..., 3])
    a = rgba[..., 3]
    ys, xs = np.where(a > 0.1)
    if len(ys) == 0:
        return None
    img = Image.fromarray((rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1] * 255 + 0.5).astype(np.uint8), 'RGBA')
    side = max(img.size)
    inner = int(size * (1 - 2 * margin))
    k = inner / side
    img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(img, ((size - img.width) // 2, (size - img.height) // 2))
    return out


def load(path):
    return np.asarray(Image.open(path).convert('RGB'), dtype=np.float32) / 255.0


def do_matte(src, size):
    raw = os.path.join(src, 'raw')
    made, bad = 0, []
    for name in sorted(os.listdir(raw)):
        if not name.endswith('_b.png'):
            continue
        part = name[:-6]
        white = os.path.join(raw, part + '_w.png')
        if not os.path.exists(white):
            continue
        try:
            b, w = load(os.path.join(raw, name)), load(white)
            if b.shape != w.shape:
                raise ValueError('the two shots differ in size')
            out = fit(matte(b, w), size)
            if out is None:
                raise ValueError('nothing visible')
            out.save(os.path.join(src, part + '.png'), optimize=True)
            made += 1
        except Exception as e:  # a half-written file, an empty shot: list it and go on
            bad.append((part, str(e)))
    print('%d pictures made, %d failed' % (made, len(bad)))
    for part, why in bad:
        print('  ' + part + ': ' + why)
    return 0 if not bad else 1


def safe(name):
    return ''.join(c if c.isalnum() or c in '_-' else '_' for c in name)


def aliases(src, have):
    """parts drawn with the same meshes as one that has a picture: { part: the picture's name }, from the index the game wrote"""
    out = {}
    try:
        with open(os.path.join(src, 'index.json'), encoding='utf-8') as f:
            index = json.load(f)
    except (OSError, ValueError):
        return out
    for part, entry in index.items():
        canon = entry.get('alias') if isinstance(entry, dict) else None
        if canon and safe(canon) in have and safe(part) not in have:
            out[safe(part)] = safe(canon)
    return out


def do_ship(src, dest):
    os.makedirs(dest, exist_ok=True)
    parts, total = [], 0
    for name in sorted(os.listdir(src)):
        if not name.endswith('.png'):
            continue
        img = Image.open(os.path.join(src, name)).convert('RGBA')
        out = os.path.join(dest, name)
        # a palette PNG keeps the alpha at a fraction of the size
        img.quantize(colors=128, method=Image.FASTOCTREE, dither=Image.NONE).save(out, optimize=True)
        parts.append(name[:-4])
        total += os.path.getsize(out)
    alias = aliases(src, set(parts))
    with open(os.path.join(dest, 'manifest.json'), 'w', encoding='utf-8') as f:
        json.dump({'parts': parts, 'alias': alias}, f, separators=(',', ':'))
    print('%d pictures, %.1f KB in all (%.1f KB each), %d more parts share one -> %s' % (len(parts), total / 1024, total / 1024 / max(1, len(parts)), len(alias), dest))
    return 0


def selftest():
    h = w = 96
    yy, xx = np.mgrid[0:h, 0:w]
    disc = ((yy - 48) ** 2 + (xx - 40) ** 2) < 20 ** 2
    glass = ((yy - 60) ** 2 + (xx - 70) ** 2) < 10 ** 2
    alpha = np.where(disc, 1.0, np.where(glass, 0.4, 0.0))[..., None]
    fg = np.array([0.8, 0.2, 0.1])
    for bg_b, bg_w in (((0, 0, 0), (1, 1, 1)), ((0.02, 0.02, 0.03), (0.93, 0.94, 0.95))):
        b = alpha * fg + (1 - alpha) * np.array(bg_b)
        wh = alpha * fg + (1 - alpha) * np.array(bg_w) + alpha * 0.12      # (the white card bleeds some light onto the part)
        m = matte(b.astype(np.float32), wh.astype(np.float32))
        assert m[48, 40, 3] > 0.97 and np.allclose(m[48, 40, :3], fg, atol=0.05), 'opaque part'
        assert abs(m[60, 70, 3] - 0.4) < 0.12 and np.allclose(m[60, 70, :3], fg, atol=0.3), 'see-through part'
        assert m[2, 2, 3] < 0.01, 'background is clear'
        out = fit(m, 64)
        assert out.size == (64, 64) and out.getpixel((0, 0))[3] == 0 and out.getchannel('A').getextrema()[1] > 250, 'fitted square'
    print('part_shots selftest passed')
    return 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['matte', 'ship', 'selftest'])
    p.add_argument('--src', default=DEFAULT)
    p.add_argument('--dest')
    p.add_argument('--size', type=int, default=128)
    a = p.parse_args()
    if a.cmd == 'selftest':
        return selftest()
    if a.cmd == 'matte':
        return do_matte(a.src, a.size)
    if not a.dest:
        p.error('ship needs --dest')
    return do_ship(a.src, a.dest)


if __name__ == '__main__':
    sys.exit(main())
