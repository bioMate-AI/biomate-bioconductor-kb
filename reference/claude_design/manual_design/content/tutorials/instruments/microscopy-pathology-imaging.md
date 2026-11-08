# Instrument tutorial — microscopy & pathology imaging → cell segmentation, marker quantification, and whole-slide analysis

> **Who this is for:** anyone running a **digital slide scanner** (数字化切片扫描仪, whole-slide imaging /
> pathology), a **confocal microscope** (共聚焦显微镜), or a **fluorescence microscope** (荧光显微镜) who wants
> the images turned into **"where are the cells/nuclei, how many are there, and how much of each marker do they
> express"** — no coding needed.
> **Time:** ~14 minutes to read.
> **Where it fits:** Tutorial 6 (T6) explains how to *connect* an instrument or otherwise get its files into
> BioMate. This tutorial explains **the analyses those images drive, how to run them, and how to read them** —
> and, candidly, **which image formats work today and which are still on the roadmap.**

> **Read §6 before you commit to a run.** For imaging, the single most important thing to know up front is the
> **file format you hold**. Several common vendor microscope and scanner formats cannot yet be read inside
> BioMate; feeding one of them in produces an error or an empty result, not a finding. §6 states exactly what
> is runnable today versus on the roadmap.

---

## 1. What these instruments produce

All three instruments produce pixel images, but of different kinds, at different scales:

- **Fluorescence microscope** — typically **2-D images**, one or a few channels (e.g. DAPI nucleus + one or two
  marker channels). Commonly exported as **TIFF**, **PNG**, or **JPEG**. This is the simplest imaging case.
- **Confocal microscope** — optical-section **z-stacks** (and often multi-channel, multi-timepoint) saved in
  **vendor formats**: Zeiss `.czi`, Leica `.lif`, Nikon `.nd2`, Olympus `.oir`. A single file can hold a whole
  3-D volume across several channels.
- **Digital slide scanner (WSI)** — **whole-slide images**: gigapixel pyramidal images of an entire histology
  slide, saved as Aperio `.svs`, Hamamatsu `.ndpi`, 3DHISTECH `.mrxs`, or the Chinese-scanner formats `.kfb`
  (KFBIO) and `.sdpc` (SQRAY). These are enormous (often multi-gigabyte) and are read tile-by-tile, not all at
  once.

**A picture is not a measurement.** Turning an image into "there are 4,200 nuclei in this field; marker X is
expressed in 38 % of them" requires **segmentation** (drawing the boundary of every cell or nucleus) followed
by **quantification** (measuring size, shape, and per-channel intensity inside each boundary). That
segment-then-quantify pipeline is what BioMate runs — and which pipeline, and whether it can even open your
file, depends on *what instrument produced it and in what format*.

---

## 2. The BioMate analysis these images drive (and why)

### 2a. Cell / nuclei segmentation (fluorescence and confocal single fields)

> **Workflow:** `segment_cells_with_deep_learning`
> **Path:** `backend/biomni_workflows/nextflow/workflows/microbiology/segment_cells_with_deep_learning.nf`
> **Key input:** `image_path` (the image to segment).

