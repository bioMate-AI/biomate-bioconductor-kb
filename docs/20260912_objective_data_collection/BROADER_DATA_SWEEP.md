# Broader Data Sweep — under-searched repos + blocked-data recovery across ALL objectives

**Date:** 2026-09-14 · **Role:** SEARCH/metadata only · **training_eligible = false**
**Companion:** `BROADER_DATA_SWEEP.json` (per-accession detail, DAC routes, tallies)

Checks whether the immune-FM program under-searched public data across **all** objectives (not just H4). Cross-referenced against `DATASET_MASTER_REGISTRY.md` and the 20260912 prior work (W1/W2/H2/H4) so nothing already held/counted is re-reported. Only small metadata pulled (df-checked: 4.1 GB free) via PROXI/ProteomeXchange, GEO, ENA, GDC/PDC, EGA/dbGaP/GSA-Human policy pages.

---

## TL;DR — how much MORE usable data exists, ranked by value-per-effort

| Rank | Target | What's newly fetchable | Effort | Access |
|---|---|---|---|---|
| **1** | **H3 pairs** | **~2,300+ OPEN same-sample RNA+protein pairs** (closes the ~0-held gap outright) | **Lowest** (`pip install cptac`) | OPEN |
| **2** | **Under-searched repos** | **≥212 NEW human-immune proteomics deposits** (128 from 2024+), ~7× the ~28 held | Low–Med (HTTPS via PRIDE mirror) | OPEN |
| **3** | **Vaccine (T3)** | **~201 subjects** cleanly recoverable + 44 via ArrayExpress → W2 923 → ~1,120–1,165 | Med (quant pipeline) | OPEN |
| **4** | **Controlled cohorts (T4)** | ~2,600 donors genotype+scRNA(+ATAC/multiome)+SLE labels | High (DAC, weeks–months) | CONTROLLED |

**Single fastest win:** the **`cptac` Python package** — one `pip install` gives ~1,000+ pre-aligned same-tumor RNA+protein pairs across 10 cancer cohorts, fully OPEN, closing the H3 modality gap the program currently scores at ~0 held.

---

## Target 1 — Under-searched proteomics repos (iProX / jPOST / MassIVE / Zenodo / full PROXI)

**≥212 NEW human-immune deposits** (not in the ~28 held) surfaced from the federated ProteomeXchange/PROXI index alone — **128 from 2024+**. By repo: PRIDE 178, **MassIVE 27, iProX 3, jPOST 3**, PanoramaPublic 1.

**Key caveat:** the *federated* index is PRIDE-dominated because most native **iProX (IPX)** and **jPOST (JPST)** immunopeptidome deposits do **not** cross-register to ProteomeXchange. iProX native search was **HTTP 403 / keyword-filter-broken / timeout-blocked** from this host (its PROXI ignores the keyword filter and `resultType=full` times out) — so the true iProX/jPOST pool is **larger than the 3+3 shown** and is **the single largest untapped repo target**. Re-sweep from an unblocked host with a paginated `resultType=compact` client. **Zenodo** additionally yielded **36 relevant records / ~10 genuinely-new processed-peptide datasets** not visible in any MS repository — notably **`10.5281/zenodo.18611575` (epiVIP: PAIRED immunopeptidome + transcriptome)** and **`10.5281/zenodo.22284845` (Atlas9921 HLA-I motif tables)**.

**Highest-value NEW non-PRIDE accessions (all ProteomeXchange-federated → HTTPS-pullable via PRIDE mirror even where native repo is FTP-only):**

