"""Self-contained tests for radiomics_extract.py. Ground truth is analytic or computed independently with
numpy; nothing is compared against the tool's own output except for equivalence and invariance checks."""
import csv, hashlib, json, os, sys
import numpy as np
import pytest
import SimpleITK as sitk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import radiomics_extract as rx  # noqa: E402
import merge_features as mf  # noqa: E402


def run(argv):
    return rx.main(argv)


def load_wide(outdir):
    with open(os.path.join(outdir, "features_wide.csv"), newline="") as fh:
        rows = list(csv.DictReader(fh))
    return rows


def feat(outdir, name, row=0):
    return float(load_wide(outdir)[row][name])


def sphere(shape, center, r):
    z, y, x = np.indices(shape)
    return ((z - center[0]) ** 2 + (y - center[1]) ** 2 + (x - center[2]) ** 2 <= r * r).astype(np.uint8)


def save_nii(arr, path, spacing=(1, 1, 1), origin=(0, 0, 0), direction=None, dtype=np.float32):
    img = sitk.GetImageFromArray(arr.astype(dtype))
    img.SetSpacing(spacing); img.SetOrigin(origin)
    if direction is not None:
        img.SetDirection(direction)
    sitk.WriteImage(img, str(path))
    return img


def write_dicom_series(stored, spacing, outdir, slope=1.0, intercept=0.0, origin=(10.0, -20.0, 5.0),
                       uid="1.2.826.0.1.3680043.8.498.1", modality="CT", reverse=False, shift_slice=None, direction6=(1, 0, 0, 0, 1, 0)):
    os.makedirs(outdir, exist_ok=True)
    n = stored.shape[0]
    writer = sitk.ImageFileWriter()
    writer.KeepOriginalImageUIDOn()
    order = list(range(n))[::-1] if reverse else list(range(n))
    for k, i in enumerate(order):
        sl = sitk.GetImageFromArray(stored[i].astype(np.int16))
        sl.SetSpacing((spacing[0], spacing[1]))
        z = origin[2] + i * spacing[2] + (0.5 if shift_slice == i else 0.0)
        tags = {"0008|0060": modality, "0020|000e": uid, "0008|0018": uid + "." + str(100 + i), "0020|0013": str(k + 1),
                "0020|0032": "\\".join(str(v) for v in (origin[0], origin[1], z)),
                "0020|0037": "\\".join(str(v) for v in direction6), "0028|1052": str(intercept), "0028|1053": str(slope),
                "0010|0020": "TEST", "0020|0011": "1", "0008|103e": "phantom"}
        for t, v in tags.items():
            sl.SetMetaData(t, v)
        writer.SetFileName(os.path.join(outdir, "slice_%03d.dcm" % k))
        writer.Execute(sl)


# ------------------------------------------------------------------ independent ground truth
def test_sphere_shape_matches_analytic(tmp_path):
    shape, r = (50, 50, 50), 14
    m = sphere(shape, (25, 25, 25), r)
    img = np.random.RandomState(0).randint(-100, 100, shape)
    save_nii(img, tmp_path / "i.nii.gz", spacing=(1, 1, 1)); save_nii(m, tmp_path / "m.nii.gz", dtype=np.uint8)
    run(["--image", str(tmp_path / "i.nii.gz"), "--mask", str(tmp_path / "m.nii.gz"), "--modality", "CT",
         "--feature-classes", "shape", "--outdir", str(tmp_path / "o")])
    o = str(tmp_path / "o")
    assert feat(o, "original_shape_VoxelVolume") == pytest.approx(float(m.sum()), rel=1e-9)
    assert feat(o, "original_shape_MeshVolume") == pytest.approx(4 / 3 * np.pi * r ** 3, rel=0.03)
    assert feat(o, "original_shape_Sphericity") > 0.93
    assert feat(o, "original_shape_Maximum3DDiameter") == pytest.approx(2 * r, abs=2.0)


def test_anisotropic_voxel_volume_exact(tmp_path):
    shape = (30, 40, 40)
    m = sphere(shape, (15, 20, 20), 9)
    save_nii(np.random.RandomState(1).randint(0, 200, shape), tmp_path / "i.nii.gz", spacing=(0.8, 0.8, 2.5))
    save_nii(m, tmp_path / "m.nii.gz", spacing=(0.8, 0.8, 2.5), dtype=np.uint8)
    run(["--image", str(tmp_path / "i.nii.gz"), "--mask", str(tmp_path / "m.nii.gz"), "--modality", "CT",
         "--feature-classes", "shape", "--outdir", str(tmp_path / "o")])
    assert feat(str(tmp_path / "o"), "original_shape_VoxelVolume") == pytest.approx(m.sum() * 0.8 * 0.8 * 2.5, rel=1e-9)
    q = json.load(open(tmp_path / "o" / "qc_summary.json"))["cases"][0]
    assert q["roi_volume_mm3"] == pytest.approx(m.sum() * 0.8 * 0.8 * 2.5, rel=1e-6)
    assert any("anisotropic" in w for w in q["warnings"])   # spacing ratio 2.5/0.8 = 3.125 > 3


