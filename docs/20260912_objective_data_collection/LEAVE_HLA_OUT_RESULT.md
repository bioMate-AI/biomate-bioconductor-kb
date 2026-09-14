# LEAVE-HLA-OUT GATE — RESULT (the decisive H4 cross-HLA test)

**Date:** 2026-09-13 · **Harness:** `leave_hla_out_gate.py` · **training_eligible = FALSE**
**Result JSON:** `LEAVE_HLA_OUT_RESULT.json` · **Gate rule:** `LEAVE_HLA_OUT_GATE.md`

## VERDICT: **FAIL_or_UNPROVEN_across_HLA** — and, stronger, **actively CONTRADICTED** on public data.

The H4 thesis (presentation controlled by antigen-processing **machinery state**, not source-protein
abundance) is **validated on ONE HLA background (HAP1)** and **does NOT transfer** to the public
KO-contrast backgrounds available. It is not merely underproven — the public data points the wrong way.

---

## 1. Data available vs. usable for THIS gate

| | count |
|---|---|
| HLA backgrounds in the corpus (H4_CORPUS_INVENTORY + HLA anchor) | **≥ 32** |
| …of which are WT-only (presentation diversity, **no KO↔WT contrast**) — do NOT feed this gate | most |
| **KO-contrast backgrounds with known HLA + usable processed peptide tables** | **4** |
| KO-contrast backgrounds that **ran** in the gate | **4** |

"≥32 backgrounds available" and "4 usable KO-contrast backgrounds for this gate" are **different numbers** — the gate needs a machinery-KO↔WT severity axis, which almost none of the 32 have.

### The 4 that ran

| background | deposit(s) | machinery KO(s) | matched proteome | presentation frac of WT |
|---|---|---|---|---|
| **HAP1** | PXD056426 | 11-gene APM panel | **yes** | B2M **0.03**, TAP2 0.17, TAPBP 0.24, TAP1 0.49, ERAP1 0.50 … |
| **A375** | PXD065279 (B2M) + PXD060572 (ERAP1) | B2M, ERAP1 | no | B2M **0.88**, ERAP1 0.99 |
| **THP-1** | PXD060575 | ERAP1 | no | ERAP1 0.85 |
| **HeLa** | PXD078020 | TAPBPR (TAPBPL) | no | TAPBPR **1.14** |

### Examined and EXCLUDED (no clean WT↔KO normalization here)
PXD024109 (ERAP2, SILAC — files are IP-antibody variants, no decodable WT/KO split) · PXD013064
(ERAP1 shRNA — mztab has no condition map) · PXD054491/494 (A375 ERAP1 — Spectronaut, no KEY;
redundant with A375) · PXD063219 (HeLaM B*44 TAPBPR — .msf, disk-heavy, redundant with PXD078020) ·
PXD020079 (class-II CIITA GBM — **raw MS only**, gate separately once normalized) · MSV000091285
(FTP transport-blocked).

---

## 2. The gate numbers

**Presentation measure:** within-deposit unique-peptide **detection-count fraction of WT**
(HLA-agnostic, batch-robust; NEVER raw cross-lab intensity). A375 B2M-KO cross-checked three ways —
detection 0.88 / summed-spectral 0.86 / intensity 0.65 — all agree the repertoire is **retained**.

| statistic | value | PASS needs |
|---|---|---|
| pooled leave-HLA-out transfer ρ | **−0.931** | ≥ 0.30 ✗ |
| permutation p (one-sided, 3000 perm) | **0.883** | ≤ 0.05 ✗ |
| backgrounds carrying a positive ordering | **0** | ≥ 3 ✗ |
| disjoint HLA alleles across folds | **no** (A\*02 shared by A375/THP-1/HeLa) | yes ✗ |

**All four PASS criteria fail.**

### Why ρ is strongly *negative*, not just ~0
Only HAP1 has ≥3 KO conditions, so it is the only computable held-out fold. Trained on
A375+THP-1+HeLa — where every machinery KO shows **~no presentation loss** — the fit learns a
**negative** severity→loss slope. Applied to HAP1, where severity genuinely predicts large loss, the
prediction is **anti-correlated (fold ρ = −0.92)**. The public backgrounds don't just fail to confirm
the HAP1 ordering; they teach the opposite one.

### Which background carries vs. breaks H4
- **Carries:** HAP1 only — the sole background where machinery-KO collapses presentation (B2M → 3%).
- **Breaks:** A375 (B2M-KO retains **88%**), THP-1 (ERAP1-KO 85%), HeLa (TAPBPR-KO **114%**).
- **Load-bearing failure:** the ONE public **hard-essential** replicate — A375 **B2M-KO** — is exactly
  the one that fails to collapse (HAP1 B2M-KO 3% vs A375 B2M-KO 88%; 55% of A375 B2M-KO peptides are
  even shared with WT). THP-1/HeLa only contribute **trimmer/editor** KOs (ERAP1/TAPBPR), whose weak
  or inverted "loss" is biologically expected and says little about the hard-essential claim. So the
  corpus is simultaneously **under-powered on the discriminative KOs** and **contradicted on its one
  hard-essential replicate**.

---

## 3. CRO-sizing implication — **the expensive path**

**FAIL / CONTRADICTED → the CRO MUST supply the missing cells.** Cross-HLA generalization of H4 is
not established (and is actively contradicted) on public KO-contrast data. The CRO must acquire:

1. **≥ 3 distinct HLA backgrounds** (disjoint alleles — the public set collapses onto A\*02),
2. × the **hard-essential machinery-KO panel** (B2M, TAP1, TAP2, TAPBP at minimum — the KOs that
   drive the collapse, not just ERAP1/TAPBPR trimmers/editors),
3. + **same-flask matched proteome** (for the beyond-abundance B1 metric),
4. + **absolute quant + MS-detectability censoring** (non-detection = censored, not zero),
5. with **verified-complete KOs** (Western/flow), because the A375 B2M-KO non-collapse must be
   resolved first: leaky/partial KO vs. MHC1-TIP method sensitivity vs. genuine A\*02-background
   B2M-independent presentation. That discordance — not statistical power — is the primary blocker.

The near-term CRO spend is **NOT shrinkable** on the strength of public data. Before committing, run
one **cheap diagnostic**: re-derive the A375 B2M-KO result with KO-completeness confirmation; if it is
a leaky KO, one background may be salvageable and the panel re-scoped.

---

## 4. Honesty notes
- Only HAP1 has ≥3 KO conditions → only its fold is computable; the pooled test is effectively "can
  A375+THP-1+HeLa predict HAP1" — it strongly cannot.
- Matched proteome only for HAP1 → B1 beyond-abundance for HAP1 only; others = presentation-loss
  transfer only (labeled).
- A375 is cross-method merged (MHC1-TIP DDA + DIA-NN); within-deposit normalization mitigates but does
  not erase method differences.
- The harness disjoint-allele check under-counts A\*02 sharing (2-field vs 1-field token mismatch);
  corrected here (verdict unaffected — already FAIL on ρ/p/count).
- Class-II (CIITA GBM) not runnable here (raw MS only); gate separately once normalized.
- Do NOT weaken thresholds to force a PASS. Acquire the missing hard-essential KO × HLA cells.
