#!/usr/bin/env nextflow
/*
 * imaging/radiomics_feature_extraction
 *
 * Quantitative RADIOMICS feature extraction from a medical image + segmentation
 * mask (NPC — nasopharyngeal carcinoma — MRI / CT ROIs), using the open-source,
 * IBSI-aligned PyRadiomics engine (van Griethuysen et al., Cancer Research 2017;
 * BSD-3) on top of SimpleITK for image I/O. Deterministic, CPU only, no GPU,
 * no model weights, no license key.
 *
 * Per image+mask it extracts the full IBSI feature battery over the labelled ROI:
 *   - first-order (intensity histogram statistics)
 *   - shape (3D morphology: volume, surface area, sphericity, elongation, ...)
 *   - GLCM   (gray-level co-occurrence matrix texture)
 *   - GLRLM  (gray-level run-length matrix texture)
 *   - GLSZM  (gray-level size-zone matrix texture)
 *   - NGTDM  (neighbouring gray-tone difference matrix texture)
 *   - GLDM   (gray-level dependence matrix texture)
 * Values are PyRadiomics' own computed numbers — NEVER fabricated. If the engine
 * is absent, or the mask is empty / geometry-mismatched so no feature is produced,
 * the task LOUD-FAILS (exit 1) instead of inventing a track.
 *
 * Runs with NO user input: when params.image / params.mask are not supplied (or
 * do not exist in the container), the extract process SYNTHESISES a small
 * reproducible 3D SimpleITK image + binary cube mask so the demo path always
 * yields a full feature set. Production supplies the real NPC NRRD/NIfTI image
 * and its ROI mask at launch.
 *
 * HONEST SCOPE / what this is NOT:
 *   - Feature extraction only. It does NOT train or apply a diagnostic/prognostic
 *     radiomics model, do feature selection, harmonise across scanners (ComBat),
 *     or perform image preprocessing beyond PyRadiomics defaults. Those are
 *     downstream steps.
 *   - The demo synthetic image is illustrative geometry, NOT a patient scan; the
 *     qc flags used_demo_data=true so synthetic runs are never mistaken for real.
 *
 * Inputs (params):
 *   params.image      path to the image volume (NRRD / NIfTI / etc.); '' -> demo.
 *   params.mask       path to the ROI segmentation mask; '' -> demo.
 *   params.bin_width  intensity discretisation bin width (default 25).
 *   params.label      mask label value defining the ROI (default 1).
 *   params.outdir     output directory (default 'results').
 *
 * Container: a dedicated radiomics image (biomate/radiomics). Dockerfile deps:
 *   python3, pyradiomics, SimpleITK, pandas (numpy comes transitively). Build +
 *   push to ECR before first AWS run, mirroring the other biomate/* images.
 */

nextflow.enable.dsl = 2

// Demo defaults (overridden by BioMate's executor at launch). Empty image/mask
// trigger the in-process synthetic-volume fallback so this runs with no input.
params.image     = ''
params.mask      = ''
params.bin_width = '25'
params.label     = '1'
params.outdir    = 'results'

