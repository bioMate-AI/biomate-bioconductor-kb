# H4 cross-allele gap — BROADER machinery-perturbation rescan

Date 2026-09-14. `training_eligible=false`. Metadata/search task (4.1 GB free; no large pull).

## Reframe

The prior `HARD_ESSENTIAL_KO_RESCAN` only looked for **genetic hard-essential KO**
(B2M/TAP/TAPBP) on disjoint non-A\*02 alleles → found 0 → "CRO required." But the H4
thesis is "antigen-processing **machinery STATE** controls presentation," testable by
**any** machinery perturbation with a control arm — cytokine (IFN-γ / type-I IFN),
proteasome/immunoproteasome inhibitor, natural APM loss, or TAP-deficiency — not only
irreversible genetic KO.

**A\*02 cluster to be disjoint from:** HAP1, A375, THP-1, HeLa — and now also
**MDA-MB-231** (A\*02:01+/A\*02:17), confirmed here.

## Decisive answer: YES — ≥3 disjoint-allele machinery backgrounds are fetchable from public data

**`PXD014017` alone supplies all three.** "Multifactorial remodeling of the cancer
immunopeptidome by IFNγ" (Cancer Res Commun 2023; organoid HLA from Newey 2019, JITC
7:309). Three CRC patient-derived organoids, each with a **paired +IFNγ vs DMSO** HLA
class I immunopeptidome, **all A\*02-negative and mutually allele-diverse**:

| PDO | HLA-A | HLA-B | HLA-C | A\*02? |
|-----|-------|-------|-------|--------|
| CRC-01 | A\*31:01, A\*32:01 | B\*14:01, **B\*27:05** | C\*02:02, C\*08:02 | NO |
| CRC-04 | **A\*03:01**, A\*24:02 | B\*18:01, B\*35:08 | C\*04:01, C\*05:01 | NO |
| CRC-05 | A\*32:01 | B\*40:01 | C\*03:04 | NO (HLA LOH) |

- Perturbation = IFN-γ 600 ng/mL 48 h vs DMSO (immunoproteasome PSMB8/9/10 + TAP + ERAP induction).
- 2,124–16,030 HLA-I peptides/PDO; **1,439–3,942 gained and 561–2,446 lost per PDO** through IFN-γ.
- **Processed ligandome available:** per-PDO supplementary Excel peptide tables ("Data
  CRC01/04/05") give processed HLA-I peptide lists per condition — **no raw reprocessing**.
  (PRIDE also hosts 640 MB / 345 MB MaxQuant no-enzyme search zips; too big for 4 GB free —
  use the paper supplements instead.)
- **Open access.**

## Supporting machinery deposits (processed, but not A-locus-disjoint)

| Accession | Perturbation | Background(s) | A\*02? | Processed ligandome | Role |
|-----------|--------------|---------------|--------|---------------------|------|
| **PXD014397** | ±IFN-γ | LM-MEL-33/44/53 (melanoma) | **YES (all)** | **.mztab.gz (~27 MB) + .mzid.gz — small, no reprocessing** | Best file ergonomics but all A\*02:01+; deepens A\*02 axis, method cross-check. Mel33 adds A\*03:01/B\*47/C\*06:02 as 2nd alleles. |
| PXD023044/38 | ±IFN-γ | MDA-MB-231 (TNBC) | **YES** | .mzid.gz per rep | IFN-γ contrast; A\*02:01+ but adds B\*40:02/B\*41:01/C\*02:02/C\*17:01. Was excluded in KO-rescan (no KO); valid under machinery reframe. |
| PXD020079 (HELD) | CIITA + IFN-γ | HROG02/HROG17/RA (GBM) | **unresolved** | raw on S3 (9.5 GB) | 3 GBM lines with +IFN-γ arms — **type HROG02/17/RA**; any A\*02-neg one ADDS a disjoint IFN-γ fold. Cheap follow-up. |

## Off-axis / secondary leads

- **PXD024331** — abacavir on C1R.**B\*57:01** (disjoint) — but abacavir is a groove-altering
  hapten (not processing-machinery), and processed files are **proteome + MRM only** (no
  eluted-ligand table). Lead, not a background.
- **PXD027859** — vaccinia infection on B27-C1R (**B\*27:05**, disjoint) — infection, not a
  defined machinery arm; **.wiff/.mgf only**, no processed table.
- **PXD037843** — Mtb + IFN-β on primary macrophages (A\*02:01+/B\*57:01+ donors) — IS-PRM
  **targeted** validation, not a global repertoire contrast.
- ERAP1/TAPBPR/tapasin editor deposits (PXD066752, PXD060575, PXD063219, PXD046825,
  PXD054743), TKI-CML (PXD076608), SUMO (PXD060641/61) — editor/off-axis, already catalogued.
- PXD063813 (B2M-KO C1R/K562) — genetic KO, A\*02, proteome-only — belongs to the KO rescan.

## Honest verdict on the CRO

- **The disjoint-allele MACHINERY-STATE test is now runnable on public data.** If the H4 gate
  accepts a **cytokine (IFN-γ) machinery perturbation** as the perturbation axis, PXD014017
  re-powers the cross-allele gate at **zero acquisition cost**, and the CRO **shrinks or is avoided**.
- **Critical caveat — sign mismatch.** IFN-γ **induces/diversifies** presentation
  (gain-of-machinery); B2M/TAP KO **ablates** it (loss-of-machinery collapse). Both probe
  "machinery state → presentation," but if the gate strictly requires a **presentation-COLLAPSE
  (KO-style) readout across disjoint alleles**, IFN-γ data does **not** substitute and the CRO
  remains for that specific readout.
- **Recommendation:** run the **reframed gate on PXD014017 first** (3 disjoint A\*02-negative
  backgrounds, processed peptides from the paper supplements) to test whether cross-allele
  machinery-dependence holds. Add PXD014397 + PXD023044 as within-A\*02 method cross-checks, and
  type HROG02/17/RA (PXD020079) for possible extra disjoint IFN-γ folds. Only escalate to the
  hard-essential-KO collapse CRO if the reframed machinery test is judged insufficient for the decision.

## Net

- **Prior narrow (genetic-KO) frame:** 0 disjoint backgrounds → CRO required.
- **Broader (machinery-perturbation) frame:** **3 disjoint backgrounds fetchable in one open
  deposit (PXD014017), IFN-γ perturbation, processed ligandome available** → cross-allele gate
  is runnable on public data; CRO shrinks/avoided **if** an IFN-γ machinery contrast is accepted
  in place of a hard-essential-KO collapse.
