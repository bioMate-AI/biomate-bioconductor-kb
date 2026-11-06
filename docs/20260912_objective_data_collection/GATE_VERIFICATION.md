# Leave-HLA-Out Gate — Adversarial Verification

**Date:** 2026-09-13 · **training_eligible = false**
**Verifies:** `LEAVE_HLA_OUT_RESULT.json` / `leave_hla_out_gate.py`
**Method:** Independent recomputation of every retention fraction from the raw S3 deposit peptide tables, plus a clean-room reimplementation of the LOO-CV / permutation-null math (no reuse of the prior agent's numbers).

## Headline

The FAIL verdict **reproduces numerically and exactly**, but it is **fragile, not robust**, and its stated *reason* is wrong:

- **NOT driven by the A375 anomaly.** Excluding A375 entirely, pooled transfer stays ρ = **−0.9381**, p = 0.87 → still FAIL. A375 is a symptom.
- **IS driven by a gene-identity mislabel.** HeLa's **TAPBPR** (editor, gene *TAPBPL*) KO is labeled **"TAPBP"** (a hard essential) in `build_inventory.py`. That single mislabeled point inverts the cross-fold OLS slope, turning the only informative fold (HAP1) from **+0.92 to −0.92**. Correct the label and the sign flips positive; with A375 also excluded it would **PASS** (ρ=0.729, p=0.0007).
- **All four backgrounds' retention fractions reproduce from raw data.** HAP1 B2M = 0.0279, A375 B2M = 0.8784, THP-1 ERAP1 = 0.8451, HeLa TAPBPR = 1.1382 (reported 1.1389).

## 1. Apples-to-apples (HAP1 3% vs A375 88%) — GENUINE, same measure

Both use **within-deposit unique-peptide detection-count fraction of WT** (peptide present if detected in ≥1 run; 8–25mers). Recomputed from raw:

| | source | WT peptides | KO peptides | retention |
|---|---|---|---|---|
| HAP1 B2M | PXD056426 DIA-NN `Search_results_DIA.tsv` | 18,624 | 520 | **0.0279** |
| A375 B2M | PXD065279 FragPipe `combined_peptide` | 2,410 | 2,117 | **0.8784** |

A375 B2M cross-measure: detection 0.878 / summed-spectral 0.860 / intensity 0.646; 49% of B2M-KO peptides shared with WT. **All 2,117 B2M-KO peptides are Match Type = MS/MS — zero match-between-runs inflation.** The 3%-vs-88% discordance is a **real** experimental/biological discordance, not a definition mismatch or an MBR artifact. Depth differs (DIA vs DDA) but retention is a within-deposit ratio so depth cancels.

## 2. Pooled ρ = −0.9312 / p = 0.883 — re-derived, correct, single-fold-dominated

Reproduced exactly. Only HAP1 has ≥3 KOs, so it is the **only computable per-fold Spearman**; the other 3 folds are null by construction. 11 of the 15 pooled points are HAP1's → the pooled statistic is essentially "can the public backgrounds predict HAP1's KO→loss ordering." The permutation null is **non-degenerate** (3000 distinct fitted slopes) and pooling avoids the p95=±1 small-n degeneracy — the wide, negative-centered null with p=0.88 is the *correct* behavior of an underpowered 1-informative-fold design.

**Excluding A375:** ρ = −0.9381, p = 0.8657, HAP1 fold = −0.9203 → **still FAIL**.

## 3. Code review — two real bugs + one design limit

1. **GENE MISLABEL (load-bearing).** `build_inventory.py` maps HeLa's TAPBPR/TAPBPL editor KO to condition `"TAPBP"` (essential, severity 0.80). The fit `loss ~ severity` over just 4 training points then places a severity-0.80 point at loss −0.14, forcing slope −0.0439 (inverted). Relabel as TAPBPR (severity 0.20) → slope +0.3088 (H4-consistent) → HAP1 transfer flips to +0.92. **Fix:** add TAPBPR/TAPBPL as an editor role, relabel the HeLa condition.
2. **DISJOINT-ALLELE CHECK NON-FUNCTIONAL.** `hla_overlap_leakage()` replaces only `,` with space before splitting, but genotypes are `;`-separated (`"HeLa;HLA-A*02;…"`). Each background collapses to one glued token → the check *always* reports "disjoint." (Prior agent blamed a 2-field/1-field mismatch; the true cause is the separator.) Biologically A375/THP-1/HeLa all share **HLA-A\*02** (and A375+HeLa share C\*06:02) → disjoint criterion genuinely fails. **Fix:** split on `[;,\s]`, normalize to 2-field.
3. **STRUCTURAL UNDERPOWER (design, not code).** Only 1 of 4 backgrounds has ≥3 KOs → 1 computable fold → the gate is a single-fold sign test until ≥2 backgrounds carry ≥3 KOs each.

No off-by-one in the LOO, no leakage of held-out peptides (feature is an HLA-agnostic gene prior), no silent-NaN denominator bug, Q.Value filter removed 0 rows (table pre-FDR'd), harness exits 0 (the "head exit code" note was a transient SIGPIPE, not a fault).

## 4. Sensitivity table

| scenario | pooled ρ | perm p | HAP1 fold | verdict |
|---|---|---|---|---|
| as-run, full 4 | −0.9312 | 0.883 | −0.9203 | FAIL |
| as-run, no A375 | −0.9381 | 0.866 | −0.9203 | FAIL |
| **HeLa label fixed**, full 4 | +0.0054 | 0.011 | **+0.9203** | FAIL (ρ<0.3, pulled to 0 by A375 B2M) |
| **HeLa label fixed**, no A375 | **+0.729** | **0.0007** | +0.9203 | **PASS** |
| hard-essentials only | — | — | uncomputable | FAIL/UNPROVEN |
| within-HAP1 H4 (severity→loss) | +0.9203 | — | — | H4 holds strongly within HAP1 |

## Final verdict

**Does FAIL reproduce?** Yes, exactly. **Is it robust?** Fragile on sign, robust on "cannot PASS."

The correct grounds for withholding a PASS are: only 1 informative fold (underpowered); the public backgrounds carry almost no dynamic range (all KOs retain 84–114%); the one public hard-essential replicate (A375 B2M) genuinely retains 88% vs HAP1's 3% — a **real** unexplained discordance; and alleles are not disjoint (A\*02 shared). The **stronger** "public data actively CONTRADICTS HAP1 (ρ=−0.92)" claim is **not supported** — that negative sign is an artifact of the TAPBPR→TAPBP mislabel and becomes +0.92 when corrected. The honest label is **UNPROVEN / underpowered**, not "contradicted."

**CRO implication (unchanged):** Cross-HLA generalization of H4 is NOT established on public KO-contrast data. The CRO must still supply ≥3 distinct HLA backgrounds × the hard-essential machinery-KO panel (B2M/TAP1/TAP2/TAPBP) + matched proteome + verified-complete KOs. Top priority is resolving the **A375 B2M-KO discordance** (leaky/incomplete KO vs genuine A\*02-background B2M-independent presentation vs DDA-depth artifact) — that real discordance, not the artifactual negative transfer, is the load-bearing failure.
