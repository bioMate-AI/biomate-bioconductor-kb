# H4 (Presentation) Corpus Inventory & Corrected Generalizability Verdict

**Date:** 2026-09-13 · **training_eligible = false** (inventory + acquisition only; no training claim)
**Scope:** cataloged all **23 HELD** immunopeptidome/proteome deposits on `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/` and fetched the confirmed-missing machinery-KO backlog.
**Companion:** `H4_CORPUS_INVENTORY.json` (per-deposit modality / HLA / context / KO / paired?), fetch log below.

---

## TL;DR — W7 was wrong

W7 (`W7_tier2_paired_atlas.md`) claimed the held H4 corpus is **"single-HLA, 1 cell line"** and that H4's thesis is validated on **one** line only. That is an undercount driven by W7 cataloging only ~11 deposits and treating each as one line.

**Corrected, from PRIDE metadata + actual S3 content of all 23 deposits:**

| Metric | W7 claim | **Corrected (HELD)** | **HELD + FETCHED** |
|---|---|---|---|
| Distinct HLA backgrounds spanned by held immunopeptidome | "1" | **≥ 32 named cell-line/donor contexts** (plus PXD071022 = **61 HLA alleles / 26 primary tumors**, multi-patient MM, multi-donor DR panels) | + HLA-A29, HLA-B*51:01, +9 melanoma lines (PXD013649) → still more |
| Distinct perturbation/KO condition classes | ~1 ("machinery-KO on one line") | **16 distinct perturbation arms** across 7 classes | +ERAP1/ERAP2/B2M/TAPBPR KO on new backgrounds |
| Distinct APM machinery genes perturbed | B2M etc. "on one line" | **14 genes**: B2M, TAP1, TAP2, TAPBP, IRF2, PDIA3, ERAP2, GANAB, SPPL3, CANX, CALR (PXD056426) + CIITA (PXD020079) + TAPBPR (PXD063219) + ERAP1 (PXD054491) | + ERAP1 (PXD060575/572/054494/013064), ERAP2 (PXD024109), B2M standalone (PXD065279), TAPBPR standalone (PXD078020) |
| Same-flask PAIRED (P+L) deposits | 2 | **≥ 4** (PXD056426, PXD020079, PXD065279, PXD076608; PXD060575/060572 add ERAP1 P+L matrices) | same +1 (PXD023044 pairing still needs its L half) |

**W7's "2 same-flask paired triples, both single-HLA" is corrected to ≥4 same-flask P+L deposits, and the corpus as a whole spans dozens of HLA backgrounds and 16 perturbation arms — not one line.**

---

## What W7 MISSED (12 deposits not in its catalog, all real & usable)

- **PXD022020** — 8 cancer-line HLA-I panel (PANC.1, A.375, SW527, CaSki, PC.3, LNCaP, MCF.7, VMRC.LCD). Processed peptide CSVs held.
- **PXD071022** — **26 primary CRC tumors, 61 HLA alleles**, MSS/MSI. Largest single HLA-diversity contributor. `.mzid` held.
- **PXD072525** — multiple myeloma primary patients + MM lines, proteogenomic `Results.zip` held.
- **PXD068488** — HLA-DR15 (**class-II**) across multiple MS donors + EBV perturbation; 57 `.msf`.
- **PXD074155** — HLA-DR MAPPs (**class-II**), **8 donors**, infliximab loading.
- **PXD076608** — CML lines, kinase-inhibitor perturbation, **immunopeptidome + (phospho)proteome co-reported → same-flask P+L**.
- **PXD070471** — CaCo2 + THP1, Coxsackievirus B3 infection (2 lines).
- **PXD070607** — MIAPACA2, lymphodepleting-chemo-induced presentation.
- **PXD070941** — U87 DMG/GBM, EGFR/PI3K-inhibitor perturbation.
- **PXD000394** — 7-line + primary HLA-I panel (**but S3 holds only a viewer stub** — accession cataloged, data not usable).
- **PXD004352** — 28 primary immune-cell **proteomes** (not immunopeptidome; P baseline).
- **PXD077352** — covalent/hapten neoantigens (**S3 holds only a SEARCH.txt stub**).

**Held-but-unusable (stub only):** PXD000394 (viewer stub), PXD022950 (README only), PXD077352 (search-param stub). W7 correctly flagged PXD022950; the other two are cataloged-not-usable.

---

## HELD corpus at a glance (usable HLA-typed immunopeptidome, 18 deposits)

