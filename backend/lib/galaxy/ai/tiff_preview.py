"""
TIFF / OME-TIFF / BigTIFF → 8-bit PNG preview, for the dataset panel (browsers cannot draw TIFF).

:func:`render_tiff_preview` reads ONE image plane of a TIFF — the first (or a chosen) plane of the
first (or a chosen) series — and returns ``(png_bytes, info)``:

* any dtype: ``uint8`` is shown as stored (a 0–15 mask / label image is min–max stretched);
  ``bool`` as black/white; every other dtype (uint16,
  signed ints, floats, complex magnitude) is contrast-stretched between its 0.5th and 99.5th
  percentiles (finite values only). The stretch is reported in ``info["stretch"]``.
* channels: up to 3 channels (an RGB page's samples or an OME ``C`` axis) are drawn as RGB
  (2 channels → red + green); with more, the first channel is drawn and ``notes`` says so.
* multi-page / multi-series: the first plane is drawn; ``planeCount`` / ``seriesCount`` /
  ``pageCount`` say how many there are.
* huge images: a pyramidal OME-TIFF is read at the smallest level that still covers
  ``max_side``; anything else whose selected plane needs more than ``MAX_READ_BYTES`` is refused
  (:class:`TiffPreviewError` ``too_large``) rather than read.
* empty files / zero-sized images are refused (``empty_image``); a constant image is drawn
  (black, or white for a nonzero constant) and flagged ``constant``.

numpy, tifffile and Pillow are imported lazily: without them :func:`preview_available` is False
and the render raises ``preview_unavailable`` (the endpoint answers 503). No network, no LLM.
"""
# CRITICAL: keep this first (Python 3.9 + PEP 604 annotations).
from __future__ import annotations

import io
import math
import os
from typing import Any, Dict, List, Optional, Tuple

MAX_SIDE = 1024
# Raw (decoded) bytes one preview may read: the selected plane(s) of the chosen level, or — for a
# series stored as one contiguous block (ImageJ hyperstacks) — the whole series.
MAX_READ_BYTES = 256 * 1024 * 1024
PERCENTILES = (0.5, 99.5)
# Pixels the percentile is computed over (a strided sample of the plane beyond this).
_STRETCH_SAMPLE = 4_000_000


# TIFF PhotometricInterpretation tag values (the enum's home moved between tifffile releases).
_PH_MINISWHITE, _PH_RGB, _PH_PALETTE, _PH_YCBCR = 0, 2, 3, 6


class TiffPreviewError(Exception):
    """A preview that cannot be drawn: ``code`` (machine), ``status`` (HTTP), ``reason`` (human)."""

    def __init__(self, code: str, status: int, reason: str):
        super().__init__(reason)
        self.code = code
        self.status = status
        self.reason = reason


def _libs():
    """(numpy, tifffile, PIL.Image) or raise preview_unavailable."""
    try:
        import numpy as np
        import tifffile
        from PIL import Image
    except Exception as exc:  # noqa: BLE001 — ImportError or a broken binary wheel
        raise TiffPreviewError("preview_unavailable", 503,
                               f"TIFF rendering libraries are not installed on this server ({exc})")
    return np, tifffile, Image


def preview_available() -> bool:
    try:
        _libs()
        return True
    except TiffPreviewError:
        return False


def _prod(xs) -> int:
    n = 1
    for x in xs:
        n *= int(x)
    return n


def _levels(series) -> List[Any]:
    lv = getattr(series, "levels", None)
    return list(lv) if lv else [series]


def _yx(shape, axes) -> Optional[Tuple[int, int]]:
    if "Y" not in axes or "X" not in axes:
        return None
    return int(shape[axes.index("Y")]), int(shape[axes.index("X")])


def _pick_level(levels, axes: str, max_side: int):
    """(index of the pyramid level to read, each level's (Y, X)): the smallest level whose long
    side still covers ``max_side`` (level 0 when the base is already small). The caller steps
    further down while the plane is over the read budget."""
    sizes = [_yx(tuple(lv.shape), axes) for lv in levels]
    choice = 0
    for i, yx in enumerate(sizes):
        if yx and max(yx) >= max_side:
            choice = i
    return choice, sizes