This is the core microscopy workflow. It performs **deep-learning cell segmentation on fluorescence microscopy
images using pre-trained models from the Cellpose / Omnipose family** (per the workflow's own description),
with scikit-image for boundary finding, I/O, and per-object statistics. The pipeline reads the image, finds
object boundaries, labels each cell/nucleus, and summarises the result (object count and intensity statistics).
The output is a **labelled mask** plus a summary — the raw material for counting cells and measuring marker
intensity.

A closely related workflow, **`segment_and_analyze_microbial_cells`**
(`…/nextflow/workflows/microbiology/segment_and_analyze_microbial_cells.nf`), performs the same segmentation and
additionally **quantifies morphological metrics** (per-object size and shape) — use it when you want cell
*morphology*, not just counts.

*When to pick which:* a single 2-D fluorescence field → `segment_cells_with_deep_learning` for counts/masks, or
`segment_and_analyze_microbial_cells` if you also need morphology. A confocal **z-stack** is a 3-D volume: see
§6 — its vendor formats are not yet readable, and you would first need a 2-D projection or OME-TIFF export.

### 2b. Multiplexed tissue — segment and quantify many markers at once

> **Workflow:** `segment_and_quantify_cells_in_multiplexed_images`
> **Path:** `backend/biomni_workflows/nextflow/workflows/pathology/segment_and_quantify_cells_in_multiplexed_images.nf`
> **Key inputs:** `image_path`, `markers_list`.

For **multichannel tissue images** (e.g. multiplex immunofluorescence / CyCIF-style panels), this workflow
segments cells and then **quantifies protein-expression levels per marker** across the panel — reading the
image, labelling cells (watershed + region properties), and measuring each marker channel inside each cell. Use
it when your question is *single-cell marker expression in tissue*, not just a nucleus count. Provide the list
of marker/channel names in `markers_list`.

### 2c. Whole-slide imaging (digital slide scanner)

For a gigapixel WSI the registered pipeline is **`nf-core/mcmicro`** — the nf-core multiplexed-tissue-imaging
pipeline (illumination correction → stitching/registration → segmentation → single-cell marker quantification).
*mcmicro is an nf-core pipeline and is **not** stubbed locally in this repository* (confirmed: no `*mcmicro*`
file under `backend/biomni_workflows`); its behaviour is defined by the published nf-core/mcmicro documentation.
**Critically, mcmicro expects an OME-TIFF input**, not a raw vendor WSI — see §6.

An emerging, in-repository alternative is **`wsi_he_nuclei_segmentation`**
(`backend/biomni_workflows/nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/`), a
research-use-only H&E preprocessing + nuclei-segmentation subworkflow that reads one slide via **OpenSlide**
(Aperio `.svs` and pyramidal OME-TIFF), tiles the tissue with background/blur QC, and runs a license-clean
**Cellpose** (BSD-3-Clause) nuclei model, emitting per-nucleus tables and QC overlays. It is **not yet
DB-registered** (so it does not route from chat today) and is **research-use-only — pathologist review
required**. It is listed here honestly as a roadmap capability, not as a one-click product path (see §6).

| What you have | Workflow BioMate offers | Today? |
|---|---|---|
| Single 2-D fluorescence field, counts/masks | **`segment_cells_with_deep_learning`** (Cellpose/Omnipose) | ✅ for TIFF/PNG/JPEG |
| Single 2-D field, also morphology | `segment_and_analyze_microbial_cells` | ✅ for TIFF/PNG/JPEG |
| Multichannel tissue, per-marker expression | `segment_and_quantify_cells_in_multiplexed_images` | ✅ for OME-TIFF / multichannel TIFF |
| Whole-slide image, multiplex single-cell | **`nf-core/mcmicro`** (nf-core docs) | ⚠️ **only via OME-TIFF** (vendor WSI blocked — §6) |
| H&E slide, nuclei segmentation | `wsi_he_nuclei_segmentation` (OpenSlide + Cellpose, RUO) | 🛑 not yet routable (roadmap) |
| Confocal z-stack (`.czi/.lif/.nd2/.oir`) | would feed the segmentation workflows above | 🛑 **no reader yet — roadmap (B1)** |

---

## 3. Before you start — getting the images in (see T6)

Connecting an instrument so its files reach BioMate is **Tutorial 6**; this tutorial assumes the images are
already in your BioMate data area (upload a single file by hand is **Tutorial 4**). Once your files are in
BioMate, come back here to run the analysis.

**What you must have ready:**

- **The image in a readable format.** This is the gating requirement for imaging — see §6. In practice that
  means **2-D TIFF / PNG / JPEG** for microscopy, or **(pyramidal) OME-TIFF** for multiplex tissue and
  whole-slide work. If you only hold a vendor format (`.czi`, `.lif`, `.nd2`, `.oir`, `.svs`, `.ndpi`, `.mrxs`,
  `.kfb`, `.sdpc`), convert it first (§6) or the run will not proceed.
- **For multiplexed tissue:** the **list of marker/channel names** (`markers_list`), in channel order.
- **A note of the image scale** (microns per pixel) if you intend to report object sizes in physical units.

---

## 4. Step by step — run it

1. **Confirm your format first (§6).** If your file is a vendor microscope/scanner format, convert it to
   TIFF or OME-TIFF before anything else. This one check saves the most wasted runs.
2. **Start from chat (or a pre-filled draft).** Type your goal in plain language, e.g. *"Segment nuclei in this
   fluorescence TIFF and count cells"*, or *"Segment and quantify markers CD3, CD8, PanCK in this multiplex
   OME-TIFF."* BioMate opens the matching workflow card (§2) in the right-hand panel; nothing runs yet.
3. **Check the workflow name.** Confirm the panel opened the right pipeline — `segment_cells_with_deep_learning`
   for single-field segmentation, `segment_and_quantify_cells_in_multiplexed_images` for multiplex tissue,
   `nf-core/mcmicro` for a whole slide. It must show a real name, not "undefined"; if it is the wrong one,
   restate your goal.
4. **Fill the key inputs.** Attach your image as `image_path`; for multiplex tissue also fill `markers_list`
   with your channel names.
5. **Confirm and run.** Click **Confirm & Run** and watch the phases move *pending → running → completed* in the
   Phases tab. Single-field segmentation is quick; a whole-slide mcmicro run is heavy compute and can take a
   long time.

---

## 5. Reading the outputs

Open the **After run** section (two tabs — see **Tutorial 3**):

- **Segmentation mask / labelled image** — every detected cell or nucleus drawn as a distinct labelled object.
  This is the primary output; overlay it on the original image to sanity-check that boundaries track real cells
  (not debris, not merged clumps).
- **Object / cell table** — one row per segmented object with its position, area, and (for the quantification
  and multiplex workflows) **per-marker intensity**. This is what you count and compare: e.g. "N nuclei; marker
  CD8 positive in X %".
- **QC summary** — object counts and intensity statistics; for the WSI nuclei subworkflow, also a tiling /
  background / blur overlay so you can see which tiles were usable.
- **Reproducibility record** — the model used, parameters, container/versions, and outputs — the audit trail.

> **What good looks like, and what to watch.** Overlay the mask on the raw image: boundaries should follow
> individual cells. Common failure modes are **under-segmentation** (several touching cells merged into one
> object) and **over-segmentation** (one cell split into many) — both distort every downstream count. Very few
> objects usually means a contrast/channel problem or the wrong model. Treat marker-positivity percentages as
> dependent on the intensity threshold used; state it when you report.

---

## 6. Honest limits — format readiness (read this carefully)

This is the section that matters most for imaging. **BioMate's imaging ingestion is format-gated, and several
common vendor formats are not yet supported.** This mirrors the facility resource inventory's **B1** gap.

**Runnable today (works end-to-end):**
- **2-D fluorescence microscopy** as **TIFF / PNG / JPEG** → `segment_cells_with_deep_learning` /
  `segment_and_analyze_microbial_cells`. This is the solid, usable path for the fluorescence microscope.
- **Multichannel tissue** as **OME-TIFF** (or multichannel TIFF) → `segment_and_quantify_cells_in_multiplexed_images`.
- **Whole-slide / multiplex** *only if your slide is already an **OME-TIFF*** → `nf-core/mcmicro`.

**On the roadmap / not yet runnable — do not assume these open today:**
- 🛑 **Vendor whole-slide formats** — Aperio `.svs`, Hamamatsu `.ndpi`, 3DHISTECH `.mrxs`, and the Chinese-scanner
  formats **`.kfb` (KFBIO)** and **`.sdpc` (SQRAY)** — **have no production reader in BioMate (gap B1).** A raw
  `.svs`/`.kfb`/`.sdpc` does **not** run end-to-end today. mcmicro needs an **OME-TIFF**; converting a vendor WSI
  to OME-TIFF (e.g. via bioformats2raw/raw2ometiff or QuPath export) is a manual pre-step outside BioMate. A new
  in-repo subworkflow (`wsi_he_nuclei_segmentation`) bundles OpenSlide and can in principle open `.svs` and
  OME-TIFF, but it is **not DB-registered (does not route from chat), not validated end-to-end, and is
  research-use-only** — treat it as roadmap, not a product path.
- 🛑 **Confocal vendor formats** — Zeiss **`.czi`**, Leica **`.lif`**, Nikon **`.nd2`**, Olympus **`.oir`** —
  **have no reader in BioMate (gap B1).** A confocal z-stack in any of these cannot be ingested directly today.
  To analyse confocal data now, export a **2-D projection or per-channel TIFF/OME-TIFF** from the acquisition
  software first; then the segmentation workflows apply.
- 🛑 **Pathology foundation models (B2) and QuPath integration (B4)** — tile/slide encoders (UNI, CONCH,
  Virchow2, Prov-GigaPath) and QuPath-based whole-slide analysis are **not present**; BioMate's foundation-model
  surface today is transcriptomic. Slide-level embedding, tumour-content QC, and IHC/antigen scoring are
  roadmap, not available.

**Status of the segmentation workflows themselves:** the microscopy and pathology segmentation workflows named
here are **real, indexed workflows** (🟡 **registered**), but their end-to-end runnability on *your* data type is
**unverified on the development site** — there is no recorded real end-to-end imaging run. Treat results as
**experimental** until checked against a known image or your prior analysis; do not report an imaging number from
BioMate as validated.

**Scientific caveats, independent of format:**
- Segmentation quality depends on the model and image quality; always overlay-check the mask (§5).
- Marker-positivity percentages depend on the intensity threshold — report the threshold.
- The WSI nuclei subworkflow is explicitly **research-use-only, not a diagnostic device; pathologist review is
  required**.

---

## 7. BioMate also offers (breadth)

Beyond the three instruments above, BioMate carries a broader imaging and spatial toolbox the facility can use:

| You want to… | Workflow / tool |
|---|---|
| Quantify morphology (size/shape) per cell | `segment_and_analyze_microbial_cells` |
| Per-marker single-cell expression in tissue | `segment_and_quantify_cells_in_multiplexed_images` |
| Analyse calcium-imaging time series | `analyze_calcium_imaging_data` (`…/nextflow/workflows/bioengineering/`) |
| Segment volumetric / medical images with a U-Net | `segment_with_nn_unet` (nnU-Net; `…/subworkflows/bioimaging/`) |
| Register / align images, measure similarity | `register_images`, `calculate_similarity_metrics`, `create_segmentation_visualization` (`…/subworkflows/bioimaging/`) |
| H&E whole-slide nuclei segmentation (RUO, roadmap) | `wsi_he_nuclei_segmentation` (OpenSlide + Cellpose) |
| Downstream of segmentation: spatial / single-cell analysis | BioMate's single-cell and spatial-omics workflows (Scanpy/Seurat family) take a cell × marker table as input |

The underlying toolkits are license-clean and standard: **Cellpose / Omnipose** (deep-learning segmentation),
**scikit-image** (image processing and region measurement), **OpenSlide** (vendor-neutral WSI reader), and
**nnU-Net** (volumetric segmentation).

---

## 8. Where to go next

| You want to… | Where |
|---|---|
| Get an instrument's files into BioMate | **Tutorial 6** |
| Upload a single image by hand | **Tutorial 4** |
| Understand the two-tab report | **Tutorial 3** |
| Quantify markers across a multiplex panel | ask for **`segment_and_quantify_cells_in_multiplexed_images`** |
| Analyse a whole slide (OME-TIFF only, today) | ask for **`nf-core/mcmicro`** |

The habit: **check your format first (convert vendor formats to TIFF/OME-TIFF) → ask BioMate to segment /
quantify → confirm the workflow name and attach the image (+ marker list) → run → overlay-check the mask and
read the cell table, treating results as experimental.**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **Segmentation** | Drawing the boundary of every cell or nucleus. Everything downstream (counts, marker intensity) depends on it being correct. |
| **Cellpose / Omnipose** | Deep-learning generalist segmentation models BioMate uses — no hand-tuned thresholds needed. |
| **OME-TIFF** | A vendor-neutral, pyramidal image format. The format multiplex/whole-slide pipelines actually read — convert vendor files to this. |
| **Whole-slide image (WSI)** | A gigapixel scan of an entire slide (`.svs/.ndpi/.mrxs/.kfb/.sdpc`). Read tile-by-tile; vendor formats need conversion first. |
| **z-stack** | A confocal 3-D volume (optical sections). Vendor `.czi/.lif/.nd2/.oir` are not yet readable — export a projection/TIFF first. |
| **Marker / channel** | One fluorescence channel = one stained protein. `markers_list` tells the quantification workflow what each channel is. |
| **Multiplex imaging** | Many markers imaged on one tissue section; `segment_and_quantify_cells_in_multiplexed_images` / mcmicro measure all of them per cell. |
| **Research-use-only (RUO)** | Not a diagnostic device; findings require expert (pathologist) review before any clinical interpretation. |

---

_Grounded in the real workflow files `backend/biomni_workflows/nextflow/workflows/microbiology/segment_cells_with_deep_learning.nf`
(params/steps/outputs), `…/microbiology/segment_and_analyze_microbial_cells.nf`,
`…/pathology/segment_and_quantify_cells_in_multiplexed_images.nf` (`image_path`, `markers_list`), and the in-repo
`…/nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/` (OpenSlide + Cellpose, RUO, not yet
DB-registered); `nf-core/mcmicro` is an nf-core pipeline not stubbed in this repo (grounded in nf-core docs).
Status and the B1/B2/B4 ingestion/foundation-model gaps mirror `docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md`
(§1 rows for digital slide scanner / confocal / fluorescence; §4 the B1 reader gap). No instrument connector,
driver, or auto-routing is documented or implied — connection is deferred to Tutorial 6. Companion: Tutorials 3, 4, 6._
