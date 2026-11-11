#!/usr/bin/env python3
"""Radiomics feature extraction from supplied segmentations (CT / MR / PET images).

RESEARCH USE ONLY. This tool computes standard radiomics features (PyRadiomics, whose first-order,
shape and texture definitions follow the Image Biomarker Standardisation Initiative) for a region of
interest that is SUPPLIED as a segmentation mask. It does not segment, diagnose or recommend treatment.

Inputs
  image : NIfTI / NRRD / MHA file, or a DICOM series (directory or .zip)
  mask  : NIfTI / NRRD / MHA label image on the same grid as the image (DICOM-SEG / RTSTRUCT are not read)
  PET   : values are used as given (assumed already in SUV or another fixed unit); no DICOM SUV conversion.

Honest-failure contract: every ambiguity or inconsistency that could silently change a number stops the
run with a non-zero exit and an actionable message (empty mask, geometry mismatch, several DICOM series,
non-uniform slice spacing, missing dependency). Nothing is estimated, defaulted silently, or fabricated.
Every setting that was used is written to provenance.json.
"""
import argparse
import csv
import datetime
import hashlib
import json
import os
import sys
import tempfile
import zipfile

NL = chr(10)


def fail(msg, code=1):
    sys.stderr.write("ERROR: " + msg + NL)
    sys.exit(code)


try:
    import numpy as np
except Exception as e:  # pragma: no cover
    fail("numpy is not importable (%r)." % e)
try:
    import SimpleITK as sitk
except Exception as e:  # pragma: no cover
    fail("SimpleITK is not importable (%r); the image reader refuses to run without it." % e)
try:
    import radiomics
    from radiomics import featureextractor
except Exception as e:  # pragma: no cover
    fail("pyradiomics is not importable (%r); feature extraction refuses to run without it." % e)

MODALITIES = ("CT", "MR", "PET", "OTHER")
ALL_CLASSES = ["firstorder", "shape", "glcm", "glrlm", "glszm", "gldm", "ngtdm"]
IMAGE_TYPES = ["Original", "LoG", "Wavelet"]

# Defaults by modality. They follow common radiomics practice and are NOT a clinical recommendation.
# Every value is overridable and every value used is written to provenance.json.
PRESETS = {
    "CT": {"binWidth": 25},                                    # HU
    "MR": {"normalize": True, "normalizeScale": 100, "binCount": 32},   # arbitrary units: normalise, fixed bin count
    "PET": {"binWidth": 0.25},                                 # SUV-scaled input assumed
    "OTHER": {},                                               # caller must give --bin-width or --bin-count
}


