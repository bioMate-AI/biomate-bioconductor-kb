#!/usr/bin/env nextflow
/*
 * imaging/ihc_marker_quantification
 *
 * RESEARCH-USE-ONLY general multiplex-IHC (mIHC) / immunofluorescence (IF) marker
 * quantification + cell phenotyping for digital pathology. On a tissue image the
 * workflow:
 *   1. segments cells (nuclei + a per-cell membrane/cytoplasm territory),
 *   2. measures per-cell mean intensity and positivity for an ARBITRARY,
 *      user-configurable marker panel (params.markers),
 *   3. PHENOTYPES each cell by its marker-positivity combination
 *      (e.g. CD8+, CD68+, PDL1+CD8+, negative), and
 *   4. reports per-marker positive-cell counts + densities (cells / mm^2), a cell
 *      phenotype-composition table, and (optionally) clinical PD-L1 TPS/CPS.
 *
 * SCORING is a configurable preset (params.scoring_mode), NOT the workflow
 * identity. PD-L1 TPS/CPS is ONE use case:
 *   - 'density'      (default): per-marker positive-cell counts + densities.
 *   - 'phenotype'             : cell-type composition by marker-positivity combo.
 *   - 'pdl1_tps_cps'          : additionally classify tumor vs immune cells and
 *                               compute PD-L1 TPS (Tumor Proportion Score) and CPS
 *                               (Combined Positive Score) — requires the panel to
 *                               include a PD-L1-like tumor-membrane marker.
 * Per-marker stats and the phenotype table are ALWAYS produced; the mode only
 * selects the headline score and whether TPS/CPS are computed.
 *
 * ALL outputs are COMPUTATIONAL ESTIMATES from an automated pipeline — NOT a
 * pathologist read and NOT a diagnostic device. A qualified pathologist must
 * review any marker call; no clinical decision may rest on this output. This
 * mirrors the honest scope of pathology/wsi_he_nuclei_segmentation.
 *
 * SEGMENTATION (drop-in model): the nuclei segmenter is pluggable. If StarDist
 * (2D_versatile_fluo) is present AND params.segmenter in (auto, stardist) it is
 * used on the DNA/nuclei channel; otherwise a DETERMINISTIC Otsu-threshold +
 * connected-components nuclei proxy runs (Otsu -> scipy.ndimage.label ->
 * small-object removal), keeping the demo path runnable in a plain scikit-image
 * image. Per-cell membrane/cytoplasm territories come from a radial nucleus
 * expansion (skimage.segmentation.expand_labels when available, else an identical
 * scipy distance-transform nearest-label fallback — no hard skimage>=0.19 dep). A
 * real StarDist/cellpose model drops into the SAME per-cell measurement code.
 *
 * INPUT CONTRACT (runs with NO user input):
 *   - params.image = '' (default): SYNTHESIZES a small, clearly-labelled DEMO
 *     mIHC image in-process (deterministic RNG, fixed seed): ~params.n_demo_cells
 *     synthetic cells, one channel per marker (DNA + the configured panel), with a
 *     known phenotype mix. The REAL measurement path is not faked: synthetic
 *     pixels are segmented and scored by the exact same code a real image uses.
 *     Flagged is_demo=true.
 *   - params.image = <path|http(s)|s3 URI>: a multi-channel TIFF/OME-TIFF is read
 *     as channel 0 = nuclei/DNA, channels 1..M = markers in params.markers order;
 *     a 3-channel RGB brightfield IHC is color-deconvolved (hematoxylin -> nuclei,
 *     DAB -> first marker; single-plex, a stated limitation).
 *
 * HONEST FAILURE CONTRACT: missing numpy/scikit-image/scipy, an unreadable
 * supplied image, or ZERO segmented cells exit non-zero (FATAL). The final
 * SUMMARISE step LOUD-FAILS if the quantification produced no cells. Nothing is
 * ever fabricated to make a run look successful.
 *
 * Container: biomate/bioc-domain-pathology:1.0 (ECR on AWS Batch) — the
 * purpose-built digital-pathology image (python3 + numpy + scikit-image + scipy
 * + pandas + tifffile; StarDist/cellpose optional). Same image family as
 * pathology/wsi_he_nuclei_segmentation.
 *
 * References:
 *   - Schmidt et al. 2018 MICCAI (StarDist, star-convex nuclei)
 *   - Ruifrok & Johnston 2001 Anal Quant Cytol Histol (IHC/DAB color deconvolution)
 *   - Kulangara et al. 2019 Arch Pathol Lab Med (PD-L1 CPS definition, 22C3)
 */

