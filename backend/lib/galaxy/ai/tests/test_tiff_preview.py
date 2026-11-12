"""
TIFF → PNG preview (galaxy/ai/tiff_preview.py) and its endpoint POST /api/perception/preview_image
(galaxy/webapps/galaxy/api/perception.py, ``preview_image_result``).

Renderer tests write synthetic TIFFs with tifffile and decode the PNG with Pillow; without those
libraries they are SKIPPED with the reason printed (the endpoint tests still run: refusals and the
503 degrade path need neither). The real dev-container check on Galaxy's own TIFF fixtures is the
read-only script described in docs (copied to the container's /tmp, run under python3.9, removed).

Run standalone:
    cd backend && python3.9 lib/galaxy/ai/tests/test_tiff_preview.py
"""
from __future__ import annotations

import importlib.util
import io
import json
import os
import sys
import tempfile
import types

_HERE = os.path.dirname(os.path.abspath(__file__))
_AI = os.path.abspath(os.path.join(_HERE, ".."))
_API = os.path.abspath(os.path.join(_HERE, "..", "..", "webapps", "galaxy", "api", "perception.py"))


def _load_perception():
    class Router:
        def __init__(self, **_kw):
            pass

        def post(self, *_a, **_kw):
            return lambda fn: fn

        get = post

    for name in ("galaxy", "galaxy.webapps", "galaxy.webapps.galaxy"):
        sys.modules.setdefault(name, types.ModuleType(name))
    api = types.ModuleType("galaxy.webapps.galaxy.api")
    api.Router = Router  # type: ignore[attr-defined]
    sys.modules["galaxy.webapps.galaxy.api"] = api
    ai = sys.modules.get("galaxy.ai")
    if ai is None or not hasattr(ai, "__path__"):
        ai = types.ModuleType("galaxy.ai")
        ai.__path__ = [_AI]  # type: ignore[attr-defined]
        sys.modules["galaxy.ai"] = ai
    sys.modules["galaxy"].__path__ = []  # type: ignore[attr-defined]
    spec = importlib.util.spec_from_file_location("_perception_preview_under_test", _API)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["_perception_preview_under_test"] = mod
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


P = _load_perception()
from galaxy.ai import tiff_preview as T  # noqa: E402 — loaded from the real file via galaxy.ai.__path__

try:
    import numpy as np
    import tifffile
    from PIL import Image

    LIBS = True
    LIBS_WHY = ""
except Exception as _exc:  # noqa: BLE001
    LIBS = False
    LIBS_WHY = f"numpy/tifffile/Pillow unavailable on this interpreter ({_exc})"

try:
    import pytest

    needs_libs = pytest.mark.skipif(not LIBS, reason=LIBS_WHY or "libs present")

    @pytest.fixture
    def d():
        with tempfile.TemporaryDirectory() as tmp:
            yield tmp
except ImportError:  # standalone
    def needs_libs(fn):
        fn._needs_libs = True  # type: ignore[attr-defined]
        return fn


def _png(png: bytes):
    im = Image.open(io.BytesIO(png))
    im.load()
    return im


# ─── renderer ───────────────────────────────────────────────────────────────────────────────