- **PXD052175** (MassIVE, 2024) — *Targeting ERAP enhances anti-tumor immunity by disrupting the immunopeptidome* → directly extends the held ERAP1/2-KO machinery axis.
- **PXD025501** (MassIVE, 2022) — *Systematic modulation of HLA class I downregulation* → machinery-state presentation.
- **PXD059832** / **PXD057858** (MassIVE, 2025) — cryptic cancer antigens / HIF-regulated translated ERVs → non-canonical + translation→presentation (spans H2/H4).
- **PXD045855** (MassIVE, 2023) — *Integrated immunopeptidomic + proteomic COVID-19* → same-sample **P+L** (proteome+immunopeptidome), infection context.
- **PXD077293** (iProX, 2026) — MiREC low-input HLA-I immunopeptidomics; **PXD047311** (iProX, 2023) — proteogenomic neoantigens + bacterial peptides.
- **PXD024248** (jPOST, 2022) — HLA-I ligandome of **HCT15/b2m** (B2M-context, complements held B2M-KO); **PXD040385** (jPOST, 2024) — Thunder-DDA-PASEF deep immunopeptidomics.
- **PXD044851** (MassIVE, 2023) — MAPPs HLA-II drug-immunogenicity (adalimumab/ATR-107); **PXD066040** (2025) — HLA-C*06:02 psoriasis transgenic (autoimmune, on-mission).
- Plus HLA-II/method sets: PXD033106, PXD040740, PXD014293; infection: PXD037779, PXD042231; quant DIA: PXD053374; plasma-HLA: PXD044215; single-allele K562: PXD022951; PRM HPV16: PXD074373. (Full ~37-accession list in JSON.)

**Bottom line:** ~7× expansion of the addressable immunopeptidome corpus beyond the ~28 held (~30 of the new deposits are the non-PRIDE ones actually under-searched), with a ready machinery/drug-perturbed cluster, plus ~10 new Zenodo processed-peptide datasets (incl. a paired immunopeptidome+transcriptome set). **iProX/jPOST native remains under-swept (host-blocked)** — re-run there for the biggest incremental gain.

---

## Target 2 — H3 transcriptome+proteome pairs (the biggest quick win)

H3 needs same-sample RNA+protein; it holds **~0 same-flask**. **~2,300+ OPEN pairs are fetchable now, no DAC:**

| Source | OPEN pairs | Fastest route |
|---|---|---|
| **CPTAC** (10 tumor cohorts) | **~1,000–1,100** same-tumor | **`pip install cptac`** — RNA + protein matrices keyed to the SAME sample IDs, pre-aligned. Cohorts: BRCA, CCRCC, COAD, GBM, HNSCC, LSCC, LUAD, OV, PDAC, UCEC. |
| **ProCan-DepMapSanger** | **~900+** cell lines | Proteome PXD030304 / GitHub matrix + Cell Model Passports; RNA via DepMap join. |
| **Gygi/CCLE** (Nusinow 2020) | **~375** cell lines | Proteome at gygi.med.harvard.edu / depmap.org + DepMap `CCLE_expression`. |

Raw routes (if needed): proteome via **PDC** GraphQL (`pdc.cancer.gov/graphql`, 109 OPEN proteome studies); matched RNA via **GDC** (`api.gdc.cancer.gov`, **CPTAC-3 = 1,866 cases; STAR-Counts RNA-seq OPEN** — self-verified 11,436 transcriptome files, ~2,968 open STAR-count files). Cell-line pairs de-dup to ~1,000–1,200 unique lines (+~1,000 CPTAC tumors).

**Bottom line:** start with the **`cptac` package** — closes H3's ~0-held gap outright with ~1,000+ pre-aligned pairs, zero dbGaP/DUA gating. Highest value-per-effort item across all four targets.

---

## Target 3 — Blocked vaccine transcriptomes (recover W2's 923/2,125)

W2 failed 1,158 subjects across 13 studies. Per-study verification (GEO type/relation + **ENA run counts verified**):

**Cleanly recoverable (~201 subj):**
- **SDY2770 / GSE199750** (80, COVID vaccine bulk RNA-seq) — ENA **PRJNA821445 = 260 RNA-Seq runs** (verified); or per-GSM featureCounts in `GSE199750_RAW.tar`. **HIGH.**
- **SDY1393 / GSE178158** (61, flu, platelet RNA-seq) — ready-made `ddsHTSeq...Rds` count object in GEO suppl (fastest); or ENA **SRP216466 = 246 paired FASTQ runs** (verified). **HIGH, best value-per-effort.**
- **SDY400 / GSE95584** (31) — **microarray**, `non-normalized.txt.gz` in suppl; same scale as the 923 already assembled, just **skipped in W2, not blocked**. **TRIVIAL.**
- **SDY212 / GSE41080** (14) — **microarray** (not RNA-seq as W2 assumed), per-sample in `_RAW.tar`.
- **SDY224 / GSE45764** (5) — RNA-seq, ENA PRJNA196230 = 110 runs (verified). **SDY675** (10) — SRP raw-only.

