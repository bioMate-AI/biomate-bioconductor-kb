# Leave-HLA-Out Gate — Authoritative Corrected Result

**Date:** 2026-09-14 · **training_eligible = false**
**Supersedes:** `LEAVE_HLA_OUT_RESULT.json` · **Built on:** `GATE_VERIFICATION.json` + `A375_B2M_KO_DIAGNOSTIC.json`

## What changed (all three fixes applied together)

1. **TAPBPR mislabel fixed.** HeLa (PXD078020) is **TAPBPR** (gene *TAPBPL*, a peptide **editor**), not TAPBP (tapasin, a hard essential). Severity set to editor-class **0.20** (was 0.80). This alone flips the training-slope sign.
2. **Disjoint-allele parser fixed.** The check now splits genotypes on `[;,\s]` (was `,` only, which left `;`-separated strings as one glued token that never matched → always reported "disjoint"), plus 1-field group normalization so `A*02` matches `A*02:01`. It now correctly detects that A375/THP-1/HeLa all share **HLA-A\*02**.
3. **Ligand-stratified retention for ALL 4 backgrounds.** Presentation is re-scored as genuine-HLA-I-ligand retention = anchor-matched 8–11mers(KO) / anchor-matched 8–11mers(WT), using the 202-allele mono-allelic anchor. This is the `A375_B2M_KO_DIAGNOSTIC` method (A375 B2M: total 0.878 → ligand ~0.12–0.19) applied uniformly, so mild-acid-elution (MHC1-TIP) and W6/32-IP deposits become comparable.

## Per-background ligand-stratified KO retention

| Background (enrichment) | KO | **ligand ret** | total ret | reads as |
|---|---|---|---|---|
| HAP1 (W6/32 IP) | B2M | **0.094** | 0.028 | collapse |
| HAP1 | TAP2 | 0.324 | 0.172 | strong loss |
| HAP1 | TAPBP | 0.291 | 0.242 | strong loss |
| HAP1 | ERP57 | 0.493 | 0.389 | loss |
| HAP1 | TAP1 | 0.648 | 0.486 | partial |
| HAP1 | ERAP1 | 0.562 | 0.499 | partial (trimmer) |
| HAP1 | IRF2/GIIA/SPPL3/CANX/CALR | 0.37→0.97 | — | graded |
| A375 (MHC1-TIP/MAE) | **B2M** | **0.189** | 0.878 | **collapse** (was "88% retained") |
| A375 | ERAP1 | 0.938 | 0.988 | no loss (trimmer) |
| THP-1 (DIA) | ERAP1 | 1.002 | 0.845 | no loss (trimmer) |
| HeLa (msf) | TAPBPR | 1.065 | 1.049 | broadens (editor) |

**Key reconciliation:** A375 B2M-KO's "88% retained" was a mild-acid-elution non-HLA background artifact. On genuine HLA-I ligands it collapses to **~19%**, agreeing with HAP1's B2M collapse (**~9%**). Within HAP1, machinery severity predicts ligand loss across all 11 KOs (Spearman **0.87**).

## Corrected gate statistics

| | pooled transfer ρ | perm p | HAP1 fold | verdict |
|---|---|---|---|---|
| **Original (uncorrected)** | −0.9312 | 0.883 | −0.9203 | FAIL / "contradicted" |
| **Corrected, full 4 bg** | **+0.6792** | **0.0003** | **+0.8656** | UNPROVEN |
| Corrected, no-A375 | +0.3906 | 0.0017 | +0.8656 | UNPROVEN |

The **sign flips positive** and becomes **significant**. Even excluding A375, the positive transfer holds (ρ=+0.39, p=0.002) — the corrected result is not an A375 artifact.

## PASS-rule scorecard

| criterion | required | value | met |
|---|---|---|---|
| pooled ρ ≥ 0.30 | yes | **+0.6792** | ✅ |
| perm p ≤ 0.05 | yes | **0.0003** | ✅ |
| ≥3 backgrounds carry ordering | yes | **1** (only HAP1 has ≥3 KOs) | ❌ |
| disjoint HLA alleles across folds | yes | A\*02 shared A375/THP-1/HeLa | ❌ |

**VERDICT: UNPROVEN across HLA** — not contradicted, not passed. The effect-size and significance criteria now pass; the two **structural** criteria (≥3 informative backgrounds, allele-disjointness) still fail.

Disjointness detail (fixed parser): HAP1 (A\*03:01/B\*51:01/C\*01:02) is fully disjoint from all others, but A375/THP-1/HeLa all share HLA-A\*02 (plus pairwise C\*06:02, B\*35). Since HAP1 is the only informative fold and its training set is not internally disjoint, the disjoint-across-folds bar is not met.

## Bottom line

- **Sign flip: confirmed** (+0.68, p=0.0003).
- **Hard essentials agree on collapse: confirmed** — HAP1 B2M 0.09 and A375 B2M 0.19 both collapse on the ligand measure; trimmer/editor KOs correctly do not.
- **Still UNPROVEN: confirmed** — only ~1 informative fold and all public backgrounds share HLA-A\*02 (non-disjoint). The coordinator's expectation reproduces exactly.

## CRO conclusion — does it hold?

**Yes, the disjoint-allele-coverage requirement HOLDS**, but the framing improves. It is no longer "the thesis is contradicted, re-establish it" but **"the thesis is corroborated on 2 independent HLA backgrounds (HAP1 + A375 B2M, ligand-scored) but not yet PROVEN cross-allele."** The CRO must still supply **≥3 distinct, allele-disjoint HLA backgrounds** each carrying the **hard-essential** panel (B2M/TAP1/TAP2/TAPBP, ≥3 KOs/background) with same-flask matched proteome and **W6/32-IP (or ligand-validated) enrichment — not bare MAE**. Because the A375 anomaly is now resolved (method+measure artifact, not biology), the CRO priority shifts from "diagnose the discordance" to "establish the disjoint hard-essential backgrounds," and any future scoring must ligand-stratify to avoid the MAE background confound.
