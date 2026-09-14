# H4 IFN-γ cross-allele MACHINERY-INDUCTION remodeling gate — REFRAMED

Date 2026-09-14. `training_eligible = false`. Verdict: **WEAK / partial transfer — does NOT
substitute for the KO-collapse CRO.**

## What was tested and why
The KO-collapse H4 gate is structurally **untestable cross-allele on public data**: every public
hard-essential-KO (B2M/TAP/TAPBP) immunopeptidome is HLA-A\*02 (see `H4_GATE_CORRECTED_VERDICT.md`).
`H4_MACHINERY_PERTURB_RESCAN.json` reframed the question: **PXD014017** (Cancer Res Commun 2023,
*Multifactorial Remodeling of the Cancer Immunopeptidome by IFNγ*, PMID 37991387) supplies **3
A\*02-negative, allele-diverse CRC organoids**, each with a paired **+IFN-γ vs untreated** HLA-I
immunopeptidome. IFN-γ is a genuine antigen-processing **machinery perturbation** (induces
immunoproteasome PSMB8/9/10 + TAP + ERAP). This gate asks: **does the map [peptide's
immunoproteasome cleavage-context] → [IFN-γ remodeling: gained vs lost] transfer across these
disjoint alleles?**

## Data (per-PDO processed peptide tables, no raw reprocessing)
Fetched the 3 supplementary Excel tables (s01/s02/s03, 7.8/5.8/2.9 MB) via EuropePMC
`supplementaryFiles` — **not** the 640/345 MB PRIDE MaxQuant zips (disk-safe). Each has per-peptide
`Sequence, C-termAA, length, UT & IFNg intensities, Peptidomics_FC, C.term.cleavage.window,
BAmostlikely allele, BAminRank (NetMHCpan %rank)`.

| PDO | Alleles (all A\*02-negative) | genuine ligands | gained (IFNg-only) | lost (UT-only) |
|-----|------|----:|----:|----:|
| CRC-01 | A\*31:01 A\*32:01 B\*27:05 B\*14:01 C\*08:02 C\*02:02 | 16,298 | 2,101 | 1,054 |
| CRC-04 | A\*03:01 A\*24:02 B\*35:08 B\*18:01 C\*05:01 C\*04:01 | 11,508 | 1,798 | 1,501 |
| CRC-05 | A\*32:01 B\*40:01 C\*03:04 | 4,938 | 913 | 220 |

**Ligand stratification** (same discipline as the renormalization): length 8–12 **and** NetMHCpan
`BAminRank ≤ 2.0` against the PDO's OWN assigned allele (`BAmostlikely` is always one of that PDO's
alleles → disjoint by construction).

## Leave-organoid-out cross-allele transfer

**Primary metric** — data-driven per-C-terminal gained-fraction table learned on 2 PDOs, scoring the
held-out PDO; statistic = **mean of the 3 per-fold AUROCs** (base-rate-free, since the PDOs have
different gained:lost ratios). Feature is HLA-agnostic; fit never sees held-out peptides.

| Held-out fold | AUROC (full) | AUROC (strict-disjoint*) |
|---|---:|---:|
| CRC-01 | 0.576 | 0.590 |
| CRC-04 (fully disjoint) | 0.520 | 0.520 |
| CRC-05 | 0.538 | **0.503** |
| **mean** | **0.544** | **0.537** |

- **Permutation null** (2,000 label shuffles): null mean 0.500, p95 0.540 → **p = 0.021**.
- *Strict-disjoint = held-out PDO re-scored **excluding** peptides on an allele it shares with a
  training PDO (CRC-01 ∩ CRC-05 = A\*32:01). CRC-05 then **collapses to chance (0.503)** — its
  apparent transfer was largely riding on the shared A\*32:01.

**Secondary** (fixed immunoproteasome C-term chemistry prior — the biologically-motivated
"immunoproteasome favours hydrophobic/aromatic + basic, disfavours acidic" prior): **FAILS.**
Pooled AUROC 0.405; continuous log2FC transfer ρ = **−0.31** (p = 0.74). The hand-coded
immunoproteasome signature does not predict IFN-γ gain across these backgrounds.

**Why it fails to transfer** — the gained C-terminal residue tracks **each PDO's own HLA anchor**,
not a shared immunoproteasome signature: hydrophobic/aromatic C-termini are gained most in CRC-01 &
CRC-05 (whose alleles favour them), but in **CRC-04** the dominant gained C-term is **K** (its
A\*03/A\*24 basic anchor) and **W is gained LEAST (0.19)** — the opposite of CRC-01/05. IFN-γ
remodeling is **allele-motif-dominated**, not a portable machinery C-term signature.

## Disjoint-allele / leakage check (confirmed)
- **All 3 backgrounds are A\*02-negative** → disjoint from the KO cluster. ✔
- CRC-04 is **fully disjoint** from the other two. CRC-01 & CRC-05 **share A\*32:01** (one allele) —
  a minor optimism source, quantified by the strict-disjoint sensitivity above.
- Feature is a fixed HLA-agnostic residue function; no held-out peptides enter the fit.

## Verdict: WEAK / partial — CRO still required

**What this PROVES:** a shared, machinery-linked component of IFN-γ remodeling transfers across
disjoint alleles at a **statistically-significant but tiny** level (AUROC 0.544, p=0.021).

**What it does NOT prove:**
1. **Not a KO-collapse test.** IFN-γ *induces* presentation (gain-of-machinery); B2M/TAP/TAPBP KO
   *ablates* it (loss-of-machinery). Opposite direction — cannot substitute for the collapse readout.
2. **Far too weak** to carry a cross-allele generalization claim (need ≥0.65; got 0.544, ~4pp over
   chance; **0.537 and fully-disjoint folds ≈0.50** on strict-disjoint scoring).
3. IFN-γ remodeling **direction is allele-motif-dominated**, not a portable immunoproteasome
   signature (fixed prior: AUROC 0.405, ρ −0.31).

**CRO implication:** the reframed public-data test does **NOT reduce or eliminate** the KO-collapse
CRO. The hard-essential presentation-COLLAPSE claim on ≥3 disjoint-allele backgrounds still requires
the wet experiment (consistent antibody-IP + matched proteome + verified-complete KO + absolute
quant), exactly as `H4_GATE_CORRECTED_VERDICT.md` concluded.

**What the public data DID buy (positive value):** it cheaply **ruled out** the optimistic hope that
free IFN-γ organoid data could stand in for the KO-collapse CRO, and produced a useful negative
mechanistic finding — IFN-γ repertoire remodeling is **allele-motif-dependent, not a portable
machinery C-term signature** — which *reinforces* the CRO's disjoint-allele design requirement:
presentation-machinery effects must be measured **per allele background**.

## Reproduce
`scratchpad/ifng_gate.py` (loaders, ligand stratification, leave-organoid-out, permutation null,
strict-disjoint sensitivity) → `H4_IFNG_CROSSALLELE_GATE.json`.
