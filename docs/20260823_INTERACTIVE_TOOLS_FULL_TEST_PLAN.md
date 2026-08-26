# Interactive Tools — Full-Set Test Plan (input + output datasets)

**Date:** 2026-08-23
**Scope:** All **32** Galaxy interactive tools registered on dev, tested on **both** launch surfaces:
(A) **INPUT** datasets the user uploaded, and (B) **OUTPUT** datasets produced by a workflow.
**Why:** data visualization/analysis on BioMate is not just Jupyter/RStudio/CellxGene — it's a whole
set of viewers/analysis apps. This plan makes coverage systematic.

**Verified working today:** Jupyter ✅, RStudio ✅, CellxGene ✅ (see
`docs/20260822_RSTUDIO_INTERACTIVE_TOOL_WORKING.md`). The other 29 are **untested** and several are
blocked by two infra gaps below.

---

## 0. Two infra gaps this matrix exposes (fix before full coverage)

1. **Proxy port coverage.** `frontend/server/routes.ts :: targetForToken` probes only
   `["8888/tcp","8787/tcp","80/tcp","5005/tcp"]`. **13 of 32 tools use other ports** (5000, 9001,
   8000, 3838, 5800, 8080, 3333, 8777). They launch but won't route → 503.
   **Fix:** probe the container's *single published port* dynamically instead of a hardcoded list
   (every IT container publishes exactly one entry-point port), or add all ports below.
2. **Root routing for privileged ports + s6 images.** Galaxy's `job_conf` tool-id match is **exact,
   not regex**, and `docker_set_user` defaults to `$UID` unless set to `''`. Any tool that binds a
   **privileged port (<1024, i.e. port 80)** or uses **s6-overlay** must route to
   `docker_interactive_root` (empty `docker_set_user`) by **exact id**. Today only
   `interactive_tool_rstudio` + `interactive_tool_cellxgene` are. **8 more use port 80.**

---

## 1. Tool matrix

Legend — **Root?** = needs `docker_interactive_root` (port 80 privileged, or s6). **Proxy?** = port
already in `targetForToken` probe list (✅) or missing (❌ add / go dynamic).

| Tool (id `interactive_tool_…`) | Port | Root? | Proxy? | Input format(s) | Use case |
|---|---|---|---|---|---|
| `jupyter_notebook` | 8888 | no | ✅ | ipynb + any (data) | general Python analysis ✅ working |
| `rstudio` | 8787 | **yes** (s6) | ✅ | any | R/Bioconductor IDE ✅ working |
| `cellxgene` | 80 | **yes** | ✅ | h5ad | single-cell viz ✅ working |
| `ml_jupyter_notebook` | 8888 | no | ✅ | ipynb + data | ML/GPU notebooks |
| `qiskit_jupyter_notebook` | 8888 | no | ✅ | ipynb + data | quantum notebooks |
| `climate_notebook` | 8888 | no | ✅ | ipynb | climate notebooks |
| `mgnify_notebook` | 8888 | no | ✅ | ipynb | metagenomics notebooks |
| `pangeo_notebook` | 8888 | no | ✅ | ipynb | geoscience notebooks |
| `pyiron` | 8888 | no | ✅ | ipynb | materials-science notebooks |
| `isee` | 8888 | no | ✅ | *(none — loads SCE from history)* | Bioconductor SCE explorer |
| `simtext_app` | 8888 | no | ✅ | tabular×2 | text-mining app |
| `blobtoolkit` | 80 | **yes** | ✅ | tgz/tar | genome-assembly QC |
| `hicbrowser` | 80 | **yes** | ✅ | zip | Hi-C contact maps |
| `higlass` | 80 | **yes** | ✅ | cool/mcool/bigwig/bed… | multiscale genomic matrices |
| `neo4j` | 80 | **yes** | ✅ | zip | graph DB browser |
| `pavian` | 80 | **yes** | ✅ | tabular (kraken report) | metagenomic taxonomy |
| `phinch` | 80 | **yes** | ✅ | biom1 | microbiome viz |
| `vcf_iobio` | 80 | **yes** | ✅ | vcf_bgzip | VCF summary viz |
| `askomics` | 5000 | no | ❌ | tabular/gff/ttl/nt | RDF/knowledge-graph |
| `bam_iobio` | 9001 | no | ❌ | bam | BAM QC viz |
| `ethercalc` | 8000 | no | ❌ | csv/tsv/tabular | collaborative spreadsheet |
| `geoexplorer` | 3838 | no | ❌ | csv/tabular | Shiny geo explorer |
| `metashark` | 3838 | no | ❌ | csv/tabular | EML metadata (Shiny) |
| `radiant` | 3838 | no | ❌ | csv/tabular | Shiny business analytics |
| `wallace` | 3838 | no | ❌ | *(none)* | ecological niche (Shiny) |
| `wilson` | 3838 | no | ❌ | tabular/txt | omics explorer (Shiny) |
| `ilastik` | 5800 | no | ❌ | h5/tiff | image segmentation (GUI) |
| `panoply` | 5800 | no | ❌ | netcdf/h5 | netCDF viewer (GUI) |
| `vrm_editor` | 5800 | no | ❌ | txt/netcdf/h5 | model editor (GUI) |
| `openrefine` | 3333 | no | ❌ | tabular/tsv | data cleaning |
| `paraview` | 8777 | no | ❌ | png/jpg/tiff | 3D scientific viz |
| `guacamole_desktop` | 8080 | no | ❌ | *(none)* | remote desktop |