def sha256_path(path):
    h = hashlib.sha256()
    if os.path.isdir(path):
        entries = []
        for root, _d, files in os.walk(path):
            for f in sorted(files):
                p = os.path.join(root, f)
                entries.append((os.path.relpath(p, path), p))
        for rel, p in sorted(entries):
            h.update(rel.encode())
            with open(p, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    h.update(chunk)
    else:
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def _dicom_dirs(root):
    found = []
    for r, _d, files in os.walk(root):
        if any(f.lower().endswith(".dcm") or "." not in f for f in files):
            found.append(r)
    return found


def read_dicom_series(path, series_uid=None, workdir=None):
    """Read exactly one DICOM series. Returns (image, info). Fails on anything ambiguous."""
    src = path
    if path.lower().endswith(".zip"):
        workdir = workdir or tempfile.mkdtemp(prefix="dicom_")
        with zipfile.ZipFile(path) as z:
            z.extractall(workdir)
        src = workdir
    series = {}
    for d in _dicom_dirs(src):
        for sid in sitk.ImageSeriesReader.GetGDCMSeriesIDs(d):
            series.setdefault(sid, []).extend(sitk.ImageSeriesReader.GetGDCMSeriesFileNames(d, sid))
    if not series:
        fail("no DICOM series found in %s" % path)
    if series_uid:
        if series_uid not in series:
            fail("series %s not found; available: %s" % (series_uid, ", ".join(sorted(series))))
        chosen = series_uid
    elif len(series) == 1:
        chosen = next(iter(series))
    else:
        listing = "; ".join("%s (%d files)" % (k, len(v)) for k, v in sorted(series.items()))
        fail("%d DICOM series found and none was selected. Pass --series-uid. Available: %s" % (len(series), listing))
    names = series[chosen]
    reader = sitk.ImageSeriesReader()
    reader.SetFileNames(names)
    reader.MetaDataDictionaryArrayUpdateOn()
    reader.LoadPrivateTagsOff()
    image = reader.Execute()
    # Guard: non-uniform slice spacing silently distorts z-geometry and every volume-based feature.
    if len(names) > 2:
        pos, normal = [], None
        for i in range(len(names)):
            try:
                ipp = [float(v) for v in reader.GetMetaData(i, "0020|0032").split("\\")]
                iop = [float(v) for v in reader.GetMetaData(i, "0020|0037").split("\\")]
            except RuntimeError:
                fail("slice %d lacks ImagePositionPatient/ImageOrientationPatient; geometry cannot be trusted" % i)
            if normal is None:
                r, c = np.array(iop[:3]), np.array(iop[3:])
                normal = np.cross(r, c)
            pos.append(float(np.dot(np.array(ipp), normal)))
        gaps = np.diff(np.array(pos))
        if gaps.size and (np.abs(gaps - gaps.mean()).max() > 0.01 * abs(gaps.mean())):
            fail("non-uniform slice spacing (gaps range %.4f to %.4f mm). Resample the series to a uniform "
                 "grid before extraction; refusing to compute volume-based features on a distorted grid."
                 % (gaps.min(), gaps.max()))
    info = {"series_uid": chosen, "n_slices": len(names)}
    try:
        info["dicom_modality"] = reader.GetMetaData(0, "0008|0060").strip()
    except RuntimeError:
        info["dicom_modality"] = None
    return image, info


def read_image(path, series_uid=None):
    if not os.path.exists(path):
        fail("image path does not exist: %s" % path)
    if os.path.isdir(path) or path.lower().endswith(".zip"):
        return read_dicom_series(path, series_uid)
    try:
        return sitk.ReadImage(path), {"series_uid": None, "n_slices": None, "dicom_modality": None}
    except Exception as e:
        fail("cannot read image %s (%s)" % (path, e))


def read_mask(path):
    if not os.path.exists(path):
        fail("mask path does not exist: %s" % path)
    if os.path.isdir(path) or path.lower().endswith(".zip"):
        fail("DICOM masks (DICOM-SEG / RTSTRUCT) are not read; supply the mask as NIfTI, NRRD or MHA on the image grid")
    try:
        return sitk.ReadImage(path)
    except Exception as e:
        fail("cannot read mask %s (%s)" % (path, e))


def geometry(img):
    return {"size": list(img.GetSize()), "spacing": [round(float(s), 6) for s in img.GetSpacing()],
            "origin": [round(float(o), 6) for o in img.GetOrigin()],
            "direction": [round(float(d), 6) for d in img.GetDirection()],
            "pixel_type": img.GetPixelIDTypeAsString()}


def build_settings(modality, args):
    s = dict(PRESETS[modality])
    if args.bin_width is not None:
        s["binWidth"] = args.bin_width
        s.pop("binCount", None)
    if args.bin_count is not None:
        s["binCount"] = args.bin_count
        s.pop("binWidth", None)
    if args.resample_spacing:
        s["resampledPixelSpacing"] = [float(v) for v in args.resample_spacing.split(",")]
        s["interpolator"] = "sitkBSpline"
    if args.normalize is not None:
        s["normalize"] = bool(args.normalize)
        if s["normalize"]:
            s.setdefault("normalizeScale", 100)
    if args.correct_mask:
        s["correctMask"] = True
    if args.settings_json:
        s.update(json.loads(args.settings_json))
    s["label"] = int(args.label)
    if modality == "OTHER" and not ("binWidth" in s or "binCount" in s):
        fail("modality OTHER needs --bin-width or --bin-count (no intensity discretisation default is assumed)")
    return s


def make_extractor(settings, classes, image_types, log_sigma):
    ex = featureextractor.RadiomicsFeatureExtractor(settings)
    ex.disableAllFeatures()
    for c in classes:
        ex.enableFeatureClassByName(c)
    ex.disableAllImageTypes()
    for t in image_types:
        if t == "LoG":
            ex.enableImageTypeByName("LoG", customArgs={"sigma": [float(v) for v in log_sigma.split(",")]})
        else:
            ex.enableImageTypeByName(t)
    return ex


def run_case(case, args, outdir):
    pid = case["patient_id"]
    modality = case["modality"]
    image, dinfo = read_image(case["image"], case.get("series_uid"))
    mask = read_mask(case["mask"])
    warns = []
    if dinfo.get("dicom_modality") and modality in ("CT", "MR", "PET") and dinfo["dicom_modality"] != {"CT": "CT", "MR": "MR", "PET": "PT"}[modality]:
        warns.append("DICOM Modality tag %s does not match requested modality %s" % (dinfo["dicom_modality"], modality))
    gi, gm = geometry(image), geometry(mask)
    geom_ok = (gi["size"] == gm["size"] and np.allclose(gi["spacing"], gm["spacing"], atol=1e-3)
               and np.allclose(gi["origin"], gm["origin"], atol=1e-3) and np.allclose(gi["direction"], gm["direction"], atol=1e-3))
    if not geom_ok and not args.correct_mask:
        fail("[%s] image and mask are not on the same grid (image %s, mask %s). Re-export the mask on the image grid, "
             "or pass --correct-mask to resample the mask to the image (nearest neighbour; recorded)." % (pid, gi, gm))
    # For quality control the mask is brought onto the image grid when it is not already there.
    mask_q = mask if geom_ok else sitk.Resample(mask, image, sitk.Transform(), sitk.sitkNearestNeighbor, 0, mask.GetPixelID())
    arr_m = sitk.GetArrayFromImage(mask_q)
    labels, counts = np.unique(arr_m[arr_m != 0], return_counts=True)
    label = int(case.get("label", args.label))
    if label not in [int(l) for l in labels]:
        fail("[%s] mask has no voxels with label %d (labels present: %s). An empty region cannot be summarised."
             % (pid, label, [int(l) for l in labels] or "none"))
    n_roi = int(counts[[int(l) for l in labels].index(label)])
    settings = build_settings(modality, args)
    settings["label"] = label
    settings.setdefault("geometryTolerance", 1e-3)   # same tolerance as the check above; recorded in provenance
    classes = [c.strip() for c in args.feature_classes.split(",") if c.strip()]
    for c in classes:
        if c not in ALL_CLASSES:
            fail("unknown feature class %s; choose from %s" % (c, ALL_CLASSES))
    itypes = [t.strip() for t in args.image_types.split(",") if t.strip()]
    for t in itypes:
        if t not in IMAGE_TYPES:
            fail("unsupported image type %s; choose from %s" % (t, IMAGE_TYPES))
    ex = make_extractor(settings, classes, itypes, args.log_sigma)
    try:
        res = ex.execute(image, mask, label=label)
    except Exception as e:
        fail("[%s] feature extraction failed: %s" % (pid, e))
    feats, diag = {}, {}
    for k, v in res.items():
        if k.startswith("diagnostics_"):
            diag[k] = v if isinstance(v, (str, int, float, bool, type(None))) else str(v)
        else:
            try:
                feats[k] = float(v)
            except (TypeError, ValueError):
                feats[k] = float("nan")
    arr_i = sitk.GetArrayFromImage(image)
    roi_vals = arr_i[arr_m == label]
    sp = gi["spacing"]
    voxel_vol = float(np.prod(sp))
    if n_roi < 64:
        warns.append("small region (%d voxels); texture and shape features are unstable below about 64 voxels" % n_roi)
    if max(sp) / min(sp) > 3.0:
        warns.append("strongly anisotropic voxels (spacing %s); 3D features depend on resampling choices" % sp)
    if modality == "PET":
        warns.append("PET values used as given; assumed already in SUV or another fixed unit (no DICOM SUV conversion)")
    qc = {"patient_id": pid, "modality": modality, "image_geometry": gi, "mask_geometry": gm,
          "mask_on_image_grid": bool(geom_ok), "mask_resampled_to_image": bool((not geom_ok) and args.correct_mask),
          "label": label, "roi_voxels": n_roi, "roi_volume_mm3": round(n_roi * voxel_vol, 3),
          "roi_intensity": {"min": float(roi_vals.min()), "max": float(roi_vals.max()), "mean": float(roi_vals.mean())},
          "dicom": dinfo, "warnings": warns}
    prov = {"patient_id": pid, "image_sha256": sha256_path(case["image"]), "mask_sha256": sha256_path(case["mask"]),
            "settings": {k: (v if isinstance(v, (str, int, float, bool, list, type(None))) else str(v)) for k, v in settings.items()},
            "feature_classes": classes, "image_types": itypes, "log_sigma": args.log_sigma if "LoG" in itypes else None}
    return feats, diag, qc, prov


def read_samplesheet(path, args):
    cases = []
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            for need in ("patient_id", "image", "mask"):
                if not row.get(need):
                    fail("samplesheet row missing %s: %s" % (need, row))
            base = os.path.dirname(os.path.abspath(path))
            img = row["image"] if os.path.isabs(row["image"]) else os.path.join(base, row["image"])
            msk = row["mask"] if os.path.isabs(row["mask"]) else os.path.join(base, row["mask"])
            mod = (row.get("modality") or args.modality or "").upper()
            if mod not in MODALITIES:
                fail("patient %s: modality must be one of %s" % (row["patient_id"], MODALITIES))
            cases.append({"patient_id": row["patient_id"], "image": img, "mask": msk, "modality": mod,
                          "label": int(row["label"]) if row.get("label") else args.label, "series_uid": row.get("series_uid") or args.series_uid})
    if not cases:
        fail("samplesheet %s has no rows" % path)
    ids = [c["patient_id"] for c in cases]
    if len(set(ids)) != len(ids):
        fail("duplicate patient_id in samplesheet")
    return cases


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--image"); ap.add_argument("--mask"); ap.add_argument("--patient-id", default="case01")
    ap.add_argument("--samplesheet", help="CSV with columns patient_id,image,mask[,modality,label,series_uid]")
    ap.add_argument("--modality", choices=MODALITIES, help="CT | MR | PET | OTHER (required; no silent default)")
    ap.add_argument("--label", type=int, default=1)
    ap.add_argument("--series-uid", default=None)
    ap.add_argument("--bin-width", type=float, default=None); ap.add_argument("--bin-count", type=int, default=None)
    ap.add_argument("--resample-spacing", default=None, help="x,y,z in mm (B-spline); none by default")
    ap.add_argument("--normalize", type=int, choices=(0, 1), default=None)
    ap.add_argument("--correct-mask", action="store_true")
    ap.add_argument("--feature-classes", default=",".join(ALL_CLASSES))
    ap.add_argument("--image-types", default="Original")
    ap.add_argument("--log-sigma", default="1,2,3")
    ap.add_argument("--settings-json", default=None, help="advanced: JSON of PyRadiomics settings; overrides everything else; recorded")
    ap.add_argument("--outdir", default=".")
    args = ap.parse_args(argv)
    os.makedirs(args.outdir, exist_ok=True)
    if args.samplesheet:
        cases = read_samplesheet(args.samplesheet, args)
    else:
        if not (args.image and args.mask):
            fail("give --image and --mask, or --samplesheet")
        if not args.modality:
            fail("--modality is required (CT, MR, PET or OTHER); a silent default could mis-scale intensities")
        cases = [{"patient_id": args.patient_id, "image": args.image, "mask": args.mask, "modality": args.modality,
                  "label": args.label, "series_uid": args.series_uid}]
    long_rows, wide, qcs, provs, diags = [], [], [], [], {}
    for case in cases:
        feats, diag, qc, prov = run_case(case, args, args.outdir)
        for k, v in feats.items():
            itype, fclass, name = (k.split("_", 2) + ["", ""])[:3]
            long_rows.append([case["patient_id"], itype, fclass, name, repr(v)])
        wide.append(dict(patient_id=case["patient_id"], **feats))
        qcs.append(qc); provs.append(prov); diags[case["patient_id"]] = diag
    with open(os.path.join(args.outdir, "features_long.csv"), "w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["patient_id", "image_type", "feature_class", "feature", "value"]); w.writerows(long_rows)
    cols = ["patient_id"] + sorted({k for r in wide for k in r if k != "patient_id"})
    with open(os.path.join(args.outdir, "features_wide.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols); w.writeheader()
        for r in wide:
            w.writerow({c: (repr(r[c]) if c != "patient_id" else r[c]) for c in cols if c in r})
    meta = {"tool": "radiomics_extract.py", "research_use_only": True, "generated_utc": datetime.datetime.utcnow().isoformat() + "Z",
            "pyradiomics": radiomics.__version__, "SimpleITK": sitk.Version.VersionString(), "numpy": np.__version__}
    with open(os.path.join(args.outdir, "qc_summary.json"), "w") as fh:
        json.dump({"cases": qcs, "n_cases": len(qcs)}, fh, indent=1)
    with open(os.path.join(args.outdir, "provenance.json"), "w") as fh:
        json.dump({"software": meta, "cases": provs, "diagnostics": diags}, fh, indent=1, default=str)
    with open(os.path.join(args.outdir, "versions.yml"), "w") as fh:
        fh.write("radiology_radiomics_extraction:" + NL + '  pyradiomics: "%s"' % radiomics.__version__ + NL
                 + '  simpleitk: "%s"' % sitk.Version.VersionString() + NL + '  numpy: "%s"' % np.__version__ + NL)
    rep = ["RESEARCH USE ONLY. Not a diagnostic device. Radiologist review is required before any clinical use.", "",
           "Radiomics features were computed with PyRadiomics %s for %d case(s) from supplied segmentations." % (radiomics.__version__, len(qcs)),
           "The region of interest is the supplied mask; no segmentation was performed.",
           "Every setting used, and SHA-256 hashes of every input, are in provenance.json.", ""]
    for q in qcs:
        for wmsg in q["warnings"]:
            rep.append("WARNING [%s]: %s" % (q["patient_id"], wmsg))
    with open(os.path.join(args.outdir, "RESEARCH_USE_ONLY_report.txt"), "w") as fh:
        fh.write(NL.join(rep) + NL)
    print("radiomics_extract: %d case(s), %d feature values" % (len(qcs), len(long_rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