def test_firstorder_matches_independent_numpy(tmp_path):
    shape = (30, 30, 30)
    m = sphere(shape, (15, 15, 15), 8)
    img = np.random.RandomState(2).randint(-200, 300, shape)
    save_nii(img, tmp_path / "i.nii.gz"); save_nii(m, tmp_path / "m.nii.gz", dtype=np.uint8)
    run(["--image", str(tmp_path / "i.nii.gz"), "--mask", str(tmp_path / "m.nii.gz"), "--modality", "CT",
         "--feature-classes", "firstorder", "--outdir", str(tmp_path / "o")])
    x = img[m == 1].astype(np.float64)
    mu = x.mean(); m2 = ((x - mu) ** 2).mean(); m3 = ((x - mu) ** 3).mean(); m4 = ((x - mu) ** 4).mean()
    o = str(tmp_path / "o")
    exp = {"Mean": mu, "Variance": m2, "Skewness": m3 / m2 ** 1.5, "Kurtosis": m4 / m2 ** 2,
           "Minimum": x.min(), "Maximum": x.max(), "Median": np.median(x), "Range": x.max() - x.min(),
           "10Percentile": np.percentile(x, 10), "90Percentile": np.percentile(x, 90),
           "InterquartileRange": np.percentile(x, 75) - np.percentile(x, 25),
           "Energy": (x ** 2).sum(), "RootMeanSquared": np.sqrt((x ** 2).mean())}
    for k, v in exp.items():
        assert feat(o, "original_firstorder_" + k) == pytest.approx(v, rel=1e-6), k


def test_translation_invariance(tmp_path):
    shape = (40, 40, 40)
    rs = np.random.RandomState(3)
    base = rs.randint(0, 100, shape)
    m = sphere(shape, (15, 15, 15), 7)
    shifted_img = np.roll(base, (3, 2, 1), axis=(0, 1, 2)); shifted_m = np.roll(m, (3, 2, 1), axis=(0, 1, 2))
    for tag, (a, b) in {"a": (base, m), "b": (shifted_img, shifted_m)}.items():
        save_nii(a, tmp_path / (tag + "_i.nii.gz")); save_nii(b, tmp_path / (tag + "_m.nii.gz"), dtype=np.uint8)
        run(["--image", str(tmp_path / (tag + "_i.nii.gz")), "--mask", str(tmp_path / (tag + "_m.nii.gz")), "--modality", "CT",
             "--outdir", str(tmp_path / tag)])
    A, B = load_wide(str(tmp_path / "a"))[0], load_wide(str(tmp_path / "b"))[0]
    bad = [k for k in A if k != "patient_id" and not np.isclose(float(A[k]), float(B[k]), rtol=1e-9, atol=1e-9)]
    assert not bad, bad[:5]


def test_deterministic_and_provenance(tmp_path):
    shape = (24, 24, 24); m = sphere(shape, (12, 12, 12), 6)
    save_nii(np.random.RandomState(4).randint(0, 50, shape), tmp_path / "i.nii.gz"); save_nii(m, tmp_path / "m.nii.gz", dtype=np.uint8)
    args = ["--image", str(tmp_path / "i.nii.gz"), "--mask", str(tmp_path / "m.nii.gz"), "--modality", "CT"]
    run(args + ["--outdir", str(tmp_path / "r1")]); run(args + ["--outdir", str(tmp_path / "r2")])
    a, b = load_wide(str(tmp_path / "r1"))[0], load_wide(str(tmp_path / "r2"))[0]
    assert a == b
    prov = json.load(open(tmp_path / "r1" / "provenance.json"))
    assert prov["cases"][0]["image_sha256"] == hashlib.sha256(open(tmp_path / "i.nii.gz", "rb").read()).hexdigest()
    assert prov["software"]["pyradiomics"] and prov["cases"][0]["settings"]["binWidth"] == 25


# ------------------------------------------------------------------ DICOM path
def _dicom_case(tmp_path, **kw):
    shape = (20, 32, 32)
    hu = np.random.RandomState(5).randint(-300, 400, shape)
    m = sphere(shape, (10, 16, 16), 7)
    stored = hu + 1024                                  # stored = HU - intercept (intercept -1024, slope 1)
    sp = (0.7, 0.7, 3.0)
    write_dicom_series(stored, sp, str(tmp_path / "dcm"), slope=1.0, intercept=-1024.0, **kw)
    save_nii(hu, tmp_path / "ref.nii.gz", spacing=sp, origin=(10.0, -20.0, 5.0))
    save_nii(m, tmp_path / "mask.nii.gz", spacing=sp, origin=(10.0, -20.0, 5.0), dtype=np.uint8)
    return hu, m


