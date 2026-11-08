# Updated candidate sequences v2 (edit-guideline fixes, re-gated)

**Date:** 2026-10-13 · Applies the flexible Tier-2 **edit-guidelines** to the v1 knowledge-grounded sets to
fix every liability/FTO flag while preserving the Tier-1 pharmacophore, then **re-gates** (liability + genus
FTO) to prove each fix. Generator: `research/guangzhou_all_atom/make_updated_sequences_v2.py`. Artifacts:
`results/knowledge_grounded_candidates_v2.json` (αvβ6), `results/knowledge_grounded_pdl1_v2.json`.
Honesty: these remain **design hypotheses** — physics (MM-GBSA on 9xmm/5O45) + wet-lab still required; v2
only proves the liability/FTO axes are now clean, not that they bind.

## αvβ6 v2 — 10/10 PASS, 0 FTO-occupied (was 8 PASS / 2 WATCH / 1 FTO-drop)
| id | v2 backbone | net | genus id | edit applied |
|---|---|---|---|---|
| AVB6-K-01 | FRGDLSWPA | 0 | 0.667 | — (lead-tier, unchanged) |
| AVB6-K-02 | WRGDLTFPV | 0 | 0.667 | — |
| AVB6-K-03 | YRGDLGHPL | 0 | 0.667 | — |
| AVB6-K-04 | HRGDLAWPE | −1 | 0.667 | **renal:** NMeLys→NMeGlu (net +1→−1, lower kidney dose) |
| AVB6-K-05 | FRGDLIFPA | 0 | 0.778 | — (extended-affinity RGDL-I) |
| AVB6-K-06 | RGDLQFPSG | 0 | 0.444 | — |
| AVB6-K-07 | LRGDLSFPT | 0 | 0.667 | — |
| **AVB6-K-08** | **YRGDLIWPA** | 0 | 0.667 | — (**LEAD**: PASS + extended-affinity + FTO-clean) |
| AVB6-K-09 | WRGDLTHPE | −1 | 0.556 | **FTO:** diversified off avebehexin (genus 0.889→0.556) + NMeGlu |
| AVB6-K-10 | WRGDLSYPA | 0 | 0.667 | **renal:** Lys→Ser (net +1→0); corrects the backwards v1 rationale |

All retain RGD·L + D-Pro/N-methyl lock (Tier-1). The two FTO-/renal-liable v1 members (K-09 genus hit;
K-04/K-10 cationic) are fixed; K-05 sits at 0.778 genus (just under the 0.80 cutoff) — FTO-watch, keep.

## PD-L1 v2 — 7 PASS / 1 WATCH / 0 HOLD (was 3 PASS / 4 WATCH / 1 HOLD)
| id | v2 backbone | tier | edit applied |
|---|---|---|---|
| PDL1-K-01 | FWLPYSFDTK | PASS | — |
| PDL1-K-02 | WLFPILSEKG | PASS | **oxidation:** Met→Leu (prod = Nle isostere) |
| PDL1-K-03 | YFPWLASDRTG | PASS | **isomerisation:** Asp-Ser→Ser-Asp (removes D-S hotspot) |
| PDL1-K-04 | FLWPLYSKGD | PASS | **HOLD-fix:** reorder K-D-G→K-G-D (removes Asp-Gly) + Met→Leu |
| PDL1-K-05 | WYFPLITENKSG | PASS | — |
| PDL1-K-06 | FWLYPLSDKT | PASS | **oxidation:** Met→Leu |
| PDL1-K-07 | FWPYILFERS | PASS | — |
| PDL1-K-08 | CFWTYFLSDC | WATCH | Met→Leu + one L→T (hydrophobic 0.80→0.70; disulfide dmp10-style, residual aggregation watch) |

PD-L1 remains structure-gated (no linear motif) — v2 clears the CMC liabilities; docking vs the 5O45 IgV
cleft is still the decisive gate.

## What v2 demonstrates
This is the Tier-2 edit-guideline layer working end-to-end on real candidates: each fix is a named medicinal-
chemistry transformation (renal charge, Met-oxidation, Asp-isomerisation, FTO-diversification) applied to a
specific position, preserving the hard pharmacophore, and **verified by re-gating** (0 HOLD, 0 FTO-occupied).
Replacements use canonical surrogates (Met→Leu) so the gate/FTO tooling can parse them; the production
molecule would use the exact isostere (Nle) noted per candidate.

**Still pending (unchanged):** physics scoring (cofold→MM-GBSA on 9xmm/5O45) and wet-lab — v2 improves the
*developability/FTO* axes, not the *binding* axis, which only physics + assay resolve.
