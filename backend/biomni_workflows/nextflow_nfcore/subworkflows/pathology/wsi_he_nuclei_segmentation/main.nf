#!/usr/bin/env nextflow
/*
 * pathology/wsi_he_nuclei_segmentation
 *
 * RESEARCH-USE-ONLY whole-slide-image (WSI) H&E preprocessing + nuclei
 * segmentation. This is the narrow, honestly-scoped first deliverable from
 * docs/20261003_PATHOLOGY_WSI_CAPABILITY_AUDIT.md ("Recommended first
 * deliverable") — NOT a diagnostic device and NOT a WSI-platform claim.
 *
 * Pipeline (all steps run on REAL data; no fabrication, no RNG, no demo slide):
 *   1. Ingest ONE WSI via OpenSlide — one OpenSlide format (e.g. Aperio .svs)
 *      plus pyramidal OME-TIFF. A real --input_wsi is MANDATORY; there is NO
 *      built-in/fallback slide (fabricated inputs are forbidden), so the
 *      process exits non-zero with a clear message when it is missing.
 *   2. Deterministic tissue tiling: a fixed raster grid at level 0 with tile
 *      coordinates, Otsu-on-saturation tissue detection (background flag) and
 *      variance-of-Laplacian focus QC (blur flag). Fully deterministic.
 *   3. ONE pinned, license-clean nuclei model: Cellpose (BSD-3-Clause),
 *      model_type='nuclei', fed the hematoxylin channel (skimage rgb2hed).
 *      Pretrained weights are the real cellpose weights (downloaded to
 *      ~/.cellpose on first use — requires worker network egress).
 *   4. Emit: per-tile labelled masks, a stitched QC overlay, a per-nucleus
 *      cell table (CSV), a QC summary JSON, a model/version manifest, and a
 *      clearly-labelled "RESEARCH USE ONLY — pathologist review required" report.
 *
 * HONEST FAILURE CONTRACT: if OpenSlide, cellpose, scikit-image/scipy, the
 * model weights, or the input slide are unavailable, the process exits
 * non-zero with an actionable message. It never emits fabricated results.
 *
 * CONTAINER: the process-level `container` directive below is what actually
 * runs on AWS Batch (it OVERRIDES the DB docker_image). It is pinned to the
 * real, registry-verified cellpose biocontainer. NOTE (owner validation): the
 * single-tool cellpose biocontainer may not ship the OpenSlide C library +
 * openslide-python; if OpenSlide is absent the workflow honest-fails at import
 * time. The validated deployment image must bundle OpenSlide + cellpose. This
 * is exactly why the DB row ships executable=0 until an owner validation run
 * on a licensed annotated slide confirms it end-to-end. See
 * docs/20261003_PATHOLOGY_WSI_WORKFLOW.md.
 *
 * References:
 *   - Stringer et al. 2021 Nature Methods (Cellpose)
 *   - Goode et al. 2013 J Pathol Inform (OpenSlide)
 *   - Ruifrok & Johnston 2001 Anal Quant Cytol Histol (H&E color deconvolution)
 */

nextflow.enable.dsl = 2

// Parameters (a real --input_wsi is required; everything else has a safe default)
params.outdir               = './results'
params.input_wsi            = null      // REQUIRED: path to one .svs/OpenSlide WSI or pyramidal OME-TIFF
params.tile_size            = '512'     // level-0 tile edge in pixels
params.tile_overlap         = '0'       // tile overlap in pixels (0 <= overlap < tile_size)
params.max_tiles            = '200'     // bound processed tissue tiles for a preview run (<=0 = all)
params.tissue_threshold     = '0.10'    // min tissue fraction for a tile to count as tissue
params.blur_threshold       = '100.0'   // var-of-Laplacian (x1e4) below this = blurry
params.cell_diameter        = '0'       // nuclei diameter in px (<=0 = cellpose auto)
params.flow_threshold       = '0.4'     // cellpose flow error threshold
params.cellprob_threshold   = '0.0'     // cellpose cell-probability threshold
params.mpp                  = 'null'    // override microns-per-pixel if not in slide metadata
params.use_gpu              = 'false'   // run cellpose on GPU if available
params.model_type           = 'nuclei'  // nuclei | cyto | cyto2 | cyto3