def test_dicom_equals_nifti_and_applies_rescale(tmp_path):
    _dicom_case(tmp_path)
    cls = ["--feature-classes", "shape,firstorder,glcm"]
    run(["--image", str(tmp_path / "dcm"), "--mask", str(tmp_path / "mask.nii.gz"), "--modality", "CT", "--outdir", str(tmp_path / "d")] + cls)
    run(["--image", str(tmp_path / "ref.nii.gz"), "--mask", str(tmp_path / "mask.nii.gz"), "--modality", "CT", "--outdir", str(tmp_path / "n")] + cls)
    D, N = load_wide(str(tmp_path / "d"))[0], load_wide(str(tmp_path / "n"))[0]
    bad = [k for k in N if k != "patient_id" and not np.isclose(float(D[k]), float(N[k]), rtol=1e-6, atol=1e-6)]
    assert not bad, bad[:8]
    q = json.load(open(tmp_path / "d" / "qc_summary.json"))["cases"][0]
    assert q["dicom"]["dicom_modality"] == "CT" and q["image_geometry"]["spacing"] == pytest.approx([0.7, 0.7, 3.0], abs=1e-6)


def test_dicom_slice_order_independent(tmp_path):
    _dicom_case(tmp_path)
    run(["--image", str(tmp_path / "dcm"), "--mask", str(tmp_path / "mask.nii.gz"), "--modality", "CT", "--feature-classes", "shape,firstorder", "--outdir", str(tmp_path / "a")])
    # same physical slices written in descending file order: the reader must sort by position
    shape = (20, 32, 32)
    hu = np.random.RandomState(5).randint(-300, 400, shape)
    write_dicom_series(hu + 1024, (0.7, 0.7, 3.0), str(tmp_path / "dcm_rev"), intercept=-1024.0, reverse=True)
    run(["--image", str(tmp_path / "dcm_rev"), "--mask", str(tmp_path / "mask.nii.gz"), "--modality", "CT", "--feature-classes", "shape,firstorder", "--outdir", str(tmp_path / "b")])
    A, B = load_wide(str(tmp_path / "a"))[0], load_wide(str(tmp_path / "b"))[0]
    assert all(np.isclose(float(A[k]), float(B[k]), rtol=1e-6, atol=1e-6) for k in A if k != "patient_id")


def test_nonuniform_slice_spacing_is_refused(tmp_path, capsys):
    shape = (12, 24, 24)
    write_dicom_series(np.random.RandomState(6).randint(0, 500, shape), (0.8, 0.8, 2.0), str(tmp_path / "dcm"), shift_slice=6)
    save_nii(sphere(shape, (6, 12, 12), 5), tmp_path / "m.nii.gz", spacing=(0.8, 0.8, 2.0), origin=(10, -20, 5), dtype=np.uint8)
    with pytest.raises(SystemExit) as e:
        run(["--image", str(tmp_path / "dcm"), "--mask", str(tmp_path / "m.nii.gz"), "--modality", "CT", "--outdir", str(tmp_path / "o")])
    assert e.value.code != 0 and "non-uniform slice spacing" in capsys.readouterr().err


def test_multiple_series_requires_selection(tmp_path, capsys):
    shape = (10, 24, 24)
    a = np.random.RandomState(7).randint(0, 500, shape)
    write_dicom_series(a, (0.8, 0.8, 2.0), str(tmp_path / "dcm" / "s1"), uid="1.2.3.4.1")
    write_dicom_series(a, (0.8, 0.8, 2.0), str(tmp_path / "dcm" / "s2"), uid="1.2.3.4.2")
    save_nii(sphere(shape, (5, 12, 12), 4), tmp_path / "m.nii.gz", spacing=(0.8, 0.8, 2.0), origin=(10, -20, 5), dtype=np.uint8)
    with pytest.raises(SystemExit):
        run(["--image", str(tmp_path / "dcm"), "--mask", str(tmp_path / "m.nii.gz"), "--modality", "CT", "--outdir", str(tmp_path / "o")])
    assert "--series-uid" in capsys.readouterr().err
    run(["--image", str(tmp_path / "dcm"), "--mask", str(tmp_path / "m.nii.gz"), "--modality", "CT", "--series-uid", "1.2.3.4.2",
         "--feature-classes", "firstorder", "--outdir", str(tmp_path / "ok")])
    assert len(load_wide(str(tmp_path / "ok"))) == 1


# ------------------------------------------------------------------ honest failures
def _basic(tmp_path, mask=None):
    shape = (20, 20, 20)
    save_nii(np.random.RandomState(8).randint(0, 100, shape), tmp_path / "i.nii.gz")
    save_nii(sphere(shape, (10, 10, 10), 5) if mask is None else mask, tmp_path / "m.nii.gz", dtype=np.uint8)
    return ["--image", str(tmp_path / "i.nii.gz"), "--mask", str(tmp_path / "m.nii.gz")]