@needs_libs
def test_uint8_as_stored_and_uint16_stretched(d):
    a = np.arange(64 * 64, dtype=np.uint8).reshape(64, 64)
    tifffile.imwrite(os.path.join(d, "u8.tif"), a)
    png, info = T.render_tiff_preview(os.path.join(d, "u8.tif"))
    im = _png(png)
    assert im.mode == "L" and im.size == (64, 64) and info["stretch"] is None
    assert np.array_equal(np.asarray(im), a), "uint8 must be drawn exactly as stored"
    mask = np.zeros((16, 16), np.uint8)
    mask[4:8, 4:8] = 1  # a 0/1 mask stored as uint8 would draw all black as stored
    tifffile.imwrite(os.path.join(d, "mask.tif"), mask)
    png, info = T.render_tiff_preview(os.path.join(d, "mask.tif"))
    assert np.asarray(_png(png))[5, 5] == 255 and np.asarray(_png(png))[0, 0] == 0
    assert "low_range_uint8" in info["notes"] and info["stretch"]["high"] == [1.0]
    b = (np.arange(100 * 80, dtype=np.uint16) * 8).reshape(100, 80)
    b[0, 0] = 65535  # one hot pixel must not flatten the stretch (percentile, not min/max)
    tifffile.imwrite(os.path.join(d, "u16.tif"), b)
    png, info = T.render_tiff_preview(os.path.join(d, "u16.tif"))
    arr = np.asarray(_png(png))
    assert info["dtype"] == "uint16" and info["stretch"]["percentiles"] == [0.5, 99.5]
    lo, hi = info["stretch"]["low"][0], info["stretch"]["high"][0]
    assert 0 < lo < 1000 and 60000 < hi < 65000, info["stretch"]
    assert arr.min() == 0 and arr.max() == 255 and len(np.unique(arr)) > 200
    print("PASS test_uint8_as_stored_and_uint16_stretched")


@needs_libs
def test_float_nan_signed_and_constant(d):
    f = np.random.RandomState(0).rand(40, 40).astype(np.float32)
    f[5, :] = np.nan
    f[6, :] = np.inf
    tifffile.imwrite(os.path.join(d, "f.tif"), f)
    png, info = T.render_tiff_preview(os.path.join(d, "f.tif"))
    assert info["dtype"] == "float32" and info["stretch"]["high"][0] <= 1.0
    assert np.asarray(_png(png))[5].max() == 0  # NaN → the low end, not garbage
    i = (np.random.RandomState(1).randn(32, 32) * 1000).astype(np.int16)
    tifffile.imwrite(os.path.join(d, "i.tif"), i)
    _, info = T.render_tiff_preview(os.path.join(d, "i.tif"))
    assert info["dtype"] == "int16" and info["stretch"]["low"][0] < 0
    tifffile.imwrite(os.path.join(d, "z.tif"), np.zeros((10, 12), np.uint16))
    png, info = T.render_tiff_preview(os.path.join(d, "z.tif"))
    assert "constant" in info["notes"] and np.asarray(_png(png)).max() == 0
    allnan = np.full((8, 8), np.nan, np.float32)
    tifffile.imwrite(os.path.join(d, "n.tif"), allnan)
    _, info = T.render_tiff_preview(os.path.join(d, "n.tif"))
    assert "no_finite_values" in info["notes"], info["notes"]
    print("PASS test_float_nan_signed_and_constant")


@needs_libs
def test_channels_rgb_and_many(d):
    rgb = np.zeros((20, 30, 3), np.uint8)
    rgb[..., 0] = 200
    tifffile.imwrite(os.path.join(d, "rgb.tif"), rgb, photometric="rgb")
    png, info = T.render_tiff_preview(os.path.join(d, "rgb.tif"))
    im = _png(png)
    assert im.mode == "RGB" and info["channelsShown"] == 3 and tuple(np.asarray(im)[0, 0]) == (200, 0, 0)
    two = np.random.RandomState(2).randint(0, 4000, (2, 16, 16)).astype(np.uint16)
    tifffile.imwrite(os.path.join(d, "c2.tif"), two, imagej=True, metadata={"axes": "CYX"})
    png, info = T.render_tiff_preview(os.path.join(d, "c2.tif"))
    a = np.asarray(_png(png))
    assert info["channels"] == 2 and a.shape == (16, 16, 3) and a[..., 2].max() == 0  # R+G, empty B
    five = np.random.RandomState(3).randint(0, 4000, (5, 16, 16)).astype(np.uint16)
    tifffile.imwrite(os.path.join(d, "c5.tif"), five, imagej=True, metadata={"axes": "CYX"})
    png, info = T.render_tiff_preview(os.path.join(d, "c5.tif"))
    assert _png(png).mode == "L" and info["channels"] == 5 and "first_of_5_channels" in info["notes"]
    print("PASS test_channels_rgb_and_many")