process WSI_HE_NUCLEI_SEGMENTATION {
    tag "$meta.id"
    label 'process_high'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Pinned, registry-verified, license-clean (BSD-3-Clause) cellpose biocontainer.
    // This directive OVERRIDES the DB docker_image on AWS Batch, so it MUST be set here.
    // Verified live on quay.io (tag 3.1.0 active; manifest sha256:0467d790...). Do NOT pull/run.
    container 'quay.io/biocontainers/cellpose:3.1.0'

    input:
    val(meta)

    output:
    tuple val(meta), path("tiles/*_mask.png"),               optional: true, emit: masks
    tuple val(meta), path("qc_overlay.png"),                                 emit: overlay
    tuple val(meta), path("cell_table.csv"),                                 emit: cells
    tuple val(meta), path("qc_summary.json"),                                emit: qc
    tuple val(meta), path("model_manifest.json"),                            emit: manifest
    tuple val(meta), path("RESEARCH_USE_ONLY_report.txt"),                   emit: report
    path "versions.yml",                                                     emit: versions

    script:
    """
    export PARAM_INPUT_WSI="${params.input_wsi?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TILE_SIZE="${params.tile_size}"
    export PARAM_TILE_OVERLAP="${params.tile_overlap}"
    export PARAM_MAX_TILES="${params.max_tiles}"
    export PARAM_TISSUE_THRESHOLD="${params.tissue_threshold}"
    export PARAM_BLUR_THRESHOLD="${params.blur_threshold}"
    export PARAM_CELL_DIAMETER="${params.cell_diameter}"
    export PARAM_FLOW_THRESHOLD="${params.flow_threshold}"
    export PARAM_CELLPROB_THRESHOLD="${params.cellprob_threshold}"
    export PARAM_MPP="${params.mpp}"
    export PARAM_USE_GPU="${params.use_gpu}"
    export PARAM_MODEL_TYPE="${params.model_type}"
    export MPLCONFIGDIR="\$PWD/.mplconfig"

    # Resolve a cellpose-capable interpreter robustly across images.
    BT_PY=\$(command -v python3 || command -v python)
    for _cand in /opt/conda/envs/cellpose/bin/python /opt/conda/bin/python /usr/local/bin/python3; do
      if [ -x "\$_cand" ] && "\$_cand" -c 'import cellpose' >/dev/null 2>&1; then BT_PY="\$_cand"; break; fi
    done
    echo "Using python: \$BT_PY"

    "\$BT_PY" << 'PYEOF'
import json, os, sys, csv

NL = chr(10)

def fail(msg):
    sys.stderr.write("ERROR: " + msg + NL)
    sys.exit(1)

# ---------------------------------------------------------------- dependencies
# Honest-fail (non-zero) if any hard dependency is missing. No fabricated data,
# no RNG, no placeholder numbers: if we cannot read the slide or run the model,
# the process exits non-zero with a clear, actionable message.
try:
    import numpy as np
except Exception as e:
    fail("numpy not importable in this image (%r)." % e)

try:
    import openslide
except Exception as e:
    fail("openslide (python binding + libopenslide C library) is NOT importable "
         "in this container (%r). This workflow ingests WSIs via OpenSlide and "
         "refuses to run without it. The validated deployment image MUST bundle "
         "the OpenSlide C library + openslide-python together with cellpose "
         "(the pinned quay.io/biocontainers/cellpose image may not ship OpenSlide). "
         "No fallback reader is used so that failures are explicit, not silent." % e)

try:
    from cellpose import models as cp_models
except Exception as e:
    fail("cellpose not importable in this container (%r). This workflow requires a "
         "pinned cellpose install (quay.io/biocontainers/cellpose:3.1.0). "
         "Refusing to emit fabricated segmentation." % e)

try:
    from skimage import color as skcolor
    from skimage import draw as skdraw
    from skimage import io as skio
    from skimage import measure as skmeasure
    from skimage import util as skutil
except Exception as e:
    fail("scikit-image not importable in this container (%r); required for H&E stain "
         "deconvolution, QC and overlay rendering." % e)

try:
    from scipy import ndimage as ndi
except Exception as e:
    fail("scipy not importable in this container (%r); required for focus (blur) QC." % e)

# ---------------------------------------------------------------- parameters
def _as_float(name, default):
    v = os.environ.get(name, "")
    if v in (None, "", "null"):
        return default
    try:
        return float(v)
    except Exception:
        fail("parameter %s must be numeric, got %r" % (name, v))

def _as_int(name, default):
    return int(_as_float(name, default))

input_wsi        = os.environ.get("PARAM_INPUT_WSI", "null")
tile_size        = _as_int("PARAM_TILE_SIZE", 512)
tile_overlap     = _as_int("PARAM_TILE_OVERLAP", 0)
max_tiles        = _as_int("PARAM_MAX_TILES", 200)
tissue_threshold = _as_float("PARAM_TISSUE_THRESHOLD", 0.10)
blur_threshold   = _as_float("PARAM_BLUR_THRESHOLD", 100.0)
cell_diameter    = _as_float("PARAM_CELL_DIAMETER", 0.0)
flow_threshold   = _as_float("PARAM_FLOW_THRESHOLD", 0.4)
cellprob_thr     = _as_float("PARAM_CELLPROB_THRESHOLD", 0.0)
mpp_override     = os.environ.get("PARAM_MPP", "null")
use_gpu_raw      = os.environ.get("PARAM_USE_GPU", "false")
model_type       = os.environ.get("PARAM_MODEL_TYPE", "nuclei")

use_gpu = str(use_gpu_raw).lower() in ("true", "1", "yes")
if tile_size < 32:
    fail("tile_size must be >= 32, got %d" % tile_size)
if tile_overlap < 0 or tile_overlap >= tile_size:
    fail("tile_overlap must satisfy 0 <= overlap < tile_size (got %d, tile_size %d)" % (tile_overlap, tile_size))
if model_type not in ("nuclei", "cyto", "cyto2", "cyto3"):
    fail("model_type %r not supported; use one of nuclei|cyto|cyto2|cyto3" % model_type)

# ---------------------------------------------------------------- inputs
# No fabricated fallback: a real --input_wsi is mandatory.
if input_wsi in (None, "", "null"):
    fail("no --input_wsi supplied. This workflow has NO demo/fallback slide by "
         "design (fabricated inputs are forbidden). Provide a real WSI file "
         "(e.g. Aperio .svs or pyramidal OME-TIFF .ome.tif) via --input_wsi.")
if not os.path.exists(input_wsi):
    fail("input WSI path does not exist on the worker: %s" % input_wsi)

try:
    slide = openslide.OpenSlide(input_wsi)
except Exception as e:
    fail("OpenSlide could not open %s (%r). Supported here: one OpenSlide WSI "
         "format (e.g. Aperio .svs) plus pyramidal OME-TIFF. If this is a plain "
         "(non-pyramidal) TIFF OpenSlide will reject it." % (input_wsi, e))

W, H = slide.level_dimensions[0]
n_levels = slide.level_count
props = dict(slide.properties)
vendor = props.get("openslide.vendor", "unknown")

def _mpp():
    if mpp_override not in (None, "", "null"):
        try:
            m = float(mpp_override)
            return m, m, "user_override"
        except Exception:
            fail("PARAM_MPP must be numeric microns-per-pixel, got %r" % mpp_override)
    mx = props.get(openslide.PROPERTY_NAME_MPP_X)
    my = props.get(openslide.PROPERTY_NAME_MPP_Y)
    if mx and my:
        try:
            return float(mx), float(my), "slide_metadata"
        except Exception:
            pass
    return None, None, "unavailable"

mpp_x, mpp_y, mpp_src = _mpp()

os.makedirs("tiles", exist_ok=True)

# ---------------------------------------------------------------- deterministic tissue thumbnail
# Build a bounded thumbnail (deterministic) and an Otsu tissue mask on the
# saturation channel: H&E tissue is saturated, slide background is near-white.
thumb_max = 2000
scale = min(1.0, float(thumb_max) / float(max(W, H)))
tw = max(1, int(round(W * scale)))
th = max(1, int(round(H * scale)))
thumb = slide.get_thumbnail((tw, th)).convert("RGB")
thumb_arr = np.asarray(thumb)
# recompute actual thumb dims (PIL may adjust aspect)
th_act, tw_act = thumb_arr.shape[0], thumb_arr.shape[1]
sx = float(tw_act) / float(W)
sy = float(th_act) / float(H)

hsv = skcolor.rgb2hsv(thumb_arr)
sat = hsv[:, :, 1]
try:
    from skimage.filters import threshold_otsu
    sat_thr = float(threshold_otsu(sat)) if sat.max() > sat.min() else 0.0
except Exception:
    sat_thr = 0.10
tissue_mask_thumb = sat > max(sat_thr, 0.05)

# ---------------------------------------------------------------- deterministic tiling grid
stride = tile_size - tile_overlap
xs = list(range(0, max(1, W - 1), stride))
ys = list(range(0, max(1, H - 1), stride))

grid = []  # raster order -> deterministic
for ty in ys:
    for tx in xs:
        w = min(tile_size, W - tx)
        h = min(tile_size, H - ty)
        if w < 32 or h < 32:
            continue
        # tissue fraction from the thumbnail region covering this tile
        a = int(tx * sx); b = int((tx + w) * sx)
        c = int(ty * sy); d = int((ty + h) * sy)
        b = max(b, a + 1); d = max(d, c + 1)
        region = tissue_mask_thumb[c:d, a:b]
        tissue_frac = float(region.mean()) if region.size else 0.0
        grid.append({"tile_x0": tx, "tile_y0": ty, "w": w, "h": h, "tissue_frac": round(tissue_frac, 4)})

n_grid = len(grid)
tissue_tiles = [g for g in grid if g["tissue_frac"] >= tissue_threshold]
n_background = n_grid - len(tissue_tiles)

# bounded, deterministic selection: raster order, first N tissue tiles
if max_tiles > 0:
    selected = tissue_tiles[:max_tiles]
else:
    selected = tissue_tiles

# ---------------------------------------------------------------- load model (once)
try:
    model = cp_models.Cellpose(gpu=use_gpu, model_type=model_type)
except Exception as e:
    fail("cellpose model init failed for model_type=%s (%r). The pretrained weights "
         "download to ~/.cellpose on first use and require network egress on the "
         "worker. Refusing to continue without the real model." % (model_type, e))

diam = None if cell_diameter <= 0 else cell_diameter

# ---------------------------------------------------------------- per-tile segmentation
cell_rows = []
tile_summ = []
n_blurry = 0
n_processed = 0
total_nuclei = 0
cp_err = None

for idx, g in enumerate(selected):
    tx, ty, w, h = g["tile_x0"], g["tile_y0"], g["w"], g["h"]
    tile_id = "tile_x%d_y%d" % (tx, ty)
    try:
        rgba = slide.read_region((tx, ty), 0, (w, h)).convert("RGB")
    except Exception as e:
        cp_err = "read_region failed at (%d,%d): %r" % (tx, ty, e)
        continue
    rgb = np.asarray(rgba)

    # focus QC: variance of the Laplacian on the grayscale tile
    gray = skcolor.rgb2gray(rgb)
    lap = ndi.laplace(gray.astype(np.float64))
    focus_var = float(lap.var()) * 10000.0  # scale to a human-readable range
    is_blurry = focus_var < blur_threshold
    if is_blurry:
        n_blurry += 1

    # H&E nuclei channel: hematoxylin via color deconvolution, inverted so that
    # nuclei are bright (what the cellpose 'nuclei' model expects).
    hed = skcolor.rgb2hed(rgb)
    h_chan = hed[:, :, 0]
    hmin, hmax = float(h_chan.min()), float(h_chan.max())
    if hmax > hmin:
        h_norm = (h_chan - hmin) / (hmax - hmin)
    else:
        h_norm = np.zeros_like(h_chan)

    try:
        masks, flows, styles, diams = model.eval(
            h_norm, diameter=diam, channels=[0, 0],
            flow_threshold=flow_threshold, cellprob_threshold=cellprob_thr)
    except Exception as e:
        cp_err = "cellpose eval failed on %s (%r)" % (tile_id, e)
        continue

    masks = np.asarray(masks)
    n_obj = int(masks.max())
    n_processed += 1
    total_nuclei += n_obj

    # save per-tile labelled mask (uint16 PNG is lossless for <=65535 labels)
    mask_path = os.path.join("tiles", tile_id + "_mask.png")
    try:
        skio.imsave(mask_path, masks.astype(np.uint16), check_contrast=False)
    except Exception as e:
        cp_err = "mask write failed for %s (%r)" % (tile_id, e)

    # per-nucleus measurements (real regionprops, no synthetic values)
    for rp in skmeasure.regionprops(masks):
        cy, cx = rp.centroid  # (row, col)
        area_px = int(rp.area)
        area_um2 = None
        if mpp_x and mpp_y:
            area_um2 = round(area_px * mpp_x * mpp_y, 4)
        cell_rows.append({
            "nucleus_id": "%s_n%d" % (tile_id, int(rp.label)),
            "tile_id": tile_id,
            "tile_x0": tx, "tile_y0": ty,
            "centroid_x_global": int(round(tx + cx)),
            "centroid_y_global": int(round(ty + cy)),
            "centroid_x_tile": round(float(cx), 2),
            "centroid_y_tile": round(float(cy), 2),
            "area_px": area_px,
            "area_um2": area_um2,
        })

    tile_summ.append({
        "tile_id": tile_id, "tile_x0": tx, "tile_y0": ty, "w": w, "h": h,
        "tissue_frac": g["tissue_frac"], "focus_var": round(focus_var, 2),
        "blurry": bool(is_blurry), "n_nuclei": n_obj,
    })

if n_processed == 0:
    fail("no tissue tiles were successfully segmented (grid=%d, tissue=%d, selected=%d). "
         "Last error: %s. Check tissue_threshold / input slide." %
         (n_grid, len(tissue_tiles), len(selected), str(cp_err)))

# ---------------------------------------------------------------- cell table (CSV)
cols = ["nucleus_id", "tile_id", "tile_x0", "tile_y0", "centroid_x_global",
        "centroid_y_global", "centroid_x_tile", "centroid_y_tile", "area_px", "area_um2"]
with open("cell_table.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    for r in cell_rows:
        w.writerow(r)

# ---------------------------------------------------------------- stitched QC overlay
# Draw the tile grid on the thumbnail: green = processed tissue tile,
# orange = blurry tissue tile, grey = background tile. Deterministic render.
overlay = thumb_arr.copy()
proc_ids = set(t["tile_id"] for t in tile_summ)
blur_ids = set(t["tile_id"] for t in tile_summ if t["blurry"])

def _rect(img, r0, c0, r1, c1, rgb_color):
    r0 = max(0, min(r0, img.shape[0] - 1)); r1 = max(0, min(r1, img.shape[0] - 1))
    c0 = max(0, min(c0, img.shape[1] - 1)); c1 = max(0, min(c1, img.shape[1] - 1))
    if r1 <= r0 or c1 <= c0:
        return
    rr, cc = skdraw.rectangle_perimeter((r0, c0), end=(r1, c1), shape=img.shape)
    img[rr, cc] = rgb_color

for g in grid:
    tx, ty, w, h = g["tile_x0"], g["tile_y0"], g["w"], g["h"]
    tile_id = "tile_x%d_y%d" % (tx, ty)
    c0 = int(tx * sx); c1 = int((tx + w) * sx)
    r0 = int(ty * sy); r1 = int((ty + h) * sy)
    if tile_id in blur_ids:
        col = np.array([255, 140, 0], dtype=overlay.dtype)
    elif tile_id in proc_ids:
        col = np.array([0, 200, 0], dtype=overlay.dtype)
    else:
        col = np.array([160, 160, 160], dtype=overlay.dtype)
    _rect(overlay, r0, c0, r1, c1, col)

try:
    skio.imsave("qc_overlay.png", overlay, check_contrast=False)
except Exception as e:
    fail("failed to write qc_overlay.png (%r)" % e)

# ---------------------------------------------------------------- QC summary JSON
qc = {
    "status": "completed",
    "research_use_only": True,
    "input": {
        "path": os.path.basename(input_wsi),
        "vendor": vendor,
        "level0_width_px": int(W),
        "level0_height_px": int(H),
        "n_levels": int(n_levels),
        "mpp_x_um": mpp_x, "mpp_y_um": mpp_y, "mpp_source": mpp_src,
    },
    "tiling": {
        "tile_size_px": tile_size, "tile_overlap_px": tile_overlap, "stride_px": stride,
        "n_grid_tiles": n_grid,
        "n_tissue_tiles": len(tissue_tiles),
        "n_background_tiles": n_background,
        "tissue_threshold": tissue_threshold,
        "max_tiles": max_tiles,
        "n_selected": len(selected),
        "n_processed": n_processed,
        "deterministic": True,
        "note": "tiles selected in raster order; bounded by max_tiles for a preview run",
    },
    "qc_flags": {
        "n_blurry_tiles": n_blurry,
        "blur_metric": "variance_of_laplacian_x1e4",
        "blur_threshold": blur_threshold,
        "background_detection": "Otsu on HSV saturation of bounded thumbnail",
    },
    "segmentation": {
        "model": "cellpose",
        "model_type": model_type,
        "channel": "hematoxylin (skimage rgb2hed), min-max normalized",
        "diameter": diam,
        "flow_threshold": flow_threshold,
        "cellprob_threshold": cellprob_thr,
        "total_nuclei": total_nuclei,
        "mean_nuclei_per_processed_tile": round(total_nuclei / float(n_processed), 2),
    },
    "warnings": [cp_err] if cp_err else [],
}
with open("qc_summary.json", "w") as f:
    json.dump(qc, f, indent=2)

# ---------------------------------------------------------------- model/version manifest
def _ver(mod, attr="__version__"):
    try:
        import importlib
        m = importlib.import_module(mod)
        return str(getattr(m, attr, "NA"))
    except Exception:
        return "NA"

ol_ver = "NA"
try:
    ol_ver = str(getattr(openslide, "__version__", "NA"))
except Exception:
    pass

manifest = {
    "workflow": "pathology/wsi_he_nuclei_segmentation",
    "research_use_only": True,
    "container_pinned": "quay.io/biocontainers/cellpose:3.1.0",
    "segmentation_model": {
        "framework": "cellpose",
        "model_type": model_type,
        "weights": "cellpose pretrained (downloaded to ~/.cellpose on first use)",
        "license": "Cellpose BSD-3-Clause",
    },
    "versions": {
        "cellpose": _ver("cellpose"),
        "openslide_python": ol_ver,
        "numpy": _ver("numpy"),
        "scipy": _ver("scipy"),
        "scikit_image": _ver("skimage"),
        "torch": _ver("torch"),
    },
}
with open("model_manifest.json", "w") as f:
    json.dump(manifest, f, indent=2)

# ---------------------------------------------------------------- RESEARCH USE ONLY report
L = []
L.append("=" * 72)
L.append("  WSI H&E NUCLEI SEGMENTATION - RESEARCH USE ONLY")
L.append("  *** NOT FOR DIAGNOSTIC USE - PATHOLOGIST REVIEW REQUIRED ***")
L.append("=" * 72)
L.append("  Slide:            %s" % os.path.basename(input_wsi))
L.append("  Scanner vendor:   %s" % vendor)
L.append("  Dimensions (L0):  %d x %d px  (%d pyramid levels)" % (W, H, n_levels))
if mpp_x and mpp_y:
    L.append("  Resolution:       %.4f x %.4f um/px  (%s)" % (mpp_x, mpp_y, mpp_src))
else:
    L.append("  Resolution:       unavailable (mpp not in slide metadata)")
L.append("")
L.append("  Tiling (deterministic, raster order):")
L.append("    Tile size / overlap:   %d / %d px" % (tile_size, tile_overlap))
L.append("    Grid tiles:            %d" % n_grid)
L.append("    Tissue tiles:          %d" % len(tissue_tiles))
L.append("    Background tiles:      %d" % n_background)
L.append("    Selected / processed:  %d / %d  (max_tiles=%d)" % (len(selected), n_processed, max_tiles))
L.append("    Blurry tiles flagged:  %d" % n_blurry)
L.append("")
L.append("  Nuclei segmentation (cellpose model_type=%s):" % model_type)
L.append("    Total nuclei:              %d" % total_nuclei)
L.append("    Mean nuclei / proc. tile:  %.2f" % (total_nuclei / float(n_processed)))
L.append("")
L.append("  Outputs:")
L.append("    tiles/<tile>_mask.png   per-tile labelled nuclei masks (uint16)")
L.append("    qc_overlay.png          tissue/blur/background tile overlay")
L.append("    cell_table.csv          per-nucleus centroids + area")
L.append("    qc_summary.json         QC + tiling + segmentation summary")
L.append("    model_manifest.json     model + container + version provenance")
L.append("")
L.append("  INTENDED USE: research-use-only preprocessing + nuclei detection.")
L.append("  This is NOT a validated diagnostic device. Counts and masks are an")
L.append("  automated estimate and MUST be reviewed by a qualified pathologist.")
L.append("  No clinical decision may be based on this output.")
L.append("=" * 72)
report = NL.join(L)
with open("RESEARCH_USE_ONLY_report.txt", "w") as f:
    f.write(report + NL)
print(report)

# ---------------------------------------------------------------- versions.yml
vy = []
vy.append("wsi_he_nuclei_segmentation:")
vy.append('  cellpose: "%s"' % _ver("cellpose"))
vy.append('  openslide_python: "%s"' % ol_ver)
vy.append('  scikit_image: "%s"' % _ver("skimage"))
vy.append('  numpy: "%s"' % _ver("numpy"))
vy.append('  scipy: "%s"' % _ver("scipy"))
with open("versions.yml", "w") as f:
    f.write(NL.join(vy) + NL)

print("Pipeline completed. nuclei=%d processed_tiles=%d" % (total_nuclei, n_processed))
PYEOF
    """
}

workflow WSI_HE_NUCLEI_SEGMENTATION_WORKFLOW {
    take:
    meta_ch

    main:
    WSI_HE_NUCLEI_SEGMENTATION(meta_ch)

    emit:
    masks    = WSI_HE_NUCLEI_SEGMENTATION.out.masks
    overlay  = WSI_HE_NUCLEI_SEGMENTATION.out.overlay
    cells    = WSI_HE_NUCLEI_SEGMENTATION.out.cells
    qc       = WSI_HE_NUCLEI_SEGMENTATION.out.qc
    manifest = WSI_HE_NUCLEI_SEGMENTATION.out.manifest
    report   = WSI_HE_NUCLEI_SEGMENTATION.out.report
    versions = WSI_HE_NUCLEI_SEGMENTATION.out.versions
}

// Entry workflow for standalone execution
workflow {
    meta = [id: 'wsi_he_run']
    Channel.value(meta) | WSI_HE_NUCLEI_SEGMENTATION_WORKFLOW
}
