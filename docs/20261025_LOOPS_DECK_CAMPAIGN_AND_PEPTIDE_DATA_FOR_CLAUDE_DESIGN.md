# Loop B (Rounds / campaign) data (for Claude Design)

**Date:** 2026-10-25. **For:** Claude Design — one campaign + one peptide round to fill the
Rounds / campaign screens. **The peptide round is REAL** (αvβ6 loop output); the small-molecule
campaign is schema-grounded illustrative (shown as example). Narration: the loops deck.

---

## A. Peptide round — REAL data (αvβ6 cyclic peptides)
Source: `research/guangzhou_all_atom/cyclic_llm/target_kb/avb6_loop_result.json` (target αvβ6 / PDAC;
one DBTL round: generate → gate → Pareto-select; 5 gated). All carry the **RGD** binding motif;
all pass the rule gate + developability; all are **novel vs patents (FTO: outside)**.

**Round 1 · 5 designed & gated cyclic peptides** (sequence · mean hydrophobicity · net charge · liabilities · FTO):
| # | HELM sequence | meanH | charge | liabilities | FTO |
|---|---|---|---|---|---|
| 1 | `cyclo(F-R-G-D-L-G-[2Nal]-[dP]-[NMeK])` | 0.47 | +1 | none | novel (outside, id 0.89) |
| 2 | `cyclo(F-R-G-D-L-A-[2Nal]-[dP]-[NMeK])` | 0.51 | +1 | none | novel (outside, id 1.0) |
| 3 | `cyclo(F-R-G-D-L-A-[Phe4F]-[dP]-[NMeK])` | 0.41 | +1 | none | novel (outside, id 1.0) |
| 4 | `cyclo(F-R-G-D-L-A-[Phe4Cl]-[dP]-[NMeK])` | 0.42 | +1 | none | novel (outside, id 1.0) |
| 5 | `cyclo([2Nal]-R-G-D-L-A-[Phe4F]-[dP]-[NMeK])` | 0.52 | +1 | none | novel (outside, id 1.0) |
Note the non-canonical residues (`[2Nal]`, `[dP]` = D-Pro, `[NMeK]` = N-methyl-Lys, `[Phe4F/4Cl]`) —
show them; they're the point (chemistry AF3/Boltz can't design).

**Round 1 · Test / Analyze** (the physics + assay step — *illustrative, method-consistent* example
values for the "measured" column; the real `binding_dG` was pending in this trace):
| # | Boltz-2 cofold iPTM | MM-GBSA ΔG_bind (kcal/mol) | availability (Landry) | PAMPA logPe | FP binding Kd |
|---|---|---|---|---|---|
| 2 | 0.71 | −42.3 | 0.63 (ok) | −5.8 | 0.9 µM |
| 5 | 0.68 | −39.8 | 0.58 (ok) | −6.1 | 1.4 µM |
| 3 | 0.66 | −37.1 | 0.61 (ok) | −5.9 | 3.2 µM |
→ **Select** #2, #5 (best ΔG + availability) → **Diffusion-DPO** pairs (chosen: 2,5 / rejected: 3,4)
retrain the generator → **Round 2** proposes tighter analogs around #2's scaffold.

## B. Small-molecule campaign — illustrative (schema-grounded)
Campaign object fields (real schema, `auto_proposals`): `round_number`, `proposed_smiles`, `scores`,
`confidence_intervals`, `ad_statuses`, `triggered_by`.

**Campaign:** "JAK1 lead-opt" · target **JAK1** · indication **rheumatoid arthritis** · objective **balance**.

**Round 1 · seed set** (3 compounds; per-objective scores — never a blended number):
| compound | SMILES | pIC50 (±CI) | QED | SA | DILI | hERG | AD |
|---|---|---|---|---|---|---|---|
| C1 | `CC(=O)Oc1ccccc1C(=O)O` | 5.8 (±0.4) | 0.56 | 2.1 | 0.31 pass | 0.08 pass | in-domain |
| C2 | `CN1C=NC2=C1C(=O)N(C(=O)N2C)C` | 5.2 (±0.5) | 0.54 | 2.3 | 0.21 pass | 0.05 pass | in-domain |
| C3 | `CC(C)Cc1ccc(C(C)C(=O)O)cc1` | 6.1 (±0.3) | 0.61 | 2.0 | 0.49 pass | 0.07 pass | in-domain |
**Ingest assay** (`INGEST_ASSAY`, measured vs predicted): C3 measured pIC50 **6.3** (predicted 6.1 ✓);
C1 measured **5.6** (predicted 5.8). Refit GP → `triggered_by: auto_retrain`.

**Round 2 · GP-proposed analogs** (3 new, scores improved; mark SMILES as generated example):
| compound | pIC50 (±CI) | QED | SA | DILI | hERG | AD | note |
|---|---|---|---|---|---|---|---|
| C3-a1 | 7.0 (±0.3) | 0.64 | 2.4 | 0.38 pass | 0.09 pass | in-domain | C3 scaffold, +0.7 pIC50 |
| C3-a2 | 6.8 (±0.4) | 0.62 | 2.6 | 0.41 pass | 0.11 pass | in-domain | — |
| C3-a3 | 6.6 (±0.5) | 0.59 | 3.1 | 0.55 **flag** | 0.08 pass | edge | DILI flagged → kept visible with reason |

**Show:** round-over-round progression (R1→R2), **per-objective columns kept separate** (no composite),
**measured-vs-predicted** tags, **lineage** (each R2 analog traces to its R1 parent), rejected/flagged
candidates stay visible with the reason.

---
**For Design:** peptide table A = real (use as-is); the A "measured" sub-table and campaign B are
**illustrative example values** (correct units/shapes/method) — show as example data, swappable for a
real run later. Keep non-canonical residues visible; keep per-objective scores separate; show the
close-back (assay → refit/DPO → next round) as the loop.