@needs_libs
def test_pages_series_and_page_reads_match(d):
    z = np.random.RandomState(4).randint(0, 4000, (30, 2, 32, 32)).astype(np.uint16)
    p = os.path.join(d, "zc.tif")
    tifffile.imwrite(p, z, imagej=True, metadata={"axes": "ZCYX"})
    _, info = T.render_tiff_preview(p, page=7)
    assert (info["planeCount"], info["plane"], info["planeAxes"], info["channelsShown"]) == (30, 7, "Z", 2)
    # The page-per-plane path reads only plane 7's two pages; reading the series whole and indexing
    # it draws the same picture, and the page path also works under a budget of one plane.
    paged, info2 = T.render_tiff_preview(p, page=7, max_read_bytes=32 * 32 * 2 * 2)
    real = T._page_based
    T._page_based = lambda *_a: False
    try:
        whole, _ = T.render_tiff_preview(p, page=7)
    finally:
        T._page_based = real
    assert whole == paged and info2["plane"] == 7
    try:
        T.render_tiff_preview(p, page=30)
        raise AssertionError("page 30 of 30 must be refused")
    except T.TiffPreviewError as e:
        assert (e.code, e.status) == ("invalid_selection", 400)
    ms = os.path.join(d, "ms.tif")
    with tifffile.TiffWriter(ms) as w:
        w.write(np.zeros((8, 8), np.uint8))
        w.write(np.ones((4, 4), np.uint16))
    _, info = T.render_tiff_preview(ms)
    assert info["seriesCount"] == 2 and info["series"] == 0 and "first_series" in info["notes"]
    _, info = T.render_tiff_preview(ms, series=1)
    assert info["dtype"] == "uint16" and info["shape"] == [4, 4]
    print("PASS test_pages_series_and_page_reads_match")


@needs_libs
def test_pyramid_level_and_budget(d):
    base = np.random.RandomState(5).randint(0, 65535, (4096, 3000)).astype(np.uint16)
    p = os.path.join(d, "pyr.ome.tif")
    with tifffile.TiffWriter(p, bigtiff=True, ome=True) as w:
        w.write(base, subifds=2, tile=(256, 256), metadata={"axes": "YX"})
        w.write(base[::2, ::2], subfiletype=1, tile=(256, 256))
        w.write(base[::4, ::4], subfiletype=1, tile=(256, 256))
    png, info = T.render_tiff_preview(p)
    assert info["format"] == "ome-tiff" and info["bigtiff"] is True
    assert (info["level"], info["levelCount"], info["levelShape"]) == (2, 3, [1024, 750]), info
    assert max(_png(png).size) <= 1024
    flat = os.path.join(d, "flat.tif")
    tifffile.imwrite(flat, np.zeros((3000, 2500), np.uint8))
    png, info = T.render_tiff_preview(flat)
    assert _png(png).size == (853, 1024)  # downscaled to 1024 on the long side
    try:
        T.render_tiff_preview(flat, max_read_bytes=1_000_000)
        raise AssertionError("an over-budget plane without a pyramid must be refused")
    except T.TiffPreviewError as e:
        assert (e.code, e.status) == ("too_large", 413) and "2500 × 3000" in e.reason, e.reason
    print("PASS test_pyramid_level_and_budget")


@needs_libs
def test_empty_and_not_tiff(d):
    for name, data, code in (("e.tif", b"", "empty_image"), ("t.tif", b"hello", "not_tiff"),
                             ("h.tif", b"II*\x00\x00\x00\x00\x00", "empty_image"),  # header, no IFD
                             ("x.tif", b"II*\x00\x08\x00\x00\x00\x00\x00", "unreadable")):  # truncated IFD
        open(os.path.join(d, name), "wb").write(data)
        try:
            T.render_tiff_preview(os.path.join(d, name))
            raise AssertionError(f"{name} must be refused")
        except T.TiffPreviewError as e:
            # a truncated IFD reads as "no pixels" on newer tifffile releases, as a decode error on older
            assert e.code == code or (name == "x.tif" and e.code == "empty_image"), (name, e.code, e.reason)
    print("PASS test_empty_and_not_tiff")