nextflow.enable.dsl = 2

// ---- Parameters: EVERY param has a built-in demo default so the workflow runs
// ---- with no user input at all. ----
params.outdir                 = './results'
params.image                  = ''        // optional real image (local path / http(s) / s3 URI); '' -> demo
params.markers                = '["PDL1","CD8","CD68"]'  // JSON list; arbitrary panel, ANY markers
params.marker_threshold       = '0.5'     // normalized intensity (0..1) above which a cell is positive for a marker
params.scoring_mode           = 'density' // density | phenotype | pdl1_tps_cps
params.mpp                    = '0.5'     // microns-per-pixel (for densities); demo default, override for real slides
params.segmenter              = 'auto'    // auto | stardist | proxy
params.n_demo_cells           = '300'     // synthetic cells for the demo image
params.seed                   = '7'       // deterministic RNG seed for the demo image
// --- pdl1_tps_cps preset params (ignored by other modes) ---
params.pdl1_marker            = ''        // marker name to treat as PD-L1 tumor-membrane marker ('' -> auto-detect alias)
params.pdl1_threshold         = '0.5'     // normalized PD-L1 cell intensity above which a cell is PD-L1+
params.immune_markers         = ''        // JSON list of lineage markers defining immune cells ('' -> all non-PD-L1 markers)
params.tps_positive_threshold = '0.01'    // sample TPS fraction (0.01 = 1%) at/above which the SAMPLE is called PD-L1 positive

