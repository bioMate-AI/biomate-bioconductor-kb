# W7 — Tier-2 Paired Multi-Omic Perturbation Atlas: feasibility inventory

**Role:** FEASIBILITY (the #1 gap) · **Date:** 2026-09-13 · **Output pair:** `W7_tier2_paired_atlas.{json,md}`

**The canonical question (OBJECTIVES.md §5 / docx):** *For how many `(cell-context × perturbation × HLA-genotype)` triples does MORE THAN ONE central-dogma modality co-exist?* — the number that decides whether H2→H3→H4 + the machinery-state bottleneck can be trained before wet-lab spend.

**Modalities:** **T** = perturbation/transcriptome (H1) · **R** = Ribo-seq (H2) · **P** = proteome (H3) · **L** = immunopeptidome peptide-HLA (H4 readout).

---

## THE ANSWER (up front, brutally honest)

The registries claim "~25–30 perturbation-paired ligandomes, a 4-layer set exists, feasible not just bootstrap." That is true about **EXISTENCE** (accessions are real and verified) but **not about HOLDINGS**. Measured live on S3 (2026-09-13), what is actually **HELD and trainable today** is far smaller:

| Tier | Definition | ≥2 modalities | ≥3 | 4-layer (T+R+P+L) |
|---|---|:-:|:-:|:-:|
| **Same-deposit, HELD** (trains the cross-modal transform directly) | modalities co-deposited on the SAME flask AND bytes on S3 | **2** | **0** | **0** |
| **Same-context, cross-study HLA-join, HELD** (weaker; pretraining/baselines only) | held L on a CCLE line + T/P joined by cell-line HLA | **~8** | ~6 | 0 |
| **Identified, NOT held** (acquisition backlog) | verified accession, not on S3 | ~25–30 | several | 1 candidate (PXD013649, ribo arm file-unverified) |

**The two same-flask HELD paired triples:**
1. **PXD056426** — HAP1, 11-gene antigen-processing-machinery KO (B2M/TAP1/TAP2/TAPBP/ERAP2/PDIA3/CALR/CANX…) vs WT, **+ matched proteome in-deposit → P+L**. Genetic perturbation, **one** HLA background. *This is the H4 kill-gate PASS set and the only held machinery-KO causal pair.*
2. **PXD020079** — glioblastoma HROG lines, **CIITA overexpression + IFN-γ**, HLA-I & HLA-II + a proteome `.raw` in-deposit → **P+L**. The only held class-II paired set.

**Both are single-HLA-background.** Same-deposit ≥3 modality = **0**. Same-deposit 4-layer = **0**.

---

## Ground truth: HELD vs IDENTIFIED (the load-bearing distinction)

The immune-llm manifests count **VERIFIED accessions**; this workstream counts **landed bytes**. The gap between them is acquisition status, not fabrication — but it is the whole story for trainability.

**Immunopeptidome (L) HELD on S3 — 11 deposits** (`…/acquisitions/immunopeptidome/`):
`PXD056426` (HAP1 APM-KO, **P+L**), `PXD020079` (CIITA-OE +IFN-γ, **P+L**, class-II), `PXD054491` (ERAP1-KO A375, L), `PXD063219` (TAPBPR KD/OE HeLaM-B44, L), `PXD060684` (CDK4/6i CAMA1, L), `PXD045265` (IFN-α β-cell ECN90, L), `PXD041578` (flu+MEKi Calu-3, L), `PXD037837` (Mtb primary donor, L), `PXD055205` (hypoxia HCT116/HT29, L), `PXD068488` (MS RRMS B cells HLA-DR, L), `PXD022950` (README only — **not usable**).

**Proteome (P) HELD — 1:** `PXD023038` (TNBC MDA-MB-231 DIA, IFN±, RAW). Its immunopeptidome half **PXD023044 is NOT held**.

**Ribo-seq (R) HELD — 2 series, LIMITED:** `GSE182371`, `GSE254157`. The H2 acquisition self-reports **go/no-go = LIMITED**: 0 usable processed general ribo-seq series landed; matched-RNA/RPF uploads **FAILED** for the T-cell (GSE254230), K562-KO (GSE224662) and Jurkat (GSE313291) series. The ~14.8k-sample public Ribo-seq corpus (RDP) is real but essentially **unretrieved**.

**Transcriptome (T) HELD — DEEP:** Tahoe-100M (50 lines × ~1,100 compounds), Replogle/Nadig, CZI primary-T-cell effect layers. Not the bottleneck; every line HLA-keyable via TCLP.

**The flagship "moat" accessions are IDENTIFIED-NOT-HELD:** the 4-layer `PXD013649` (Chong 2020, ribo arm file-unverified), the T+P+L "prize" `PXD020750` (GRANTA-519), `PXD023044`, `PXD017407+GSE144373`, `MSV000091285` (ONX-0914), and the machinery-KO cluster (ERAP1/2, B2M, TAPBP/TAPBPR KO). These are the acquisition backlog — **not trainable today**.

---

## Per-head trainability verdict (beyond one cell line, TODAY)

| Head | Trainable today | Beyond 1 cell line? | Why |
|---|---|:-:|---|
| **H1** perturbation→transcriptome | **YES, abundant** | **YES** | Tahoe/Replogle/CZI held; unpaired-per-modality, no paired atlas needed. |
| **H2** transcriptome+Ribo-seq | **As matched head: NO** | **NO** | 0 same-flask T+R triples held; 0 perturbation Ribo-seq on any HLA-typed line held; H2 acquisition LIMITED. Matched R is genuine white space. |
| **H3** transcriptome+proteome | Baseline YES / perturbation-delta NO | **NO** (delta) | Same-deposit T+P held = 0; P+L held = 2. Baseline H3 (CCLE 375 / ProCan 949 lines) fetchable, so per-modality H3 is fine; same-flask perturbation-delta across lines is not held. |
| **H4** proteome/pert.+HLA→immunopeptidome | **Thesis VALIDATED on 1 line; trained head across >1: NO** | **NO** | H4 kill-gate PASSED on HAP1 (B2M-KO→2% presentation, proteome ~100%, ρ=−0.51) — mechanism validation on **one** cell line, **one** HLA background, from the **single** same-flask machinery-KO P+L deposit held (PXD056426). Every other held L is L-only or a single perturbation class. A generalizing H4 (leave-line/HLA/KO-out beating B1) is **not** trainable on held data. |

**Bottom line: H2, H3 (as perturbation-delta), and H4 are NOT trainable beyond one cell line / HLA today.** H4's thesis is *validated* on one line; that is the ceiling of the held moat.

---

## The specific paired-data gap → what closes it

**Step 1 — zero-cost public fetches** (public, no wet-lab; widen H4 from 1 → ~4–7 HLA backgrounds same-flask):
- **PXD020750** (GRANTA-519 IFN-γ, single-deposit T+P+L) — highest-value; +1 distinct HLA background.
- **PXD023044** (completes P+L on the held TNBC proteome; MDA-MB-231 HLA) — +1.
- **PXD017407 + GSE144373** (4-line melanoma panel, IFN-γ + palbociclib, T+P+L) — +4 HLA-typed lines + a 2nd perturbation class.
- **MSV000091285** (ONX-0914 immunoproteasome-inhibitor HLA-I) — extends the machinery axis pharmacologically.
- **Machinery-KO cluster** PXD060575/060572/054494 (ERAP1), PXD014804/024109 (ERAP2), PXD065279 (B2M), PXD078020/046825 (TAPBP/TAPBPR), PXD013064 (ERAP1-shRNA) — multi-HLA replicates of the HAP1 causal signal; the direct **leave-KO-out / leave-line-out** training set for H4.

**Step 2 — what public data STILL cannot supply (Tier-2 CRO required):**
- **Same-flask Ribo-seq (H2) under perturbation on any HLA-typed line** — genuine white space; matched H2 requires generation.
- **Same-flask 4-layer T+R+P+L on >1 HLA background** — 0 held; PXD013649 is the only candidate and its ribo arm is file-unverified.
- **Standalone NLRC5-KO, PSMB8/9/10 (immunoproteasome catalytic) KO, PSME1/2/3 (PA28) KO immunopeptidome** — re-confirmed to **not exist anywhere publicly**; the single highest-value dataset that does not exist.

**The minimal CRO atlas to move H4 from *validated* to *trained*:**
> HLA-typed cell-line panel (≥6 lines spanning common supertypes) × machinery-perturbation panel (B2M, TAP1/2, TAPBP, ERAP1/2, **PSMB8/9/10**, **NLRC5**, CIITA KO + IFN-γ/IFN-α/MEKi/CDK4/6i drug arms) × **paired same-flask T + P + L** (HLA-I & HLA-II), matched WT/vehicle, ≥3 reps.
> **Minimum:** 6 lines × (B2M+TAP1+TAPBP+ERAP1+PSMB8 KO + WT) × paired P+L = 36 conditions (×2 with IFN-γ arm ≈ **72 same-flask paired units**) — closes leave-line-out / leave-KO-out for H4. This is the moat that is generated, not scraped.

---

## Go / No-Go

- **H4 thesis kill-test:** **GO** — already PASSED on public data (HAP1/PXD056426).
- **H4 trained head beyond one line:** **NO-GO on held data**; **conditional-GO** after the Step-1 public fetches (reaches ~4–7 HLA backgrounds); **FULL-GO** requires Tier-2 CRO for the immunoproteasome/NLRC5 KO ligandomes + any matched Ribo-seq.
- **H2 matched head:** **NO-GO** on public data (white space) — Tier-2 generation required.
- **H3 baseline head:** GO (CCLE/ProCan fetchable); perturbation-delta across lines = same gap as H4.
- **H1:** **GO** — abundant, largely held.

**This confirms the docx §5 premise exactly:** the paired moat is scarce. As a same-flask, HELD, trainable corpus it is **2 paired triples (both single-HLA)**, only one of which (PXD056426) carries the machinery-KO causal signal H4 depends on. The thesis is testable and validated on one line; training a generalizing H4/H3-delta/H2 across cell lines and HLA backgrounds is blocked on **acquisition** (for T/L) and **generation** (for R and for multi-HLA immunoproteasome/NLRC5 KO L).

---

## Caveats
- **HELD vs IDENTIFIED** is the whole story; S3 measured 2026-09-13 vs registry accession lists.
- PXD056426/PXD020079 in-deposit proteome is asserted from `.raw` filenames — proteome *usability* still needs a DIA/immunopeptidomics search step.
- Cross-study HLA-join triples (~8) are not same-flask; per docx §6 "unpaired data cannot train the cross-modal transformation" → pretraining/baselines only.
- H2 acquisition self-reported LIMITED (upload failures); corpus exists (~14.8k RDP) but unretrieved, and is genuine white space *under perturbation on HLA-typed lines*.
- PXD013649 4-layer: accession real, ribo-seq-in-deposit at file level UNVERIFIED and NOT HELD — not counted as a trainable 4-layer set.