def _color_axis(axes: str, shape, photometric_rgb: bool) -> Optional[str]:
    """The axis drawn as colour: an RGB page's samples ``S``, else an OME/ImageJ channel axis
    ``C``, else ``S`` of any other multi-sample page."""
    has_s = "S" in axes and int(shape[axes.index("S")]) > 1
    has_c = "C" in axes and int(shape[axes.index("C")]) > 1
    if has_s and (photometric_rgb or not has_c):
        return "S"
    if has_c:
        return "C"
    return None


def _plane_index(axes: str, shape, color: Optional[str], plane: int):
    """{axis: index} for every non-Y/X/colour axis from a flat ``plane`` number (C order), plus
    the plane axes and count."""
    paxes = [a for a in axes if a not in ("Y", "X") and a != color]
    psizes = [int(shape[axes.index(a)]) for a in paxes]
    count = _prod(psizes)
    if plane < 0 or plane >= max(count, 1):
        raise TiffPreviewError("invalid_selection", 400, f"page {plane} is out of range (this series has {count})")
    idx: Dict[str, int] = {}
    rem = plane
    for a, n in reversed(list(zip(paxes, psizes))):
        idx[a] = rem % n if n else 0
        rem //= n if n else 1
    return idx, "".join(paxes), count


def _to_float(np, a):
    if np.iscomplexobj(a):
        a = np.abs(a)
    return a.astype(np.float32, copy=False)


def _stretch(np, chans: List[Any]) -> Tuple[List[Any], List[float], List[float], bool, bool]:
    """Percentile-stretch each float32 array in ``chans`` to uint8 with its own low/high pair.
    Returns (uint8 arrays, lows, highs, every array constant, any finite value seen)."""
    out, lows, highs = [], [], []
    constant = True
    any_finite = False
    for a in chans:
        flat = a.reshape(-1)
        if flat.size > _STRETCH_SAMPLE:
            flat = flat[:: int(math.ceil(flat.size / _STRETCH_SAMPLE))]
        fin = flat[np.isfinite(flat)]
        if fin.size == 0:
            out.append(np.zeros(a.shape, dtype=np.uint8))
            lows.append(float("nan"))
            highs.append(float("nan"))
            continue
        any_finite = True
        lo, hi = (float(v) for v in np.percentile(fin, PERCENTILES))
        if not hi > lo:  # the percentiles collapsed: fall back to the full finite range
            lo, hi = float(fin.min()), float(fin.max())
        lows.append(lo)
        highs.append(hi)
        if hi > lo:
            constant = False
            b = (np.nan_to_num(a, nan=lo, posinf=hi, neginf=lo) - lo) * (255.0 / (hi - lo))
            out.append(np.clip(b, 0, 255).astype(np.uint8))
        else:
            out.append(np.full(a.shape, 255 if lo != 0 else 0, dtype=np.uint8))
    return out, lows, highs, constant, any_finite


def _mib(n: int) -> str:
    return f"{n / 2**20:.0f} MiB" if n >= 2**20 else f"{n / 1024:.0f} KiB"


# uint8 whose values all sit below this (and are not constant) is a mask / label image, not a picture.
_U8_LOW_RANGE = 16


def _low_range_u8(chans) -> bool:
    hi = max(int(c.max()) for c in chans)
    lo = min(int(c.min()) for c in chans)
    return hi < _U8_LOW_RANGE and hi > lo


def _sig(x: float) -> Optional[float]:
    if x is None or not math.isfinite(x):
        return None
    return float(f"{x:.6g}")


def render_tiff_preview(path: str, series: int = 0, page: int = 0, max_side: int = MAX_SIDE,
                        max_read_bytes: int = MAX_READ_BYTES) -> Tuple[bytes, Dict[str, Any]]:
    """Render one plane of the TIFF at ``path`` to PNG. Raises :class:`TiffPreviewError`."""
    np, tifffile, Image = _libs()
    try:
        if os.path.getsize(path) == 0:
            raise TiffPreviewError("empty_image", 422, "the file is empty")
    except OSError:
        raise TiffPreviewError("unreadable", 422, "the file could not be read")
    try:
        tf = tifffile.TiffFile(path)
    except Exception as exc:  # noqa: BLE001 — not a TIFF / truncated header
        msg = str(exc)
        if "contains no pages" in msg:
            raise TiffPreviewError("empty_image", 422, "the TIFF holds no image pages")
        raise TiffPreviewError("not_tiff", 415, f"not a readable TIFF ({msg[:200]})")
    with tf:
        try:
            return _render(np, Image, tf, path, series, page, max_side, max_read_bytes)
        except TiffPreviewError:
            raise
        except MemoryError:
            raise TiffPreviewError("too_large", 413, "the image does not fit in the preview's memory")
        except Exception as exc:  # noqa: BLE001 — a malformed IFD chain, unsupported compression, …
            raise TiffPreviewError("unreadable", 422, f"the TIFF could not be decoded ({str(exc)[:200]})")