*(port 5000/9001/8000/3838/5800/8080/3333/8777 are all non-privileged → no root needed for the port,
but a few images may still use s6/root — confirm per tool when tested.)*

---

## 2. The two launch surfaces

Both ultimately call `POST /api/interactive/launch` with `{tool_id, inputs:{dataset_ids:[hda]}}`; the
only difference is where the HDA came from. The launch endpoint maps the dataset to the tool's data
param (currently hard-mapped for CellxGene's `infile`; **generalize this** — see §5).

- **(A) INPUT dataset** — user uploads a file (`POST /api/datasets/upload` → HDA), then launches a
  viewer on it via DatasetActions / the interactive launcher.
- **(B) OUTPUT dataset** — a workflow runs, produces an HDA (via the ensure-hda bridge), then a viewer
  is launched on that output.

Both must be tested because the HDA lifecycle differs (upload path vs. Nextflow output → ensure-hda),
and outputs may carry different datatypes/metadata than uploads.

---

## 3. Test method (per tool, per surface)

Canonical E2E (fixture user `lifeifei163361@163.com`, `dev-public.biomate.ai`):

```
# (A) INPUT
login → token
POST /api/datasets/upload  (file = a valid <format> dataset)         → galaxy_dataset_id (HDA)
POST /api/interactive/launch {tool_id, inputs:{dataset_ids:[HDA]}}   → entry_point_url
poll GET /interactive/<token>/…  until 200/302 (container boot 10–40s)
assert the tool's own UI marker (e.g. <title>, app root div, api/status)

# (B) OUTPUT
run a workflow that emits a <format> output → ensure-hda → HDA
POST /api/interactive/launch {tool_id, inputs:{dataset_ids:[output HDA]}}
same serve/assert checks
```

**Pass criteria (per cell):** launch returns an `entry_point_url`; the URL serves the tool's real UI
(not 404/502/503) on `dev-public.biomate.ai/interactive/<token>/…`; redirects stay on the public host;
for compute tools (Jupyter/RStudio) a live action succeeds (run code / RPC). Record http code + a UI
marker per the working three.

**Per-format input fixtures needed** (create once, reuse): `ipynb`, `h5ad`, `bam`, `vcf_bgzip`,
`biom1`, `cool`/`mcool`+`bigwig`/`bed`, `netcdf`, `h5`, `tiff`, `csv`/`tsv`/`tabular`, `gff/ttl/nt`,
`zip`, `tgz/tar`, `png/jpg`. Prefer tiny synthetic files, **but match the consuming tool's reader
version** (see the CellxGene anndata-0.8.0 lesson — a valid file the tool's bundled library can't parse
still fails; write fixtures with the tool's own libs when possible).

---

## 4. Prioritized order (highest value first)

1. **Already green:** jupyter, rstudio, cellxgene — re-run under both surfaces (A input h5ad/ipynb, B a
   workflow output).
2. **Notebook family (share Jupyter's proven path, port 8888, no root):** ml_/qiskit_/climate_/
   mgnify_/pangeo_/pyiron/isee/simtext — should pass once the notebook path is confirmed generic.
3. **Genomics viewers on port 80 (need root routing — add exact ids):** vcf_iobio, higlass, pavian,
   phinch, blobtoolkit, hicbrowser, neo4j. Highest scientific value; each needs a real input fixture.
4. **Shiny/other-port tools (need proxy port coverage fix):** wilson, radiant, geoexplorer, metashark,
   wallace, ethercalc, openrefine, askomics, bam_iobio, ilastik, panoply, paraview, vrm_editor,
   guacamole_desktop.

---

## 5. Blocking work items (do these to unblock the matrix)

- [ ] **Proxy: probe the container's published port dynamically** (or extend the list to all ports in
  §1). One-line change in `targetForToken`; unblocks 13 tools. *Recommended: dynamic.*
- [ ] **job_conf: route every port-80 / s6 tool to `docker_interactive_root` by exact id** (8 tools in
  §1). Same pattern as rstudio/cellxgene.
- [ ] **Generalize the launch input mapping** — instead of the CellxGene-specific `infile`, resolve
  each tool's data param name from its XML and map `dataset_ids` to it, so any viewer works on any
  HDA. Currently only CellxGene is wired.
- [ ] **Build the per-format fixture set** (§3), tool-reader-version-matched.
- [ ] **CellxGene real-dataset compat** — bundled anndata 0.8.0 can't read modern-scanpy h5ads; bump
  the image or convert on ingest (tracked in the RStudio doc).
- [ ] **Reaper/leak note** — each launch leaks a container until reaped; run the enable reaper between
  large test batches.

---

## 6. Status log

| Date | Tool | Surface | Result |
|---|---|---|---|
| 2026-08-19 | jupyter | (A) fresh launch | ✅ 200 + kernel WS exec |
| 2026-08-22 | rstudio | (A) fresh launch | ✅ IDE (302→GWT, client_init 200) |
| 2026-08-23 | cellxgene | (A) uploaded h5ad | ✅ 200 CELL×GENE UI (0.8.0-compat h5ad) |
| 2026-08-23 | jupyter/rstudio | (A) re-verified post-generalization | ✅ no regression |
| 2026-08-23 | wallace (3838) | (A) no-input | 🟡 proxy **reached** it on port 3838 (502 → port-agnostic proven); container job errored (shiny startup nuance) |

## Update 2026-08-23 — generalization shipped; all 32 enabled

The per-tool complications are gone (the "use the standard path" direction):
- **Proxy is port-agnostic** — `targetForToken` now takes the container's single published port, not a
  hardcoded list. Proven: it routed Wallace on **3838** (would have 503'd before). Covers all ports.
- **One routing rule** — `job_conf` `interactive_tool_.* → docker_interactive_root` (empty
  `docker_set_user`); every image runs as its own default user. Verified after a **full** galaxyctl
  restart (regex matches — the earlier "exact only" was a HUP-reload artifact). Jupyter/RStudio
  re-verified, no regression.
- **All 32 tools enabled** in `interactivetools_conf.xml` (were 3) and loaded (32 distinct in the tool
  panel). Each pulls its biocontainer on first launch.

**What's left is genuinely per-tool** (the routing/port/user are solved for all): each tool's own
container/command/entry-path/image may need a small fix, exactly as RStudio (root+`exec /init`) and
CellxGene (anndata compat) did. Wallace is the first of these (shiny container errors on start). Work
the matrix in the §4 priority order; the framework now supports any tool without per-tool wiring.