@needs_libs
def test_compressed_tiff_decoded_by_pillow_without_imagecodecs(d):
    # LZW / PackBits need the optional imagecodecs package in tifffile (absent on the dev Galaxy
    # container); Pillow's libtiff decodes them. Force that path and check the exact pixels.
    pages = [((np.arange(24 * 32).reshape(24, 32) + 40 * k) % 256).astype(np.uint8) for k in range(3)]
    p = os.path.join(d, "lzw.tif")
    Image.fromarray(pages[0]).save(p, compression="tiff_lzw", save_all=True,
                                   append_images=[Image.fromarray(a) for a in pages[1:]])
    rgb = os.path.join(d, "rgb_packbits.tif")
    rgb_a = np.dstack([pages[0], pages[1], pages[2]])
    Image.fromarray(rgb_a).save(rgb, compression="packbits")
    real = (tifffile.TiffFile.asarray, tifffile.TiffPageSeries.asarray)

    def no_codecs(*_a, **_kw):
        raise ValueError("<COMPRESSION.LZW: 5> requires the 'imagecodecs' package")

    tifffile.TiffFile.asarray = no_codecs
    tifffile.TiffPageSeries.asarray = no_codecs
    try:
        png, info = T.render_tiff_preview(p, page=2)
        assert "decoded_by_pillow" in info["notes"] and info["planeCount"] == 3, info
        assert np.array_equal(np.asarray(_png(png)), pages[2])
        png, info = T.render_tiff_preview(rgb)
        assert info["channelsShown"] == 3 and np.array_equal(np.asarray(_png(png)), rgb_a)
    finally:
        tifffile.TiffFile.asarray, tifffile.TiffPageSeries.asarray = real
    png, info = T.render_tiff_preview(p, page=1)  # whichever decoder this interpreter has
    assert np.array_equal(np.asarray(_png(png)), pages[1])
    # CCITT G4 fax (Galaxy's 1.tiff fixture): no tifffile decoder at all; black marks stay black.
    bw = np.ones((40, 60), bool)
    bw[10:20, 5:50] = False
    g4 = os.path.join(d, "g4.tif")
    Image.fromarray(bw).save(g4, compression="group4")
    png, info = T.render_tiff_preview(g4)
    drawn = np.asarray(_png(png))
    assert info["dtype"] == "bool" and drawn[15, 20] == 0 and drawn[0, 0] == 255, (info, drawn[15, 20], drawn[0, 0])
    print("PASS test_compressed_tiff_decoded_by_pillow_without_imagecodecs")


# ─── endpoint ───────────────────────────────────────────────────────────────────────────────

PID = "11111111-1111-4111-8111-111111111111"


class _S3Calls:
    def __init__(self, files):
        self.files, self.calls = files, []

    def install(self):
        saved = (P._s3_size, P._cached_s3_path)
        P._s3_size = lambda b, k: self.calls.append(("head", b, k)) or (
            os.path.getsize(self.files[k]) if k in self.files else None)
        P._cached_s3_path = lambda b, k: self.calls.append(("get", b, k)) or self.files.get(k)
        return saved

    @staticmethod
    def restore(saved):
        P._s3_size, P._cached_s3_path = saved


def test_endpoint_refuses_refs_outside_the_project(d):
    s3 = _S3Calls({})
    saved = s3.install()
    try:
        for ref in ("/etc/passwd", "file:///etc/passwd", "../x.tif", f"s3://other-bucket/projects/{PID}/a.tif",
                    "projects/22222222-2222-4222-8222-222222222222/inputs/a.tif", f"projects/{PID}/../x/a.tif",
                    "nextflow/run/a.tif", None):
            status, _h, body = P.preview_image_result(P.PreviewImageRequest(projectId=PID, datasetRef=ref))
            assert status == 403 and body["error"] == "ref_refused", (ref, status, body)
        status, _h, body = P.preview_image_result(P.PreviewImageRequest(datasetRef=f"projects/{PID}/a.tif"))
        assert status == 403, "no projectId → nothing is read"
        assert s3.calls == [], f"a refused ref must touch nothing: {s3.calls}"
    finally:
        s3.restore(saved)
    print("PASS test_endpoint_refuses_refs_outside_the_project")