process EXTRACT_FEATURES {
    tag "${sample_id}"
    label 'process_low'
    publishDir { "${params.outdir}/radiomics/${sample_id.replaceAll('[^A-Za-z0-9]', '_')}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/radiomics:x86' : 'biomate/radiomics:latest'

    input:
    tuple val(sample_id), val(image), val(mask), val(label)

    output:
    tuple val(sample_id), path("${sample_id}_features.csv"), emit: features
    tuple val(sample_id), path("${sample_id}_qc.json"),      emit: qc
    path "versions.yml",                                     emit: versions

    script:
    """
    export SAMPLE_ID='${sample_id}'
    export IMAGE='${image}'
    export MASK='${mask}'
    export BIN_WIDTH='${params.bin_width}'
    export LABEL='${label}'

    python3 << 'PYEOF'
import os, json, sys, csv

sample     = os.environ.get("SAMPLE_ID", "sample").strip() or "sample"
image_path = os.environ.get("IMAGE", "").strip()
mask_path  = os.environ.get("MASK", "").strip()
bin_width  = float(os.environ.get("BIN_WIDTH", "25") or 25)
label      = int(float(os.environ.get("LABEL", "1") or 1))

try:
    import SimpleITK as sitk
except Exception as e:
    sys.exit("FATAL: SimpleITK not available in this image (%s). The biomate/radiomics "
             "image must be built with: pip install SimpleITK pyradiomics pandas." % e)

try:
    from radiomics import featureextractor
    import radiomics as _rad
except Exception as e:
    sys.exit("FATAL: PyRadiomics not available in this image (%s). Build biomate/radiomics "
             "with: pip install pyradiomics." % e)

used_demo = False

def have(p):
    return bool(p) and os.path.exists(p)

if have(image_path) and have(mask_path):
    image = sitk.ReadImage(image_path)
    mask  = sitk.ReadImage(mask_path)
else:
    # Synthesize a small reproducible 3D image + binary cube mask so the workflow
    # runs with no user input. PyRadiomics ships brain1 test data, but it is not
    # guaranteed inside every image build, so geometry is built deterministically.
    used_demo = True
    import numpy as np
    rs = np.random.RandomState(42)
    dim = 24
    base = rs.rand(dim, dim, dim).astype("float32") * 100.0
    core = np.zeros((dim, dim, dim), dtype="float32")
    core[6:18, 6:18, 6:18] = 60.0          # brighter structured ROI core
    arr = base + core
    image = sitk.GetImageFromArray(arr)
    image.SetSpacing((1.0, 1.0, 1.0))
    mask_arr = np.zeros((dim, dim, dim), dtype="uint8")
    mask_arr[6:18, 6:18, 6:18] = 1
    mask = sitk.GetImageFromArray(mask_arr)
    mask.CopyInformation(image)

try:
    extractor = featureextractor.RadiomicsFeatureExtractor(binWidth=bin_width)
    extractor.enableAllFeatures()
    result = extractor.execute(image, mask, label=label)
except Exception as e:
    sys.exit("FATAL: PyRadiomics execute failed for sample %s: %s" % (sample, e))

CLASSES = ["firstorder", "shape", "glcm", "glrlm", "glszm", "ngtdm", "gldm"]

def feat_class(key):
    # keys look like original_firstorder_Mean / original_glcm_Idmn / original_shape_Volume
    for part in str(key).split("_"):
        if part in CLASSES:
            return part
    return "other"

rows = []
for k in result.keys():
    if str(k).startswith("diagnostics"):
        continue
    cls = feat_class(k)
    if cls == "other":
        continue
    v = result[k]
    try:
        val = float(v)
    except Exception:
        try:
            val = json.dumps([float(x) for x in list(v)])
        except Exception:
            val = str(v)
    rows.append({"feature": str(k), "class": cls, "value": val})

if not rows:
    sys.exit("FATAL: PyRadiomics produced no features for sample %s "
             "(empty mask or image/mask geometry mismatch)." % sample)

rows.sort(key=lambda r: (r["class"], r["feature"]))

with open("%s_features.csv" % sample, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["feature", "class", "value"])
    for r in rows:
        w.writerow([r["feature"], r["class"], r["value"]])

counts = {}
for c in CLASSES:
    counts[c] = sum(1 for r in rows if r["class"] == c)

mask_np = sitk.GetArrayFromImage(mask)
voxels = int((mask_np == label).sum())
size = list(image.GetSize())

qc = {
    "sample_id": sample,
    "status": "ok",
    "n_features": len(rows),
    "feature_counts_per_class": counts,
    "n_feature_classes": sum(1 for c in CLASSES if counts[c] > 0),
    "mask_voxel_count": voxels,
    "image_size": size,
    "bin_width": bin_width,
    "label": label,
    "used_demo_data": used_demo,
    "tool": "PyRadiomics",
    "tool_version": getattr(_rad, "__version__", "unknown"),
}
with open("%s_qc.json" % sample, "w") as fh:
    json.dump(qc, fh, indent=2)
print(json.dumps({k: qc[k] for k in ("sample_id", "n_features", "n_feature_classes",
                                      "mask_voxel_count", "used_demo_data", "status")}, indent=2))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pyradiomics: \$(python3 -c "import radiomics; print(getattr(radiomics,'__version__','unknown'))" 2>/dev/null || echo unknown)
        simpleitk: \$(python3 -c "import SimpleITK; print(SimpleITK.Version_VersionString())" 2>/dev/null || echo unknown)
        python: \$(python3 --version | cut -d' ' -f2)
    END_VERSIONS
    """
}

process SUMMARISE {
    tag "radiomics"
    label 'process_low'
    publishDir { "${params.outdir}/radiomics" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/radiomics:x86' : 'biomate/radiomics:latest'

    input:
    path "features_*.csv"
    path "qc_*.json"

    output:
    path "radiomics_summary.json", emit: summary
    path "qc_metrics.json",        emit: qc

    script:
    """
    python3 << 'PYEOF'
import os, json, csv, glob

feat_files = sorted(glob.glob("features_*.csv"))
qc_files   = sorted(glob.glob("qc_*.json"))

CLASSES = ["firstorder", "shape", "glcm", "glrlm", "glszm", "ngtdm", "gldm"]

total_counts = dict((c, 0) for c in CLASSES)
n_features_total = 0
for f in feat_files:
    with open(f, newline="") as fh:
        for r in csv.DictReader(fh):
            cls = r.get("class")
            if cls in total_counts:
                total_counts[cls] += 1
            n_features_total += 1

if n_features_total == 0:
    raise SystemExit("FATAL: SUMMARISE produced no radiomics features from %d feature file(s); "
                     "nothing to summarise." % len(feat_files))

qcs = []
for f in qc_files:
    try:
        with open(f) as fh:
            qcs.append(json.load(fh))
    except Exception:
        pass

n_classes_covered = sum(1 for c in CLASSES if total_counts[c] > 0)

summary = {
    "tool": "PyRadiomics + SimpleITK",
    "n_samples": len(feat_files),
    "n_features_total": n_features_total,
    "feature_counts_per_class": total_counts,
    "n_feature_classes_covered": n_classes_covered,
    "feature_classes": CLASSES,
    "status": "ok",
    "note": "Radiomics feature extraction (first-order, shape, GLCM, GLRLM, GLSZM, NGTDM, GLDM) "
            "from a medical image + segmentation mask via PyRadiomics. Counts are per IBSI "
            "feature class. Demo defaults synthesize a 3D image + cube mask when no image/mask "
            "is supplied; production supplies the real NPC MRI/CT volume and ROI.",
}
with open("radiomics_summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)

qc_metrics = {
    "status": "ok",
    "n_samples": len(feat_files),
    "n_features_total": n_features_total,
    "n_feature_classes_covered": n_classes_covered,
    "expected_feature_classes": len(CLASSES),
    "all_classes_present": all(total_counts[c] > 0 for c in CLASSES),
    "per_sample_qc": qcs,
}
with open("qc_metrics.json", "w") as fh:
    json.dump(qc_metrics, fh, indent=2)

print(json.dumps({k: summary[k] for k in ("n_samples", "n_features_total",
                                          "n_feature_classes_covered", "status")}, indent=2))
PYEOF
    """
}

workflow RADIOMICS_FEATURE_EXTRACTION {
    take:
    ch_samples   // channel: tuple(sample_id, image, mask, label) — ONE per image

    main:
    EXTRACT_FEATURES(ch_samples)
    SUMMARISE(
        EXTRACT_FEATURES.out.features.map { sid, csv -> csv }.collect(),
        EXTRACT_FEATURES.out.qc.map { sid, j -> j }.collect()
    )

    emit:
    features   = EXTRACT_FEATURES.out.features
    qc         = EXTRACT_FEATURES.out.qc
    summary    = SUMMARISE.out.summary
    qc_metrics = SUMMARISE.out.qc
    versions   = EXTRACT_FEATURES.out.versions
}

// Entry workflow for standalone execution.
workflow {
    ch_samples = Channel.of(
        tuple('demo_sample', params.image as String, params.mask as String, params.label as String)
    )

    RADIOMICS_FEATURE_EXTRACTION(ch_samples)

    RADIOMICS_FEATURE_EXTRACTION.out.summary.view { f -> "radiomics feature extraction done" }
}