def _render(np, Image, tf, path: str, series: int, page: int, max_side: int,
            max_read_bytes: int) -> Tuple[bytes, Dict[str, Any]]:
    all_series = list(tf.series)
    if not all_series or not len(tf.pages):
        raise TiffPreviewError("empty_image", 422, "the TIFF holds no image pages")
    if series < 0 or series >= len(all_series):
        raise TiffPreviewError("invalid_selection", 400,
                               f"series {series} is out of range (this file has {len(all_series)})")
    s = all_series[series]
    axes = str(s.axes)
    shape = tuple(int(x) for x in s.shape)
    dtype = np.dtype(s.dtype)
    if not shape or _prod(shape) == 0:
        raise TiffPreviewError("empty_image", 422, f"the image has no pixels (shape {list(shape)})")
    if _yx(shape, axes) is None:
        raise TiffPreviewError("unsupported_layout", 422, f"no 2-D image plane in axes {axes!r}")
    key = s.keyframe if getattr(s, "keyframe", None) is not None else s.pages[0]
    photometric = int(getattr(key, "photometric", -1))
    rgb = photometric in (_PH_RGB, _PH_YCBCR)
    notes: List[str] = []

    levels = _levels(s)
    lvl, lsizes = _pick_level(levels, axes, max_side)
    color = _color_axis(axes, shape, rgb)
    n_color = int(shape[axes.index(color)]) if color else 1
    if color and n_color > 3 and not (color == "S" and rgb):
        color_take = [0]
        notes.append(f"first_of_{n_color}_channels")
    elif color:
        color_take = list(range(min(n_color, 3)))
        if n_color > 3:
            notes.append("extra_samples_ignored")
    else:
        color_take = [0]
    idx, plane_axes, plane_count = _plane_index(axes, shape, color, page)

    def plane_bytes(i: int) -> int:
        y, x = lsizes[i]
        return y * x * len(color_take) * dtype.itemsize

    # Step to a smaller pyramid level while the plane is over budget.
    while plane_bytes(lvl) > max_read_bytes and lvl + 1 < len(levels):
        lvl += 1
    if plane_bytes(lvl) > max_read_bytes:
        y, x = lsizes[lvl]
        raise TiffPreviewError(
            "too_large", 413,
            f"the image plane is {x} × {y} px ({_mib(plane_bytes(lvl))} decoded) and the file has no smaller "
            f"pyramid level; the preview reads at most {_mib(max_read_bytes)}")
    level = levels[lvl]
    lshape = tuple(int(v) for v in level.shape)
    series_bytes = _prod(lshape) * dtype.itemsize

    try:
        try:
            if len(level.pages) > 1 and _page_based(level, axes, lshape):
                # One page per plane (Z-stacks, OME channels): read only the selected plane's pages.
                plane, rest = _read_pages(np, tf, s, level, lvl, series, axes, lshape, idx, color, color_take)
            elif series_bytes <= max_read_bytes:
                # One page, or a contiguous block (ImageJ hyperstack): read it whole and index the plane.
                arr = np.asarray(level.asarray())
                if arr.shape != lshape:
                    arr = arr.reshape(lshape)
                sl = tuple(idx.get(a, slice(None)) for a in axes)
                plane = arr[sl]
                rest = "".join(a for a in axes if a not in idx)
            else:
                plane, rest = _read_pages(np, tf, s, level, lvl, series, axes, lshape, idx, color, color_take)
        except TiffPreviewError:
            raise
        except Exception as exc:  # noqa: BLE001
            # tifffile has no decoder for this compression (LZW / JPEG / … need the optional
            # imagecodecs package; CCITT fax is never built in): Pillow's libtiff decodes them.
            # Only the selected plane's own pages are read; if Pillow fails too, tifffile's error
            # is the one reported.
            try:
                plane, rest = _read_pages(np, tf, s, level, lvl, series, axes, lshape, idx, color, color_take,
                                          pil=(Image, path))
            except Exception:  # noqa: BLE001
                raise exc
            notes.append("decoded_by_pillow")
    except TiffPreviewError:
        raise
    except Exception as exc:  # noqa: BLE001 — unsupported compression, truncated strips, …
        raise TiffPreviewError("unreadable", 422, f"the image data could not be decoded ({str(exc)[:200]})")

    # plane axes now: Y, X and (maybe) the colour axis, in file order → (Y, X[, C]).
    order = [rest.index("Y"), rest.index("X")] + ([rest.index(color)] if color and color in rest else [])
    plane = np.transpose(plane, order)
    if plane.ndim == 3:
        plane = plane[..., color_take] if plane.shape[2] != len(color_take) else plane
    h0, w0 = int(plane.shape[0]), int(plane.shape[1])
    step = max(1, int(max(h0, w0) // (2 * max_side)))
    if step > 1:
        plane = plane[::step, ::step]
    chans = [plane] if plane.ndim == 2 else [plane[..., i] for i in range(plane.shape[2])]

    stretch: Optional[Dict[str, Any]] = None
    constant = False
    palette = photometric == _PH_PALETTE and getattr(key, "colormap", None) is not None \
        and dtype.kind == "u" and dtype.itemsize <= 2 and plane.ndim == 2
    if palette:
        cmap = np.asarray(key.colormap)
        cmap8 = (cmap >> 8).astype(np.uint8) if cmap.max() > 255 else cmap.astype(np.uint8)
        ind = np.clip(plane.astype(np.int64), 0, cmap8.shape[1] - 1)
        out8 = [cmap8[0][ind], cmap8[1][ind], cmap8[2][ind]]
        constant = bool(plane.min() == plane.max())
        notes.append("palette")
    elif dtype == np.bool_:
        out8 = [c.astype(np.uint8) * 255 for c in chans]
        constant = all(bool(c.min() == c.max()) for c in chans)
    elif dtype == np.uint8 and not _low_range_u8(chans):
        out8 = [np.ascontiguousarray(c) for c in chans]
        constant = all(bool(c.min() == c.max()) for c in chans)
    elif dtype == np.uint8:
        # A label mask / 0–1 image stored as uint8 draws black as stored: its few levels are spread
        # over 0–255 (one min–max map for all channels) and the stretch is reported like any other.
        lo = float(min(int(c.min()) for c in chans))
        hi = float(max(int(c.max()) for c in chans))
        out8 = [((c.astype(np.float32) - lo) * (255.0 / (hi - lo))).astype(np.uint8) for c in chans]
        stretch = {"percentiles": [0, 100], "low": [lo] * len(chans), "high": [hi] * len(chans)}
        notes.append("low_range_uint8")
    else:
        f = [_to_float(np, c) for c in chans]
        if np.iscomplexobj(plane):
            notes.append("complex_magnitude")
        if color == "S" and rgb and len(f) > 1:
            # One stretch for the RGB samples together: keeps the colour balance.
            stacked = np.stack(f, axis=-1)
            (s8,), lows, highs, constant, finite = _stretch(np, [stacked])
            out8 = [s8[..., i] for i in range(s8.shape[-1])]
            lows, highs = lows * len(f), highs * len(f)
        else:  # each channel (fluorescence) is stretched on its own
            out8, lows, highs, constant, finite = _stretch(np, f)
        if not finite:
            notes.append("no_finite_values")
        stretch = {"percentiles": list(PERCENTILES), "low": [_sig(v) for v in lows],
                   "high": [_sig(v) for v in highs]}
    if constant:
        notes.append("constant")
    # tifffile returns stored values; Pillow already applies MinIsWhite (its "1;I" / "L;I" modes).
    if photometric == _PH_MINISWHITE and not palette and "decoded_by_pillow" not in notes:
        out8 = [255 - c for c in out8]
        notes.append("inverted_miniswhite")

    if len(out8) == 1:
        img = Image.fromarray(np.ascontiguousarray(out8[0]))  # uint8 2-D → "L"
    else:
        while len(out8) < 3:
            out8.append(np.zeros_like(out8[0]))
        img = Image.fromarray(np.ascontiguousarray(np.stack(out8[:3], axis=-1)))  # → "RGB"
    resample = getattr(getattr(Image, "Resampling", Image), "LANCZOS")
    img.thumbnail((max_side, max_side), resample)
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=False)

    if len(all_series) > 1:
        notes.append("first_series" if series == 0 else "chosen_series")
    info: Dict[str, Any] = {
        "format": "ome-tiff" if getattr(tf, "is_ome", False) else "tiff",
        "bigtiff": bool(getattr(tf, "is_bigtiff", False)),
        "seriesCount": len(all_series),
        "series": series,
        "pageCount": len(tf.pages),
        "planeCount": plane_count,
        "plane": page,
        "planeAxes": plane_axes,
        "axes": axes,
        "shape": list(shape),
        "dtype": str(dtype),
        "channels": n_color,
        "channelsShown": len(color_take),
        "colorAxis": color,
        "level": lvl,
        "levelCount": len(levels),
        "levelShape": list(lshape),
        "width": img.width,
        "height": img.height,
        "stretch": stretch,
        "constant": constant,
        "notes": notes,
    }
    return buf.getvalue(), info


def _page_based(level, axes: str, lshape) -> bool:
    """Each plane of ``level`` is its own page(s): the series axes end with the page axes and the
    leading axes enumerate the pages."""
    pages = level.pages
    kf = level.keyframe if getattr(level, "keyframe", None) is not None else pages[0]
    page_axes = str(kf.axes)
    lead = len(axes) - len(page_axes)
    return lead >= 0 and axes.endswith(page_axes) and _prod(lshape[:lead]) == len(pages)


def _read_pages(np, tf, s, level, lvl, series, axes, lshape, idx, color, color_take, pil=None):
    """Read only the pages that hold the selected plane of a page-per-plane series — one page, or
    one per drawn channel when the colour axis spans pages. Returns (array, its axes: Y, X and the
    colour axis when present). ``pil=(Image, path)`` decodes those pages with Pillow instead of
    tifffile (top-level pages only: a pyramid's SubIFD levels are out of its reach)."""
    pages = list(level.pages)
    kf = level.keyframe if getattr(level, "keyframe", None) is not None else pages[0]
    page_axes = str(kf.axes)
    lead_axes = axes[: len(axes) - len(page_axes)]
    if not _page_based(level, axes, lshape):
        if pil is not None:
            raise TiffPreviewError("unreadable", 422, "the image uses a compression this server cannot decode")
        raise TiffPreviewError(
            "too_large", 413,
            f"the series is stored as one {_mib(_prod(lshape) * np.dtype(s.dtype).itemsize)} block, more than "
            f"the preview reads")
    lead_shape = lshape[: len(lead_axes)]
    keys = []
    color_in_lead = color is not None and color in lead_axes
    for c in (color_take if color_in_lead else [None]):
        pos = [c if a == color else idx.get(a, 0) for a in lead_axes]
        keys.append(int(np.ravel_multi_index(tuple(pos), lead_shape)) if lead_axes else 0)
    if pil is None:
        data = np.asarray(tf.asarray(key=keys, series=series, level=lvl))
        page_shape = tuple(int(v) for v in kf.shape)
        data = data.reshape(((len(keys),) if len(keys) > 1 else ()) + page_shape)
    else:
        Image, path = pil
        ifds = [getattr(pages[k], "index", None) for k in keys]
        if any(not isinstance(i, int) for i in ifds):
            raise TiffPreviewError("unreadable", 422, "the image uses a compression this server cannot decode")
        got = []
        with Image.open(path) as im:
            for i in ifds:
                im.seek(i)
                got.append(np.asarray(im))
        data = got[0] if len(got) == 1 else np.stack(got)
        # Pillow gives a page as (Y, X) or (Y, X, S) whatever the planar configuration.
        page_axes = "YXS" if got[0].ndim == 3 else "YX"
    rest = (color if len(keys) > 1 else "") + page_axes
    sl = tuple(idx.get(a, slice(None)) if a not in ("Y", "X") and a != color else slice(None) for a in rest)
    data = data[sl]
    rest = "".join(a for a in rest if a in ("Y", "X") or a == color)
    return data, rest
