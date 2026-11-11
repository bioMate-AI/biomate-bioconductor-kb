#!/usr/bin/env python3
"""Verify radiomics_extract.py against external references.

A. PyRadiomics' own baseline: for each real case in the PyRadiomics repository (brain MR, breast MR, two lung CT)
   and each stored configuration (plain, normalisation, resampling, resegmentation) run radiomics_extract.py
   with exactly the settings stored in the baseline file, and compare every feature. PyRadiomics' own tests
   accept a relative difference under 3%; the same criterion is applied here and the actual maximum is reported.
B. IBSI digital phantom: first-order features recomputed independently with numpy and compared.
Writes verification_results.json. Exit code is non-zero if any criterion fails.
"""
import argparse, ast, csv, json, os, subprocess, sys, urllib.request, hashlib
import numpy as np
import SimpleITK as sitk

RAW = "https://raw.githubusercontent.com/AIM-Harvard/pyradiomics/master/data/"
IBSI = "https://raw.githubusercontent.com/theibsi/data_sets/master/ibsi_1_digital_phantom/nifti/"
CLASSES = ["firstorder", "shape", "glcm", "glrlm", "glszm", "gldm", "ngtdm"]
TOL = 0.03


def get(url, dst):
    if not os.path.exists(dst):
        urllib.request.urlretrieve(url, dst)
    return dst


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def read_baseline(path):
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    header = rows[0]
    table = {r[0]: dict(zip(header[1:], r[1:])) for r in rows[1:]}
    return header[1:], table


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--work", default="/tmp/refs"); ap.add_argument("--out", default="verification_results.json")
    a = ap.parse_args(); os.makedirs(a.work, exist_ok=True)
    results = {"criterion": "relative difference < %.0f%% per feature (the criterion PyRadiomics applies to its own baselines)" % (TOL * 100),
               "pyradiomics_baseline": {}, "ibsi_digital_phantom": {}, "data_hashes": {}}
    import radiomics
    results["pyradiomics_version"] = radiomics.__version__
    ok = True
    # ---------------- A. PyRadiomics baselines
    cache = {}
    for cls in CLASSES:
        bl = get(RAW + "baseline/baseline_%s.csv" % cls, os.path.join(a.work, "baseline_%s.csv" % cls))
        results["data_hashes"]["baseline_%s.csv" % cls] = sha(bl)
        cols, table = read_baseline(bl)
        n_cmp, worst, n_bad, per_col = 0, 0.0, 0, {}
        for col in cols:
            case = table["diagnostics_Configuration_TestCase"][col]
            settings = ast.literal_eval(table["diagnostics_Configuration_Settings"][col])
            for suffix in ("image", "label"):
                p = get(RAW + "%s_%s.nrrd" % (case, suffix), os.path.join(a.work, "%s_%s.nrrd" % (case, suffix)))
                results["data_hashes"]["%s_%s.nrrd" % (case, suffix)] = sha(p)
            key = (col, cls, json.dumps(settings, sort_keys=True, default=str))
            if key not in cache:
                out = os.path.join(a.work, "run_%s_%s_%d" % (cls, col, len(cache)))
                cmd = [sys.executable, "/opt/biomate/radiomics_extract.py", "--image", os.path.join(a.work, case + "_image.nrrd"),
                       "--mask", os.path.join(a.work, case + "_label.nrrd"), "--modality", "OTHER", "--bin-width", "25", "--patient-id", col,
                       "--feature-classes", cls, "--image-types", "Original",
                       "--settings-json", json.dumps({k: v for k, v in settings.items()}), "--outdir", out]
                r = subprocess.run(cmd, capture_output=True, text=True)
                if r.returncode != 0:
                    results["pyradiomics_baseline"].setdefault("errors", []).append({"column": col, "stderr": r.stderr[-400:]}); ok = False
                    cache[key] = None; continue
                with open(os.path.join(out, "features_wide.csv"), newline="") as fh:
                    cache[key] = next(csv.DictReader(fh))
            got = cache[key]
            if got is None:
                continue
            cmax, cbad, cn = 0.0, 0, 0
            for fname, bval in table.items():
                if not fname.startswith("original_" + cls + "_"):
                    continue
                b = table[fname][col]
                if b in ("", "nan"):
                    continue
                b = float(b); v = float(got[fname])
                d = (0.0 if v == b else 1.0) if b == 0.0 else abs(1.0 - v / b)
                cmax, cn = max(cmax, d), cn + 1
                if d >= TOL:
                    cbad += 1
            per_col[col] = {"features_compared": cn, "max_rel_diff": cmax, "n_over_tolerance": cbad}
            n_cmp += cn; worst = max(worst, cmax); n_bad += cbad
        results["pyradiomics_baseline"][cls] = {"features_compared": n_cmp, "max_rel_diff": worst, "n_over_tolerance": n_bad, "columns": per_col}
        ok = ok and n_bad == 0 and n_cmp > 0
    # ---------------- B. IBSI digital phantom, independent numpy first-order
    ip = get(IBSI + "image/phantom.nii.gz", os.path.join(a.work, "ibsi_phantom.nii.gz")); mp = get(IBSI + "mask/mask.nii.gz", os.path.join(a.work, "ibsi_mask.nii.gz"))
    results["data_hashes"]["ibsi_phantom.nii.gz"] = sha(ip); results["data_hashes"]["ibsi_mask.nii.gz"] = sha(mp)
    out = os.path.join(a.work, "run_ibsi")
    r = subprocess.run([sys.executable, "/opt/biomate/radiomics_extract.py", "--image", ip, "--mask", mp, "--modality", "OTHER", "--bin-width", "1",
                        "--feature-classes", "firstorder,shape", "--outdir", out], capture_output=True, text=True)
    if r.returncode != 0:
        results["ibsi_digital_phantom"]["error"] = r.stderr[-400:]; ok = False
    else:
        with open(os.path.join(out, "features_wide.csv"), newline="") as fh:
            got = next(csv.DictReader(fh))
        img = sitk.GetArrayFromImage(sitk.ReadImage(ip)).astype(float); msk = sitk.GetArrayFromImage(sitk.ReadImage(mp)) != 0
        x = img[msk]; mu = x.mean(); m2 = ((x - mu) ** 2).mean()
        exp = {"Mean": mu, "Variance": m2, "Skewness": ((x - mu) ** 3).mean() / m2 ** 1.5 if m2 else 0.0, "Kurtosis": ((x - mu) ** 4).mean() / m2 ** 2 if m2 else 0.0,
               "Minimum": x.min(), "Maximum": x.max(), "Median": np.median(x), "Energy": (x ** 2).sum(), "RootMeanSquared": np.sqrt((x ** 2).mean()),
               "10Percentile": np.percentile(x, 10), "90Percentile": np.percentile(x, 90)}
        cmp = {}
        for k, v in exp.items():
            g = float(got["original_firstorder_" + k]); cmp[k] = {"expected_numpy": float(v), "tool": g, "abs_diff": abs(g - float(v))}
            ok = ok and abs(g - float(v)) <= 1e-6 * max(1.0, abs(float(v)))
        cmp["voxel_count_expected"] = int(msk.sum()); cmp["VoxelVolume_tool"] = float(got["original_shape_VoxelVolume"])
        ok = ok and abs(cmp["VoxelVolume_tool"] - msk.sum() * float(np.prod(sitk.ReadImage(ip).GetSpacing()))) < 1e-6
        results["ibsi_digital_phantom"] = {"n_roi_voxels": int(msk.sum()), "firstorder": cmp,
                                           "note": "PyRadiomics Kurtosis is the non-excess form (IBSI excess kurtosis = this - 3); compared against the numpy non-excess definition"}
    results["passed"] = bool(ok)
    json.dump(results, open(a.out, "w"), indent=1, default=str)
    print(json.dumps({"passed": results["passed"], "per_class": {c: {k: results["pyradiomics_baseline"].get(c, {}).get(k) for k in ("features_compared", "max_rel_diff", "n_over_tolerance")} for c in CLASSES}}, indent=1))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