def test_endpoint_degrades_to_503_without_libs(d):
    s3 = _S3Calls({f"projects/{PID}/inputs/a.tif": os.path.join(d, "a.tif")})
    saved, libs = s3.install(), T._libs

    def missing():
        raise T.TiffPreviewError("preview_unavailable", 503, "TIFF rendering libraries are not installed")

    T._libs = missing
    try:
        status, _h, body = P.preview_image_result(P.PreviewImageRequest(projectId=PID, datasetRef=f"projects/{PID}/inputs/a.tif"))
        assert (status, body["error"]) == (503, "preview_unavailable"), (status, body)
        assert s3.calls == [], "nothing is downloaded when it cannot be drawn"
    finally:
        T._libs = libs
        s3.restore(saved)
    print("PASS test_endpoint_degrades_to_503_without_libs")


@needs_libs
def test_endpoint_renders_a_project_object(d):
    key = f"projects/{PID}/inputs/stack.tif"
    p = os.path.join(d, "stack.tif")
    tifffile.imwrite(p, np.random.RandomState(6).randint(0, 4000, (3, 20, 24)).astype(np.uint16), photometric="minisblack")
    big = os.path.join(d, "big.tif")
    s3 = _S3Calls({key: p, f"projects/{PID}/inputs/big.tif": big, f"projects/{PID}/inputs/t.txt": os.path.join(d, "t.txt")})
    open(os.path.join(d, "t.txt"), "w").write("not a tiff")
    saved, cap = s3.install(), P.MAX_PREVIEW_INPUT_BYTES
    try:
        status, headers, body = P.preview_image_result(P.PreviewImageRequest(projectId=PID, datasetRef=key))
        assert status == 200 and body[:8] == b"\x89PNG\r\n\x1a\n"
        info = json.loads(headers["X-Preview-Info"])
        assert (info["planeCount"], info["dtype"], info["shape"]) == (3, "uint16", [3, 20, 24]) and info["stretch"]
        status, _h, body = P.preview_image_result(P.PreviewImageRequest(projectId=PID, datasetRef=f"s3://{P._default_bucket()}/{key}", page=2))
        assert status == 200
        status, _h, body = P.preview_image_result(P.PreviewImageRequest(projectId=PID, datasetRef=f"projects/{PID}/inputs/t.txt"))
        assert (status, body["error"]) == (415, "not_tiff"), body
        status, _h, body = P.preview_image_result(P.PreviewImageRequest(projectId=PID, datasetRef=f"projects/{PID}/inputs/gone.tif"))
        assert (status, body["error"]) == (404, "unresolvable_ref")
        tifffile.imwrite(big, np.zeros((64, 64), np.uint8))
        P.MAX_PREVIEW_INPUT_BYTES = 1000
        n = len(s3.calls)
        status, _h, body = P.preview_image_result(P.PreviewImageRequest(projectId=PID, datasetRef=f"projects/{PID}/inputs/big.tif"))
        assert (status, body["error"]) == (413, "too_large") and [c[0] for c in s3.calls[n:]] == ["head"], s3.calls[n:]
    finally:
        P.MAX_PREVIEW_INPUT_BYTES = cap
        s3.restore(saved)
    print("PASS test_endpoint_renders_a_project_object")


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    skipped = 0
    with tempfile.TemporaryDirectory() as d:
        for t in tests:
            if getattr(t, "_needs_libs", False) and not LIBS:
                print(f"SKIP {t.__name__}: {LIBS_WHY}")
                skipped += 1
                continue
            sub = tempfile.mkdtemp(dir=d)
            t(sub)
    print(f"\n{len(tests) - skipped} TIFF preview tests passed, {skipped} skipped.")


if __name__ == "__main__":
    main()