**Recoverable but needs new fetcher:** **SDY1439** (44) — ArrayExpress **E-MTAB** (GEO-only W2 pipeline missed it).
**Recoverable but modality-mismatch:** **SDY2189 / GSE171964** (32) — **scRNA-seq** (BNT162b2), needs pseudobulk.

**BLOCKED — genuinely not public (776 subj):**
- **SDY1538** (686, **32% of target**) — EPIC-002 Gambia/PNG newborn HBV (EPICHIPC). GSE254348/GSE272438 **do not resolve** (private/embargoed); GSE272800 is an **EPIC methylation array, not RNA**. Data released "through ImmPort SDY1538/SDY2584" but the **RNA-seq transcriptome is not on GEO or SRA**. Only recoverable via ImmPort restricted download or an EPIC/HIPC consortium request.
- **SDY2584** (90) — same EPICHIPC program, same blocker.

**No accession (manual triage):** SDY622 (54, blank), SDY301 (38), SDY296 (13).

**Pipeline scale (route only — do NOT run):** nf-core/rnaseq quant of ~600–700 FASTQ runs (SDY2770+SDY1393+SDY224+SDY675) → per-subject baseline collapse → align to microarray scale; SDY1393 (and partly SDY2770) have pre-computed count objects. The 2 microarray adds need only the existing gene-collapse pipeline.

**Bottom line:** realistic recovery raises W2 from **923 → ~1,120–1,165** (43% → **~54%**). SDY2770 + SDY1393 are the big open wins; SDY400+SDY212 are trivial microarray adds. The **686-subject SDY1538 is a real hard ceiling** — its transcriptome is not in any public raw-read repo.

---

## Target 4 — Controlled-access multimodal cohorts (DAC routes)

| Cohort | Accession / repo | Modalities | N | Adds | DAC route (summary) |
|---|---|---|---|---|---|
| **TenK10K** ★1 | EGAS50000001653 (+…1654 WGS) / EGA | WGS 30x · scRNA (>5M cells) · scATAC (952) · multiome (~95) | 1,925 | Genotype eQTL prior + paired scRNA/scATAC/multiome, same donors — fills 4 slots | EGA account → DAR + email DAC (Powell/Garvan) → sign TenK10K DAA → institutional SO signs → Garvan DAC (EGAC50000000931) |
| **Perez SLE** ★2 | phs002812.v2.p1 / dbGaP | mux-seq scRNA (>1.2M PBMC) · genotype array | 258 | Cell-type cis-eQTL + **SLE disease labels** (160 case/98 ctrl) | eRA Commons PI → dbGaP DAR → RUS matching DUL → SO co-sign → DUC → IRB if DS- → NIAMS DAC, ~2–8 wk |
| **EGA SLE** ★3 | EGAS00001003662 / EGA | bulk RNA-seq (200) · genotype array · **prebuilt eQTL/sQTL** | 200 | SLE genetics prior + labels; bulk only | EGA account → Request Access + email (gbertsias@uoc.gr) → sign FORTH-BRFAA DAA → SO → DAC EGAC00001001213 |
| **CIMA** ★4 | HRA009968 / GSA-Human | scRNA · scATAC · WGS | 428 | **East-Asian-ancestry** paired scRNA+scATAC+WGS (eQTL+caQTL) | BIG SSO (PI + homepage) → DAR → sign DAA → CIMA DAC (HDAC005178). **Non-China friction: needs MOST-HGR registration + likely Chinese collaborating PI + HGRAC approval** |

**Value-per-effort:** TenK10K > Perez SLE > EGA SLE > CIMA. Start **TenK10K (highest payload)** and **Perez SLE (lowest-friction US portal)** DARs in parallel now; EGA SLE is a cheap add-on; CIMA is a long-lead partnership track. **Cross-cutting gap:** none of the four supply protein (CyTOF/Olink) or dedicated TCR-seq — separate cohort search needed for those.

---

## Blocked data confirmed unrecoverable publicly (this run)

- **SDY1538 / SDY2584** vaccine RNA-seq (776 subj, EPICHIPC) — ImmPort-restricted / consortium request only.
- **MSV000091285** (H4 immunoproteasome ONX-0914) — MassIVE FTP-only; needs an FTP-capable host (same transport blocker that limited many MassIVE files here).
- **iProX / jPOST native** — 403/timeout from this host; not a data-availability block, a host-egress block → re-sweep elsewhere.
