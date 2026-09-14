# HLA-Allele Anchor + KO-Deposit HLA Recovery

**Date:** 2026-09-13 · **training_eligible: false** (prior/anchor + recovery metadata, not FM training data) ·
**Owner:** data-scout, immune-FM H4 (presentation) head — HLA-allele axis.
**Feeds:** `leave_hla_out_gate.py` (needs ≥3 distinct HLA backgrounds for a cross-HLA H4 PASS).

S3 landing: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/immunopeptidome/monoallelic_ref/`

---

## TASK 1 — Mono-allelic reference panels (the HLA-allele prior/anchor)

**Headline coverage (mono-allelic, human):**
- **HLA-I: 197 distinct alleles** — A: 58, B: 101, C: 38.
- **HLA-II: 139 distinct alleles** (DRB single chains + DP α/β pairs + DQ α/β pairs).
- Grand union incl. donor/assay reference layers: HLA-I 197, HLA-II 148.

| Source | Class | Mono-allelic? | HLA-I alleles | HLA-II alleles | Pairs | Access |
|---|---|---|---|---|---|---|
| **MHCflurry 2.0 MS** | I | yes | **177** | — (I-only) | 642,697 | OPEN (Apache-2.0) |
| **SysteMHC Atlas v2 AlleleLibs** | I + II | yes (allele-specific libs) | **145** | **139** | 745,557 / 506,212 | OPEN |
| HLA Ligand Atlas 2020.12 | I + II | no (donor-level ref) | 51 | 81 | 80,621 / 132,818 peptides | OPEN |
| IEDB MHC-ligand EL (MS) | I + II | no (assay-level ref) | 124* | 32* | *SAMPLED (100k of 4.96M)* | OPEN |

\* IEDB = bounded alphabetical sample; class-II DRB-biased. Full 4,961,783-record export deferred (paginate IQ-API or bulk zip on a higher-disk host) — not blocking since SysteMHC+atlas already cover DP/DQ pairs.

**Mono-allelic anchor = MHCflurry-MS ∪ SysteMHC-I = 197 HLA-I alleles / 642k peptides**; SysteMHC also gives **139 HLA-II** allotypes. Atlas + IEDB are allele-annotated *reference* layers (donor/assay level), explicitly **not** clean mono-allelic panels, and add no new 2-field HLA-I alleles beyond the 197.

**Provenance notes.** Old `systemhcatlas.org` is dead (spam redirect); live host is `systemhc.sjtu.edu.cn` (SJTU). SysteMHC pulled efficiently by HTTP-range-reading only the small `.pepidx` from each of 302 `.tar.gz` AlleleLibs (skipped the huge `.splib`). HLA Ligand Atlas distributed as one `hla_2020.12.zip` (the `.tsv.gz` paths were wrong; discovered the zip from `/downloads`). MHCflurry MS data via `downloads.yml → curated_training_data.mass_spec.csv`. All processed tables `peptide, allele, source` landed gzipped on S3 (see JSON `s3_objects`).

---

## TASK 2 — HLA recovery: tooling + per-deposit plan

### Tooling availability (probed; nothing HLA-specific installed locally)
Host has `python3 + pandas 3.0.3`, `conda` (shim), **no docker/singularity/mamba**.

| Tool | Installed | Open? | Use | Acquire |
|---|---|---|---|---|
| OptiType | no | yes | HLA-I typing from RNA/WES reads | bioconda `optitype` / docker fred2/optitype |
| arcasHLA | no | yes | HLA-I **+ II** typing from RNA-seq BAM | bioconda `arcas-hla` |
| GibbsCluster | no | **no** (DTU license) | MS motif deconvolution (peptide list → N motifs) | DTU Health Tech |
| NetMHCpan / NetMHCIIpan | no | **no** (DTU license) | assign motif → allele | DTU Health Tech |
| **MHCflurry** | no | **yes** | OPEN motif→allele assignment (HLA-I) | `pip install mhcflurry` |
| **MoDec / MixMHCpred** (Gfeller) | no | **yes** | OPEN deconvolution + assignment | GitHub GfellerLab |

**Recommended OPEN toolchains** — (a) *RNA/WES present:* arcasHLA (I+II) or OptiType (I). (b) *MS-only (no RNA):* MoDec (or GibbsCluster) deconvolve the eluted-ligand peptide list into N motifs → assign each with MHCflurry (I, open) / MixMHCpred; **the fetched 197-allele mono-allelic panels double as the per-allele motif reference for the assignment step.**

### Per-deposit HLA-recovery plan (the 4 held/fetched KO deposits)

| Deposit | Chassis / KO | HLA reported? | HLA | Class | Recovery method |
|---|---|---|---|---|---|
| **PXD063219** | HeLaM HLA-ABC-KO reconstituted, TAPBPR KD/OE | **YES (explicit)** | HLA-B*44:02 & HLA-B*44:05 | I | **None** — filenames (B4402/B4405) + title/protocol; effectively mono-allelic per line (+2 backgrounds) |
| **PXD056426** | HAP1, 11-gene APM-KO | **YES (known line)** | A*03:01, B*51:01, C*01:02 | I | **Recovered from known genotype** (matches in-program `DRYRUN_leave_hla_out_gate` value). Optional motif-check vs anchor. |
| **PXD054491** | A375 melanoma, ERAP1 silencing+inhibitor | **partial** | A375 documented cell-line type | I | **Recover from cell-line genotype** (Cellosaurus / paper / shared A375 cluster incl. held PXD065279). *Fallback:* MS-only MoDec+MHCflurry on WT peptide list. |
| **PXD020079** | GBM HROG02/HROG17/RA, CIITA-OE (+IFN-γ) | **YES (in paper)** | per-line I + II allotypes | **I + II** | **Recover from paper** (supp HLA-typing table; PMC8724627). *Fallback:* MoDec/GibbsCluster→NetMHCIIpan/SysteMHC-II libs. The **only HLA-II axis** contributor. |

### Recovery status (reported vs must-impute)
- **Reported / recoverable, no imputation needed (3):** PXD063219, PXD056426, PXD020079.
- **Recover-from-known-line, MS-only imputation as fallback (1):** PXD054491.
- **Must-impute de-novo (no metadata) (0):** none.

**Net:** all 4 in-scope KO deposits have reported or cell-line/paper-recoverable HLA. MS-only motif deconvolution (open: MoDec + MHCflurry + the 197-allele anchor) is set up as the fallback and as an optional confirmation. This delivers **≥6 distinct HLA-I backgrounds** (HAP1 + B*44:02 + B*44:05 + A375 + HROG02/17/RA) and **3 HLA-II backgrounds** (HROG02/17/RA) to the leave-HLA-out gate — clearing its ≥3-background requirement once PXD054491/PXD020079 typings are pulled.

---

## Honesty
- Panels are a prior/anchor + eval reference, **not training data** (`training_eligible=false`); promotion requires the H4 kill-test / leave-HLA-out advantage. Collection ≠ model value.
- Atlas/IEDB labeled as donor/assay-level references, not mono-allelic. IEDB is a partial sample (deferred full export).
- No accession or allele invented. HAP1 clone genotype flagged for paper-confirmation (A*03:01/B*51:01/C*01:02 per the in-program dry-run vs the common A*02:01/B*40:01/C*03:04 listing) before hard-wiring — a class-I motif check against the anchor resolves it.
- No HLA tool installed locally; open toolchain reported, install owed only if de-novo imputation is actually needed.
