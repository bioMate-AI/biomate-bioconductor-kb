# VCC-2026 Perturb-seq Data Sources Log

Running log of single-cell CRISPRi/CRISPR-KO Perturb-seq datasets found for the Arc Virtual Cell Challenge 2026.
**Goal:** Cover as many VCC-300 target genes as possible via a multi-source mean of per-gene knockdown deltas.

## Already Acquired / In-Pipeline (DO NOT RE-REPORT)

| Dataset | Cell line | Notes |
|---|---|---|
| Replogle K562-gwps | K562 (CML) | Replogle et al. 2022, genome-wide CRISPRi |
| X-Atlas/Orion HCT116 | HCT116 | Xaira 2025, genome-wide CRISPRi |
| X-Atlas/Orion HEK293T | HEK293T | Xaira 2025, genome-wide CRISPRi |
| CZI CD4+ T-cell | Primary CD4+ T cells | CZI genome-wide CRISPRi |
| KOLF2.1J iPSC | KOLF2.1J iPSC | Nature Biotech 2026; Figshare doi:10.25452/figshare.plus.27261219.v1 |
| Sanger multi-donor hiPSC | 34 iPSC lines | Feng et al. Cell Genomics Feb 2026; being acquired |

---

## Run 2026-10-15 — Datasets Found This Run

### NEW CANDIDATE 1 — X-Atlas/Pisces (Xaira Therapeutics, March 2026) ⭐ READY TO EXTRACT

| Field | Value |
|---|---|
| Name | X-Atlas/Pisces |
| Cell lines / contexts | 16 contexts: HCT116, HEK293T, HepG2 (liver), Jurkat (T-lymphoma, resting + activated), iPSC (multiple differentiation states), multi-lineage differentiating iPSCs |
| New vs. existing | **HepG2 and Jurkat are NEW** (HCT116 and HEK293T already in Orion) |
| Perturbation type | Genome-wide CRISPRi (GuEST-List / custom libraries) |
| Genes perturbed | ~18,924 in HCT116; ~18,312 in HEK293T; ~9,735 in HepG2; ~10,095 in iPSC (screen breakdown from X-Cell project page) |
| Number of cells | 25.6 million total across all contexts |
| Est. VCC-300 coverage | ~300/300 (genome-wide) |
| Download route | HuggingFace: `Xaira-Therapeutics/X-Atlas-Pisces` |
| Format | Likely h5ad (same platform as Orion; UNVERIFIED — HuggingFace page not directly fetchable) |
| Approximate size | Very large; Orion alone was 520 GB; Pisces likely multi-TB |
| License | Non-commercial (confirmed for Orion; assumed same for Pisces — verify before use) |
| Preprint | bioRxiv 10.64898/2026.03.18.712807 (X-Cell paper) |
| Announcement | BusinessWire 2026-03-17 |
| Notes | Pisces supersedes Orion and adds many new contexts. Extract HepG2 and Jurkat contexts specifically for VCC-300 mean. Verify HuggingFace dataset card for exact file names and checksums. |

### NEW CANDIDATE 2 — VIPerturb-seq K562 (Satija lab / Bradu et al., Feb 2026) ⚠ DATA ACCESS UNCONFIRMED

| Field | Value |
|---|---|
| Name | VIPerturb-seq K562 genome-wide CRISPRi |
| Cell line | K562 (CML) — same line as Replogle K562-gwps but INDEPENDENT screen |
| Perturbation type | Genome-wide CRISPRi using GuEST-List library (from Dolcetto library A) |
| Genes perturbed | Genome-wide (~20,000) |
| Number of cells | ~880,000 in one example screen |
| Est. VCC-300 coverage | ~300/300 (genome-wide) |
| Download route | UNCONFIRMED — no GEO/Zenodo accession found; check bioRxiv data availability section |
| Format | Unknown |
| Approximate size | Unknown |
| License | Unknown |
| Preprint | bioRxiv 10.64898/2026.02.12.705613 (Bradu et al., Satija lab) |
| Library reagent | Addgene plasmid ID 248189 |
| Notes | Independent K562 screen adds variance reduction to multi-source mean even though we already have Replogle K562-gwps. Data availability not yet confirmed — check full bioRxiv text. |

### NEW CANDIDATE 3 — K562 CRISPRi Screen Insights (Bradu et al., Oct 2025) ⚠ DATA ACCESS UNCONFIRMED

| Field | Value |
|---|---|
| Name | Pooled CRISPRi single-cell screens in K562 cells |
| Cell line | K562 |
| Perturbation type | Pooled CRISPRi single-cell screens |
| Preprint | bioRxiv 10.1101/2025.10.23.684112 (Oct 2025) |
| Download route | UNCONFIRMED — no GEO accession found |
| Est. VCC-300 coverage | ~300/300 (genome-wide assumed) |
| Notes | May overlap with or be a companion to VIPerturb-seq (Candidate 2). Check if same or separate data. |

---

## Checked But Already in Pipeline

- **KOLF2.1J iPSC atlas** (Nature Biotech July 2026, Figshare doi:10.25452/figshare.plus.27261219.v1, h5ad, ~176 GB full file, CC BY 4.0) — **ALREADY IN LIST**
- **Feng et al. Cell Genomics Feb 2026** (Sanger, 34 iPSC lines, 7,226 genes, doi 10.1016/j.xgen.2025.101076) — **ALREADY IN LIST (Sanger multi-donor hiPSC map)**

---

## Priority Queue for Extraction (as of 2026-10-15)

| Priority | Dataset | Action |
|---|---|---|
| 1 | X-Atlas/Pisces — HepG2 context | `huggingface-cli download Xaira-Therapeutics/X-Atlas-Pisces` then extract HepG2 rows |
| 2 | X-Atlas/Pisces — Jurkat contexts (resting + activated) | Same download, extract Jurkat rows |
| 3 | VIPerturb-seq K562 | First confirm GEO/accession by reading bioRxiv 10.64898/2026.02.12.705613 data-availability section |
| 4 | K562 CRISPRi screens (Oct 2025) | Confirm if same/different data as VIPerturb-seq |