def test_empty_mask_refused(tmp_path, capsys):
    a = _basic(tmp_path, mask=np.zeros((20, 20, 20)))
    with pytest.raises(SystemExit) as e:
        run(a + ["--modality", "CT", "--outdir", str(tmp_path / "o")])
    assert e.value.code != 0 and "no voxels with label" in capsys.readouterr().err


def test_modality_required_and_other_needs_binning(tmp_path, capsys):
    a = _basic(tmp_path)
    with pytest.raises(SystemExit):
        run(a + ["--outdir", str(tmp_path / "o")])
    assert "--modality is required" in capsys.readouterr().err
    with pytest.raises(SystemExit):
        run(a + ["--modality", "OTHER", "--outdir", str(tmp_path / "o")])
    assert "needs --bin-width or --bin-count" in capsys.readouterr().err


def test_geometry_mismatch_refused_then_corrected(tmp_path, capsys):
    shape = (20, 20, 20)
    save_nii(np.random.RandomState(9).randint(0, 100, shape), tmp_path / "i.nii.gz")
    save_nii(sphere(shape, (10, 10, 10), 5), tmp_path / "m.nii.gz", origin=(0.4, 0, 0), dtype=np.uint8)   # shifted grid
    a = ["--image", str(tmp_path / "i.nii.gz"), "--mask", str(tmp_path / "m.nii.gz"), "--modality", "CT", "--feature-classes", "firstorder"]
    with pytest.raises(SystemExit):
        run(a + ["--outdir", str(tmp_path / "o")])
    assert "not on the same grid" in capsys.readouterr().err
    run(a + ["--correct-mask", "--outdir", str(tmp_path / "c")])
    assert json.load(open(tmp_path / "c" / "qc_summary.json"))["cases"][0]["mask_resampled_to_image"] is True


def test_pet_warning_and_mr_preset_recorded(tmp_path):
    a = _basic(tmp_path)
    run(a + ["--modality", "PET", "--feature-classes", "firstorder", "--outdir", str(tmp_path / "p")])
    assert any("SUV" in w for w in json.load(open(tmp_path / "p" / "qc_summary.json"))["cases"][0]["warnings"])
    run(a + ["--modality", "MR", "--feature-classes", "firstorder", "--outdir", str(tmp_path / "r")])
    s = json.load(open(tmp_path / "r" / "provenance.json"))["cases"][0]["settings"]
    assert s["normalize"] is True and s["binCount"] == 32 and "binWidth" not in s


def test_samplesheet_and_merge(tmp_path):
    shape = (20, 20, 20)
    for i, pid in enumerate(["P1", "P2"]):
        save_nii(np.random.RandomState(10 + i).randint(0, 100, shape), tmp_path / (pid + "_i.nii.gz"))
        save_nii(sphere(shape, (10, 10, 10), 5 + i), tmp_path / (pid + "_m.nii.gz"), dtype=np.uint8)
    with open(tmp_path / "sheet.csv", "w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["patient_id", "image", "mask", "modality"])
        for pid in ["P1", "P2"]:
            w.writerow([pid, pid + "_i.nii.gz", pid + "_m.nii.gz", "CT"])
    run(["--samplesheet", str(tmp_path / "sheet.csv"), "--feature-classes", "firstorder,shape", "--outdir", str(tmp_path / "all")])
    rows = load_wide(str(tmp_path / "all"))
    assert [r["patient_id"] for r in rows] == ["P1", "P2"] and rows[0]["original_shape_VoxelVolume"] != rows[1]["original_shape_VoxelVolume"]
    # per-case runs merged = samplesheet run
    for pid in ["P1", "P2"]:
        run(["--image", str(tmp_path / (pid + "_i.nii.gz")), "--mask", str(tmp_path / (pid + "_m.nii.gz")), "--modality", "CT", "--patient-id", pid,
             "--feature-classes", "firstorder,shape", "--outdir", str(tmp_path / pid)])
    os.makedirs(tmp_path / "merged")
    mf.main(["--wide", str(tmp_path / "P1" / "features_wide.csv"), str(tmp_path / "P2" / "features_wide.csv"),
             "--qc", str(tmp_path / "P1" / "qc_summary.json"), str(tmp_path / "P2" / "qc_summary.json"),
             "--prov", str(tmp_path / "P1" / "provenance.json"), str(tmp_path / "P2" / "provenance.json"), "--outdir", str(tmp_path / "merged")])
    with open(tmp_path / "merged" / "features_wide_all.csv", newline="") as fh:
        merged = list(csv.DictReader(fh))
    assert merged == rows