- **Genetic KO/KD/OE:** PXD056426 (11-gene APM KO panel, HAP1, P+L — the H4 kill-test PASS), PXD020079 (CIITA-OE, 3 GBM lines, HLA-I+II, P+L), PXD063219 (TAPBPR-KD, HLA-B44:02/44:05 allele-controlled), PXD054491 (ERAP1 silencing, A375).
- **Drug:** MEKi (PXD041578), CDK4/6i abemaciclib (PXD060684), EGFR/PI3Ki (PXD070941), TKIs/CML (PXD076608), lymphodepleting chemo (PXD070607).
- **Cytokine:** IFN-α (PXD045265, β-cell/T1D), IFN-γ arm (PXD020079).
- **Infection:** Mtb (PXD037837, primary macrophage donors), influenza (PXD041578), CVB3 (PXD070471), EBV (PXD068488).
- **Microenvironment:** hypoxia (PXD055205, HCT116/HT29).
- **Baseline HLA panels (no perturbation):** PXD022020 (8 lines), PXD071022 (61 alleles), PXD072525 (MM).
- **Class-II axis (thicker than W7 implied):** PXD020079 (HLA-II), PXD068488 (DR15), PXD074155 (DR, 8 donors).

---

## FETCHED backlog (this run)

Landed under `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/immunopeptidome/{ACC}/`.
Policy: prefer PROCESSED peptide-identification / result files over `.raw`; report >2 GB before pulling; skip raw-only-huge.

| ACC | KO / perturbation | HLA background | Status | Files | Bytes | Notes |
|---|---|---|---|---|---|---|
| **PXD024109** | ERAP2 CRISPR KO vs WT (SILAC) | HLA-A29 (EBV-LCL) | ✅ FETCHED | 4 | 161,364,060 | Percolator PeptideGroups (HLA-A29 + W6/32), sets 1&2 |
| **PXD013064** | ERAP1 shRNA silencing | HLA-B*51:01 (HeLa.ABC-KO) | ✅ FETCHED | 3 | 4,913,391 | mzid+mztab+sdrf; bulky `.mgf` skipped |
| **PXD060575** | ERAP1 KO + inhibitor | A375 | ✅ FETCHED (P+L) | 5 | 601,548,047 | DIA-NN report.tsv + matrices; raw+xic skipped |
| **PXD060572** | ERAP1 KO + inhibitor | A375 / THP-1 | ✅ FETCHED (P+L) | 4 | 46,034,712 | DIA-NN matrices; raw+xic skipped |
| **PXD054494** | ERAP1 silencing (Part II) | A375 | ✅ FETCHED | 2 | 79,833,241 | Spectronaut result + peptide list (companion to held PXD054491) |
| **PXD065279** | **B2M KO** vs WT (+IFNg/TGFb) | A375 / JY / tumour frags | ✅ FETCHED (P+L) | 10 | 277,536,193 | MHC1-TIP combined_peptide + spectral lib + DIA-NN proteome; ~396 GB raw skipped |
| **PXD078020** | **TAPBPR (TBP) KO** vs WT | HeLa (HBV) | ✅ FETCHED core pair | 2 (+2 in bg) | 3,605,790,720 | WT + TBP_KO CoProcessed `.msf` (each ~1.7–1.9 GB, <2 GB). Two QE-replicate `.msf` queued in background; ~24.8 GB raw + allele subsets skipped |
| **PXD013649** | non-canonical/cryptic peptides (4-layer set) | 9 melanoma lines | ✅ FETCHED | 11 | 1,258,831,204 | paper_data.zip + 9 per-line search_*.zip + README; raw `.mgf` skipped. **Ribo-seq layer NOT confirmed at file level in fetched artifacts** |
| **PXD014804** | ERAP2 CRISPR KO | HLA-B*40:02 (C1R) | ⏭️ SKIPPED | 0 | 0 | Raw-only (14.8 GB raw); only non-raw artifact is a **51.7 GB** zip > 2 GB → skipped per policy |
| **MSV000091285** | **ONX-0914 immunoproteasome inhibitor** (+carfilzomib) vs vehicle | human B-lymphoblast | ⏭️ SKIPPED | 0 | 0 | MassIVE is **FTP-only**; FTP blocked/timeouts in this environment, no HTTPS mirror. Deposit **verified** via PROXI (Mamrosh 2023, PMID 37352349, Orbitrap Eclipse/Fusion, MHC-I, 55 files). Re-pull from `ftp://massive.ucsd.edu/v05/MSV000091285/` on an FTP-capable host |