process IHC_MARKER_QUANTIFY {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-pathology:1.0' : 'biomate/bioc-domain-pathology:1.0'

    input:
    val(meta)

    output:
    tuple val(meta), path("marker_scores.json"),       emit: score
    tuple val(meta), path("cell_quantification.csv"),  emit: cells
    tuple val(meta), path("quantification_overlay.png"), optional: true, emit: overlay
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_IMAGE="${params.image?.toString()?.replace('"', '') ?: ''}"
    export PARAM_MARKERS='${params.markers}'
    export PARAM_MARKER_THRESHOLD="${params.marker_threshold}"
    export PARAM_SCORING_MODE="${params.scoring_mode}"
    export PARAM_MPP="${params.mpp}"
    export PARAM_SEGMENTER="${params.segmenter}"
    export PARAM_N_DEMO_CELLS="${params.n_demo_cells}"
    export PARAM_SEED="${params.seed}"
    export PARAM_PDL1_MARKER="${params.pdl1_marker?.toString()?.replace('"', '') ?: ''}"
    export PARAM_PDL1_THRESHOLD="${params.pdl1_threshold}"
    export PARAM_IMMUNE_MARKERS='${params.immune_markers}'
    export PARAM_TPS_POSITIVE_THRESHOLD="${params.tps_positive_threshold}"
    export MPLCONFIGDIR="\$PWD/.mplconfig"

    BT_PY=\$(command -v python3 || command -v python)
    echo "Using python: \$BT_PY"

    "\$BT_PY" << 'PYEOF'
import os, sys, json, csv

NL = chr(10)

def fatal(msg):
    sys.stderr.write("FATAL: " + msg + NL)
    raise SystemExit("FATAL: " + msg)

# ----------------------------------------------------------------- dependencies
try:
    import numpy as np
except Exception as e:
    fatal("numpy not importable in this image (%r)." % e)

try:
    from scipy import ndimage as ndi
except Exception as e:
    fatal("scipy not importable in this image (%r); required for nuclei labelling." % e)

try:
    from skimage.filters import threshold_otsu
    from skimage import color as skcolor
    from skimage import io as skio
except Exception as e:
    fatal("scikit-image not importable in this image (%r); required for segmentation "
          "and color deconvolution." % e)

def cell_territory(labels, distance=4):
    # Per-cell nucleus+membrane/cytoplasm territory = each nucleus grown radially
    # into nearby background. Uses skimage.segmentation.expand_labels when present
    # (skimage >= 0.19); otherwise an identical scipy-only nearest-label expansion
    # so we never hard-depend on a specific skimage version.
    try:
        from skimage.segmentation import expand_labels
        return expand_labels(labels, distance=distance)
    except Exception:
        background = labels == 0
        dist, (iy, ix) = ndi.distance_transform_edt(background, return_indices=True)
        nearest = labels[iy, ix]
        out = labels.copy()
        grow = background & (dist <= distance)
        out[grow] = nearest[grow]
        return out

# ----------------------------------------------------------------- parameters
def as_float(name, default):
    v = os.environ.get(name, "")
    if v in (None, "", "null"):
        return default
    try:
        return float(v)
    except Exception:
        fatal("parameter %s must be numeric, got %r" % (name, v))

def as_int(name, default):
    return int(round(as_float(name, default)))

image_param   = os.environ.get("PARAM_IMAGE", "").strip()
marker_thr    = as_float("PARAM_MARKER_THRESHOLD", 0.5)
scoring_mode  = (os.environ.get("PARAM_SCORING_MODE", "density") or "density").strip().lower()
mpp           = as_float("PARAM_MPP", 0.5)
segmenter     = (os.environ.get("PARAM_SEGMENTER", "auto") or "auto").strip().lower()
n_demo_cells  = as_int("PARAM_N_DEMO_CELLS", 300)
seed          = as_int("PARAM_SEED", 7)
pdl1_param    = (os.environ.get("PARAM_PDL1_MARKER", "") or "").strip()
pdl1_thr      = as_float("PARAM_PDL1_THRESHOLD", 0.5)
tps_pos_thr   = as_float("PARAM_TPS_POSITIVE_THRESHOLD", 0.01)

VALID_MODES = ("density", "phenotype", "pdl1_tps_cps")
if scoring_mode not in VALID_MODES:
    fatal("params.scoring_mode %r not supported; use one of density|phenotype|pdl1_tps_cps." % scoring_mode)

try:
    markers = json.loads(os.environ.get("PARAM_MARKERS") or "[]")
except Exception as e:
    fatal("could not parse params.markers JSON (%r)." % e)
markers = [str(m).strip() for m in markers if str(m).strip()]
if not markers:
    fatal("params.markers is empty; supply at least one marker such as PDL1, CD8, CD68.")

try:
    immune_markers_param = json.loads(os.environ.get("PARAM_IMMUNE_MARKERS") or "[]")
except Exception:
    immune_markers_param = []
immune_markers_param = [str(m).strip() for m in immune_markers_param if str(m).strip()]

if mpp <= 0:
    fatal("params.mpp (microns-per-pixel) must be > 0, got %s" % mpp)

# PD-L1 marker resolution (for the pdl1_tps_cps preset).
PDL1_ALIASES = ("PDL1", "PD-L1", "PD_L1", "CD274", "PDL-1")
def canon(s):
    return s.upper().replace(" ", "").replace("-", "").replace("_", "")
pdl1_name = None
if pdl1_param:
    for m in markers:
        if m == pdl1_param or canon(m) == canon(pdl1_param):
            pdl1_name = m
            break
    if pdl1_name is None:
        fatal("params.pdl1_marker %r is not in params.markers %r." % (pdl1_param, markers))
else:
    alias_set = set(canon(a) for a in PDL1_ALIASES)
    for m in markers:
        if canon(m) in alias_set:
            pdl1_name = m
            break

# immune (lineage) markers for tumor/immune split in pdl1 mode
if immune_markers_param:
    immune_markers = [m for m in immune_markers_param if m in markers]
else:
    immune_markers = [m for m in markers if m != pdl1_name]

# ----------------------------------------------------------------- image (real or synthesized demo)
is_demo    = False
img_source = "user_supplied"
nuclei = None
marker_planes = {}

def normalize(a):
    a = np.asarray(a, dtype=np.float64)
    lo, hi = float(a.min()), float(a.max())
    if hi > lo:
        return (a - lo) / (hi - lo)
    return np.zeros_like(a)

def fetch_remote(uri):
    base = os.path.basename(uri.split("?")[0]) or "input_image.tif"
    dest = os.path.join(os.getcwd(), base)
    if uri.startswith(("http://", "https://")):
        import urllib.request
        urllib.request.urlretrieve(uri, dest)
    elif uri.startswith("s3://"):
        import subprocess, shutil, urllib.parse
        try:
            import boto3
            p = urllib.parse.urlparse(uri)
            boto3.client("s3").download_file(p.netloc, p.path.lstrip("/"), dest)
        except Exception:
            aws_bin = shutil.which("aws") or next(
                (b for b in ("/opt/aws-cli/aws", "/opt/aws-cli/bin/aws", "/usr/local/bin/aws") if os.path.exists(b)),
                None)
            if not aws_bin:
                fatal("could not download s3 image %s: boto3 unavailable and no aws CLI found." % uri)
            r = subprocess.run([aws_bin, "s3", "cp", uri, dest], capture_output=True, text=True)
            if r.returncode != 0:
                fatal("aws s3 cp failed for %s: %s" % (uri, (r.stderr or "").strip()))
    else:
        return None
    return dest

def read_image(path):
    ext = os.path.splitext(path)[1].lower()
    arr = None
    if ext in (".tif", ".tiff"):
        try:
            import tifffile
            arr = tifffile.imread(path)
        except Exception as e:
            fatal("tifffile could not read %s (%r)." % (path, e))
    else:
        try:
            arr = skio.imread(path)
        except Exception as e:
            fatal("could not read image %s (%r)." % (path, e))
    return np.asarray(arr)

def map_channels_from_array(arr):
    arr = np.asarray(arr)
    # RGB brightfield IHC -> color deconvolution (hematoxylin=nuclei, DAB=first marker)
    if arr.ndim == 3 and arr.shape[2] == 3:
        hed = skcolor.rgb2hed(arr)
        nuc = normalize(hed[:, :, 0])
        dab = normalize(hed[:, :, 2])
        planes = {}
        for i, m in enumerate(markers):
            planes[m] = dab if i == 0 else None
        return nuc, planes, "rgb_brightfield_deconvolution_singleplex"
    # Multi-channel stack: channel 0 = nuclei, 1.. = markers
    if arr.ndim == 3:
        stack = arr if arr.shape[0] <= arr.shape[2] else np.moveaxis(arr, 2, 0)
        nchan = stack.shape[0]
        if nchan < 2:
            fatal("multi-channel image has %d channel(s); need >=2 (nuclei + >=1 marker)." % nchan)
        nuc = normalize(stack[0])
        planes = {}
        for i, m in enumerate(markers):
            ci = i + 1
            planes[m] = normalize(stack[ci]) if ci < nchan else None
        return nuc, planes, "multichannel_stack"
    if arr.ndim == 2:
        fatal("supplied a single-plane 2D image; cannot separate nuclei from markers. "
              "Provide a multi-channel mIHC/IF stack or an RGB brightfield IHC image.")
    fatal("unsupported image shape %r." % (arr.shape,))

def synthesize_demo():
    # Deterministic synthetic mIHC: DNA + one plane per marker, with a known
    # phenotype mix so marker stats / phenotype / TPS-CPS are meaningful on demo.
    rng = np.random.default_rng(seed)
    H = W = 512
    spacing = 26
    sigma_nuc = 3.5
    planes = {m: np.zeros((H, W), dtype=np.float64) for m in markers}
    dna = np.zeros((H, W), dtype=np.float64)

    centers = []
    for cy in range(spacing, H - spacing, spacing):
        for cx in range(spacing, W - spacing, spacing):
            centers.append((cy + int(rng.integers(-5, 6)), cx + int(rng.integers(-5, 6))))
    rng.shuffle(centers)
    centers = centers[:max(1, n_demo_cells)]

    yy, xx = np.mgrid[0:H, 0:W]
    lineage = [m for m in markers if m != pdl1_name]

    def stamp(plane, cyx, amp, sigma):
        cy, cx = cyx
        y0, y1 = max(0, cy - 12), min(H, cy + 13)
        x0, x1 = max(0, cx - 12), min(W, cx + 13)
        sy = yy[y0:y1, x0:x1]; sx = xx[y0:y1, x0:x1]
        plane[y0:y1, x0:x1] += amp * np.exp(-(((sy - cy) ** 2 + (sx - cx) ** 2) / (2.0 * sigma * sigma)))

    for (cy, cx) in centers:
        stamp(dna, (cy, cx), 1.0, sigma_nuc)
        is_tumor = bool(rng.random() < 0.60)
        # immune cells express exactly one lineage marker (picked round-robin-ish)
        expressed = None
        if not is_tumor and lineage:
            expressed = lineage[int(rng.integers(0, len(lineage)))]
            stamp(planes[expressed], (cy, cx), 0.9 + 0.3 * rng.random(), sigma_nuc + 2.0)
        # PD-L1-like membrane positivity (if a PD-L1 marker is in the panel)
        if pdl1_name is not None:
            p = 0.45 if is_tumor else 0.30
            if rng.random() < p:
                stamp(planes[pdl1_name], (cy, cx), 0.9 + 0.4 * rng.random(), sigma_nuc + 2.5)

    dna = ndi.gaussian_filter(dna, 0.8)
    for m in markers:
        planes[m] = ndi.gaussian_filter(planes[m], 0.8)
        planes[m] = normalize(planes[m] + 0.02 * rng.random((H, W)))
    dna = normalize(dna + 0.02 * rng.random((H, W)))
    return dna, planes

if image_param in ("", None, "null"):
    nuclei, marker_planes = synthesize_demo()
    is_demo = True
    img_source = "DEMO: synthesized mIHC image (deterministic, seed=%d)" % seed
    channel_mode = "synthetic_multichannel"
    print("No params.image supplied; synthesized a DEMO mIHC image [DEMO DATA].")
else:
    local = image_param
    if str(image_param).startswith(("http://", "https://", "s3://")):
        local = fetch_remote(image_param)
        if not local:
            fatal("could not resolve remote image URI %s" % image_param)
    if not os.path.exists(local):
        fatal("image path does not exist on the worker: %s" % local)
    arr = read_image(local)
    nuclei, marker_planes, channel_mode = map_channels_from_array(arr)
    img_source = "user_supplied: %s (%s)" % (os.path.basename(str(image_param)), channel_mode)
    print("Loaded user image %s [mode=%s]" % (local, channel_mode))

H, W = nuclei.shape
nuclei = normalize(nuclei)

# ----------------------------------------------------------------- nuclei segmentation
seg_method = None

def segment_stardist(nuc):
    try:
        from stardist.models import StarDist2D
    except Exception:
        return None, None
    try:
        model = StarDist2D.from_pretrained("2D_versatile_fluo")
        labels, _ = model.predict_instances(normalize(nuc))
        return np.asarray(labels).astype(np.int32), "stardist:2D_versatile_fluo"
    except Exception as e:
        print("StarDist available but failed (%r); falling back to proxy." % e)
        return None, None

def segment_proxy(nuc):
    try:
        thr = float(threshold_otsu(nuc)) if nuc.max() > nuc.min() else 1.0
    except Exception:
        thr = 0.3
    binary = nuc > max(thr, 0.08)
    lbl, n = ndi.label(binary)
    if n == 0:
        return lbl.astype(np.int32), "proxy:otsu_connected_components"
    sizes = ndi.sum(np.ones_like(lbl), lbl, index=np.arange(1, n + 1))
    keep = set(int(i + 1) for i, s in enumerate(sizes) if s >= 6)
    out = np.zeros_like(lbl)
    nxt = 1
    for old in keep:
        out[lbl == old] = nxt
        nxt += 1
    return out.astype(np.int32), "proxy:otsu_connected_components"

labels = None
if segmenter in ("auto", "stardist"):
    labels, seg_method = segment_stardist(nuclei)
if labels is None:
    if segmenter == "stardist":
        print("params.segmenter=stardist but StarDist unavailable; using deterministic proxy.")
    labels, seg_method = segment_proxy(nuclei)

n_cells = int(labels.max())
if n_cells == 0:
    fatal("no cells were segmented from the nuclei channel (method=%s). Check the "
          "image / segmenter; refusing to emit fabricated cells." % seg_method)

territory = cell_territory(labels, distance=4)

# ----------------------------------------------------------------- per-cell quantification
centroids = ndi.center_of_mass(np.ones_like(labels), labels, index=np.arange(1, n_cells + 1))
areas = ndi.sum(np.ones_like(labels), labels, index=np.arange(1, n_cells + 1))

def marker_cell_means(plane):
    if plane is None:
        return None
    return ndi.mean(plane, territory, index=np.arange(1, n_cells + 1))

marker_means = {m: marker_cell_means(marker_planes.get(m)) for m in markers}

cells = []
for i in range(n_cells):
    cy, cx = centroids[i]
    row = {
        "cell_id": i + 1,
        "centroid_x": round(float(cx), 2),
        "centroid_y": round(float(cy), 2),
        "area_px": int(round(float(areas[i]))),
    }
    pos_markers = []
    for m in markers:
        vals = marker_means[m]
        inten = None if vals is None else round(float(vals[i]), 4)
        row["%s_intensity" % m] = inten
        thr = pdl1_thr if m == pdl1_name else marker_thr
        pos = (inten is not None) and (inten >= thr)
        row["%s_positive" % m] = int(bool(pos))
        if pos:
            pos_markers.append(m)
    # generic phenotype label = concatenation of positive markers (or 'negative')
    phenotype = ("".join([p + "+" for p in pos_markers])) if pos_markers else "negative"
    row["phenotype"] = phenotype
    cells.append(row)

# ----------------------------------------------------------------- per-marker stats + densities
area_mm2 = (H * W) * (mpp * mpp) / 1.0e6
marker_stats = {}
for m in markers:
    n_pos = sum(1 for c in cells if c.get("%s_positive" % m) == 1)
    marker_stats[m] = {
        "n_positive": n_pos,
        "fraction_positive": round(n_pos / float(n_cells), 4) if n_cells else None,
        "density_per_mm2": round(n_pos / area_mm2, 2) if area_mm2 > 0 else None,
        "channel_present": marker_planes.get(m) is not None,
    }

# ----------------------------------------------------------------- phenotype composition
pheno_counts = {}
for c in cells:
    pheno_counts[c["phenotype"]] = pheno_counts.get(c["phenotype"], 0) + 1
phenotype_composition = [
    {"phenotype": k, "n_cells": v, "fraction": round(v / float(n_cells), 4)}
    for k, v in sorted(pheno_counts.items(), key=lambda kv: kv[1], reverse=True)
]

# ----------------------------------------------------------------- optional PD-L1 TPS/CPS preset
pdl1_block = None
if scoring_mode == "pdl1_tps_cps":
    if pdl1_name is None:
        fatal("scoring_mode=pdl1_tps_cps but no PD-L1 marker found. Add a PD-L1-like "
              "marker to params.markers (e.g. PDL1 / CD274) or set params.pdl1_marker.")
    # tumor vs immune: a cell is immune if positive for ANY immune lineage marker
    for c in cells:
        is_immune = any(c.get("%s_positive" % m) == 1 for m in immune_markers)
        c["cell_type"] = "immune" if is_immune else "tumor"
        c["pdl1_positive"] = int(c.get("%s_positive" % pdl1_name) == 1)
    n_tumor = sum(1 for c in cells if c["cell_type"] == "tumor")
    n_immune = sum(1 for c in cells if c["cell_type"] == "immune")
    n_pos_tumor = sum(1 for c in cells if c["cell_type"] == "tumor" and c["pdl1_positive"] == 1)
    n_pos_immune = sum(1 for c in cells if c["cell_type"] == "immune" and c["pdl1_positive"] == 1)
    n_pdl1_pos = n_pos_tumor + n_pos_immune
    tps = round(100.0 * n_pos_tumor / n_tumor, 3) if n_tumor > 0 else None
    cps_raw = (100.0 * (n_pos_tumor + n_pos_immune) / n_tumor) if n_tumor > 0 else None
    cps = round(min(cps_raw, 100.0), 3) if cps_raw is not None else None
    tps_call = None
    if tps is not None:
        tps_call = "positive" if (tps / 100.0) >= tps_pos_thr else "negative"
    pdl1_block = {
        "pdl1_marker": pdl1_name,
        "immune_markers": immune_markers,
        "n_tumor": n_tumor, "n_immune": n_immune, "n_pdl1_pos": n_pdl1_pos,
        "n_pdl1_pos_tumor": n_pos_tumor, "n_pdl1_pos_immune": n_pos_immune,
        "TPS": tps, "TPS_units": "percent of tumor cells PD-L1 positive", "TPS_call": tps_call,
        "CPS": cps, "CPS_units": "100 * (PD-L1+ tumor + PD-L1+ immune) / viable tumor cells, capped at 100",
        "tps_positive_threshold": tps_pos_thr,
    }

# ----------------------------------------------------------------- write cell_quantification.csv
marker_cols = []
for m in markers:
    marker_cols.append("%s_intensity" % m)
    marker_cols.append("%s_positive" % m)
cols = ["cell_id", "centroid_x", "centroid_y", "area_px"] + marker_cols + ["phenotype"]
if scoring_mode == "pdl1_tps_cps":
    cols += ["cell_type", "pdl1_positive"]
with open("cell_quantification.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for c in cells:
        w.writerow({k: c.get(k) for k in cols})

# ----------------------------------------------------------------- write marker_scores.json
score = {
    "workflow": "imaging/ihc_marker_quantification",
    "research_use_only": True,
    "is_demo": is_demo,
    "image_source": img_source,
    "scoring_mode": scoring_mode,
    "disclaimer": ("Computational estimate from an automated multiplex-IHC/IF "
                   "quantification pipeline. NOT a pathologist read and NOT a "
                   "diagnostic result; a qualified pathologist must review any call."),
    "image": {"height_px": int(H), "width_px": int(W), "mpp_um": mpp,
              "area_mm2": round(area_mm2, 4), "channel_mode": channel_mode},
    "segmentation": {"method": seg_method, "territory": "nucleus radial expansion (distance=4px)",
                     "n_cells": int(n_cells)},
    "markers": markers,
    "marker_threshold": marker_thr,
    "n_cells": int(n_cells),
    "marker_stats": marker_stats,
    "phenotype_composition": phenotype_composition,
    "pdl1_tps_cps": pdl1_block,
    "status": "ok",
}
with open("marker_scores.json", "w") as fh:
    json.dump(score, fh, indent=2)
_head = {"scoring_mode": scoring_mode, "n_cells": n_cells,
         "n_phenotypes": len(phenotype_composition)}
if pdl1_block is not None:
    _head["TPS"] = pdl1_block["TPS"]; _head["CPS"] = pdl1_block["CPS"]
print(json.dumps(_head, indent=2))

# ----------------------------------------------------------------- overlay preview (best-effort)
try:
    # distinct color per phenotype so the overlay reflects the real panel
    palette = [(210, 90, 20), (30, 190, 30), (220, 40, 40), (40, 120, 220),
               (230, 200, 20), (170, 60, 200), (0, 180, 180), (255, 140, 0)]
    pheno_order = [p["phenotype"] for p in phenotype_composition]
    color_of = {}
    ci = 0
    for ph in pheno_order:
        if ph == "negative":
            color_of[ph] = (170, 170, 170)
        else:
            color_of[ph] = palette[ci % len(palette)]; ci += 1
    rgb = np.zeros((H, W, 3), dtype=np.uint8)
    rgb[:, :, 2] = (normalize(nuclei) * 90).astype(np.uint8)
    for c in cells:
        cy = int(round(c["centroid_y"])); cx = int(round(c["centroid_x"]))
        y0, y1 = max(0, cy - 2), min(H, cy + 3)
        x0, x1 = max(0, cx - 2), min(W, cx + 3)
        col = color_of.get(c["phenotype"], (255, 255, 255))
        rgb[y0:y1, x0:x1, 0] = col[0]; rgb[y0:y1, x0:x1, 1] = col[1]; rgb[y0:y1, x0:x1, 2] = col[2]
    skio.imsave("quantification_overlay.png", rgb, check_contrast=False)
except Exception as e:
    print("overlay render skipped (%r)" % e)

# ----------------------------------------------------------------- versions.yml
def ver(mod):
    try:
        import importlib
        return str(getattr(importlib.import_module(mod), "__version__", "NA"))
    except Exception:
        return "NA"

with open("versions.yml", "w") as fh:
    lines = []
    lines.append("ihc_marker_quantify:")
    lines.append('  python: "%s"' % sys.version.split()[0])
    lines.append('  numpy: "%s"' % ver("numpy"))
    lines.append('  scikit_image: "%s"' % ver("skimage"))
    lines.append('  scipy: "%s"' % ver("scipy"))
    lines.append('  stardist: "%s"' % ver("stardist"))
    fh.write(NL.join(lines) + NL)

print("Quantification done: n_cells=%d markers=%d mode=%s phenotypes=%d" %
      (n_cells, len(markers), scoring_mode, len(phenotype_composition)))
PYEOF
    """
}

process SUMMARISE {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-pathology:1.0' : 'biomate/bioc-domain-pathology:1.0'

    input:
    tuple val(meta), path("marker_scores.json"), path("cell_quantification.csv")

    output:
    tuple val(meta), path("summary.json"),     emit: summary
    tuple val(meta), path("qc_metrics.json"),  emit: qc

    script:
    """
    "\$(command -v python3 || command -v python)" << 'PYEOF'
import os, sys, json, csv

NL = chr(10)

def fatal(msg):
    sys.stderr.write("FATAL: " + msg + NL)
    raise SystemExit("FATAL: " + msg)

if not os.path.exists("marker_scores.json"):
    fatal("marker_scores.json missing; the quantification step produced no score.")
if not os.path.exists("cell_quantification.csv"):
    fatal("cell_quantification.csv missing; the quantification step produced no cells.")

with open("marker_scores.json") as fh:
    score = json.load(fh)

rows = []
with open("cell_quantification.csv", newline="") as fh:
    for r in csv.DictReader(fh):
        rows.append(r)

n_cells = len(rows)
if n_cells == 0:
    fatal("cell_quantification.csv has zero cells; the workflow produced no usable "
          "output (no cells segmented). Refusing to report an empty success.")

seg = score.get("segmentation", {})
img = score.get("image", {})
marker_stats = score.get("marker_stats", {})
mode = score.get("scoring_mode", "density")
pdl1 = score.get("pdl1_tps_cps")
pheno = score.get("phenotype_composition", [])

# ---- summary.json: headline, mode-aware
summary = {
    "workflow": "imaging/ihc_marker_quantification",
    "research_use_only": True,
    "is_demo": score.get("is_demo"),
    "scoring_mode": mode,
    "disclaimer": score.get("disclaimer"),
    "n_cells": n_cells,
    "markers": score.get("markers", []),
    "marker_densities_per_mm2": {m: marker_stats.get(m, {}).get("density_per_mm2") for m in score.get("markers", [])},
    "marker_positive_counts": {m: marker_stats.get(m, {}).get("n_positive") for m in score.get("markers", [])},
    "phenotype_composition": pheno[:12],
    "status": score.get("status", "ok"),
    "headline": None,
}
if mode == "pdl1_tps_cps" and pdl1 is not None:
    summary["TPS"] = pdl1.get("TPS"); summary["TPS_call"] = pdl1.get("TPS_call")
    summary["CPS"] = pdl1.get("CPS")
    summary["headline"] = ("PD-L1 TPS=%s%% (%s), CPS=%s over %d cells (%d tumor / %d immune). "
                           "COMPUTATIONAL ESTIMATE — pathologist review required." %
                           (pdl1.get("TPS"), pdl1.get("TPS_call"), pdl1.get("CPS"), n_cells,
                            pdl1.get("n_tumor") or 0, pdl1.get("n_immune") or 0))
elif mode == "phenotype":
    top = pheno[0] if pheno else {"phenotype": "NA", "n_cells": 0}
    summary["headline"] = ("Phenotyped %d cells into %d phenotypes; most common: %s (%d cells). "
                           "COMPUTATIONAL ESTIMATE — pathologist review required." %
                           (n_cells, len(pheno), top.get("phenotype"), top.get("n_cells")))
else:
    dens = summary["marker_densities_per_mm2"]
    summary["headline"] = ("Marker densities (cells/mm^2) over %d cells: %s. "
                           "COMPUTATIONAL ESTIMATE — pathologist review required." %
                           (n_cells, json.dumps(dens)))
with open("summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)

# ---- qc_metrics.json: QC / provenance + independent recompute from the CSV
csv_pheno = {}
for r in rows:
    csv_pheno[r.get("phenotype")] = csv_pheno.get(r.get("phenotype"), 0) + 1
score_pheno = {p["phenotype"]: p["n_cells"] for p in pheno}

qc = {
    "workflow": "imaging/ihc_marker_quantification",
    "research_use_only": True,
    "scoring_mode": mode,
    "n_cells": n_cells,
    "segmentation_method": seg.get("method"),
    "cell_territory": seg.get("territory"),
    "image_height_px": img.get("height_px"),
    "image_width_px": img.get("width_px"),
    "mpp_um": img.get("mpp_um"),
    "area_mm2": img.get("area_mm2"),
    "channel_mode": img.get("channel_mode"),
    "marker_threshold": score.get("marker_threshold"),
    "marker_channel_present": {m: marker_stats.get(m, {}).get("channel_present") for m in score.get("markers", [])},
    "consistency_check": {
        "phenotype_counts_match": csv_pheno == score_pheno,
        "csv_phenotype_counts": csv_pheno,
    },
    "status": "completed",
    "note": "Scores are computational estimates, not a pathologist read.",
}
if mode == "pdl1_tps_cps" and pdl1 is not None:
    csv_tumor = sum(1 for r in rows if r.get("cell_type") == "tumor")
    csv_immune = sum(1 for r in rows if r.get("cell_type") == "immune")
    csv_pdl1 = sum(1 for r in rows if str(r.get("pdl1_positive")) == "1")
    qc["consistency_check"]["tumor_match"] = pdl1.get("n_tumor") == csv_tumor
    qc["consistency_check"]["immune_match"] = pdl1.get("n_immune") == csv_immune
    qc["consistency_check"]["pdl1_match"] = pdl1.get("n_pdl1_pos") == csv_pdl1
with open("qc_metrics.json", "w") as fh:
    json.dump(qc, fh, indent=2)

print("Summary written: n_cells=%d mode=%s status=%s" % (n_cells, mode, summary["status"]))
PYEOF
    """
}

workflow IHC_MARKER_QUANTIFICATION {
    take:
    meta_ch

    main:
    IHC_MARKER_QUANTIFY(meta_ch)
    SUMMARISE(
        IHC_MARKER_QUANTIFY.out.score.join(IHC_MARKER_QUANTIFY.out.cells)
    )

    emit:
    score    = IHC_MARKER_QUANTIFY.out.score
    cells    = IHC_MARKER_QUANTIFY.out.cells
    overlay  = IHC_MARKER_QUANTIFY.out.overlay
    summary  = SUMMARISE.out.summary
    qc       = SUMMARISE.out.qc
    versions = IHC_MARKER_QUANTIFY.out.versions
}

// Entry workflow for standalone execution (runs with NO user input).
workflow {
    meta = [id: 'ihc_marker_run']
    Channel.value(meta) | IHC_MARKER_QUANTIFICATION
}