**Total fetched: 8 deposits, ~6.03 GB of processed files across ~41 objects.** 2 skipped (1 raw-only-huge, 1 FTP-transport-blocked).

New machinery-KO axis added by the fetch: **ERAP1** (PXD060575/060572/054494/013064 → 4 new arms on A375/THP-1/HeLa-B51 beyond held PXD054491), **ERAP2** (PXD024109, HLA-A29; PXD014804 skipped), **B2M standalone** (PXD065279, A375/JY beyond the HAP1 panel), **TAPBPR standalone** (PXD078020, HeLa beyond held PXD063219). This is exactly the **leave-KO-out / leave-line-out** replicate set for H4.

---

## Corrected H4-generalizability verdict

**Q: How many HLA backgrounds are trainable with HELD + FETCHED data?**

- **As unpaired ligandome (L-only) across HLA backgrounds:** dozens — ≥32 named cell-line/donor contexts + 61 CRC HLA alleles + multi-patient MM + multi-donor class-II DR panels. H4 as a *sequence→presentation* / HLA-restricted binding-and-processing model has **broad** HLA coverage, not one background.
- **As a same-flask PAIRED (proteome+immunopeptidome) causal H4 (the strict "train the cross-modal transform" bar):** the paired moat is **≥4 deposits** (PXD056426 HAP1, PXD020079 GBM ×3 lines, PXD065279 A375/JY, PXD076608 CML), plus ERAP1 P+L (PXD060575/060572). That is **≥5–6 distinct HLA backgrounds with same-flask P+L**, up from W7's "2, both single-HLA."
- **As machinery-KO→presentation causal edges (H4's mechanistic core):** HELD spans **14 APM genes**; FETCHED adds **ERAP1/ERAP2/B2M/TAPBPR KO replicates on ≥4 new HLA backgrounds** (HLA-A29, HLA-B*51:01, A375, HeLa, THP-1, JY). The single-deposit, single-HLA HAP1 dependency that W7 flagged is now **broken**: B2M, ERAP1, ERAP2, TAPBP/TAPBPR each have ≥2 independent HLA backgrounds.

**Can H4 now train beyond one cell line / one HLA background?**
**YES for the leave-line-out / leave-KO-out generalization test** — the held multi-line panels + the fetched machinery-KO replicate cluster provide multiple independent HLA backgrounds per perturbation class. W7's "NO-GO on held data, conditional-GO after fetches" is upgraded to **GO after this fetch** for H4 as a generalizing presentation/machinery-state model. (This is a *data-availability* verdict; `training_eligible=false` — actual training + a leave-line/HLA-out result beating baseline remains a separate authorized step.)

**Remaining genuine gaps (unchanged, re-confirmed):**
- **MSV000091285** immunoproteasome-selective (ONX-0914) arm — verified-deposited but FTP-transport-blocked here; needs an FTP-capable pull.
- **PXD014804** ERAP2/B40:02 — processed artifact is a 51.7 GB zip; deferred.
- **Same-flask Ribo-seq (H2) under perturbation on any HLA-typed line** — still white space; PXD013649's ribo layer not confirmed in fetched artifacts.
- **Standalone NLRC5-KO, PSMB8/9/10 (immunoproteasome-catalytic) KO, PSME1/2/3 (PA28) KO immunopeptidome** — re-confirmed not to exist publicly (generation-only).

---

## Fetch log (raw)

Per-file OK/size/sha256 recorded in the run; S3-verified object counts/bytes per deposit:

```
PXD024109 : 4 objects, 161,364,060 bytes
PXD013064 : 3 objects,   4,913,391 bytes
PXD060575 : 5 objects, 601,548,047 bytes
PXD060572 : 4 objects,  46,034,712 bytes
PXD054494 : 2 objects,  79,833,241 bytes
PXD065279 : 10 objects, 277,536,193 bytes
PXD078020 : 2 objects (core WT/KO pair) + 2 QE-replicate .msf in background, 3,605,790,720 bytes so far
PXD013649 : 11 objects, 1,258,831,204 bytes
PXD014804 : SKIPPED (raw-only + 51.7 GB processed zip > 2 GB)
MSV000091285 : SKIPPED (MassIVE FTP-only, transport blocked; verified via PROXI)
```

**Environment note:** this run hit a host-disk-full (228 Gi volume at ~100%) mid-fetch; resolved by streaming files one-at-a-time (download→S3→delete) so nothing large persisted locally. All uploads S3-verified after the fact.
