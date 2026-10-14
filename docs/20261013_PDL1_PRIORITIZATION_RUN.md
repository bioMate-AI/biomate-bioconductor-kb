# PD-L1 G1 prioritization — cofold + MM-GBSA run

**Date:** 2026-10-13 · Ranking the 13 PD-L1 blockade candidates (+ verified control) before ordering, via the
canonical physics discriminator: Boltz-2 cofold (cyclic) into PD-L1 → MM-GBSA rescore on the shared ΔG scale.

## Run
- **Cofold:** RUNID `cofold-v2-5o45-20261014T004510Z`, instance `i-0bd69d0c648c706d3`, g5.2xlarge (A10G, on-demand
  — spot capacity-exhausted), TARGET=5o45 (PD-L1 IgV, chain R), NO_KERNELS=1, 14 peptides, 3h deadline, self-terminating.
- **Peptides:** G1-01..10 + K-01/02/05 + **CTRL-5O45-pep71** (A2 positive control = 5O45 native macrocyclic
  peptide-71, RCSB chain B `PHE-MEA-9KK-SAR-ASP-VAL-MEA-TYR-SAR-TRP-TYR-LEU-CCS-GLY`, canonical approx `FFKGDVFYGWYLCG`).
- **Receptor/control provenance:** PDB 5O45 (PD-L1 + macrocyclic peptide-71), RCSB-fetched — not fabricated.

## Honest caveats
- Boltz takes canonical 20-AA → ncAA fold as nearest canonical (2Nal→F, dP→P, NMe dropped). First-pass ranking
  approximation; the real-stereochem molecule is what gets ordered/assayed. (A4 full-stereochem scoring is a later refinement.)
- Cyclic-peptide docking/scoring is imperfect; the control anchors admissibility (A2) — if the pipeline does not
  rank CTRL-5O45-pep71 among the stronger binders, the candidate ranking is not trusted.

## Next (on cofold completion)
1. Verify fold: 14/14 CIFs + ipTM; control folded.
2. MM-GBSA pool: `DESIGNS_S3=.../complexes TARGET=5o45 bash launch_mmgbsa_pool.sh`.
3. Rank by ΔG (+ ipTM), validate control, select top candidates to order. Record in this doc.

## Status log
- 2026-10-14T00:45Z — cofold launched (on-demand A10G); monitoring.
- 2026-10-14T01:12Z — **cofold DONE, 14/14 folded** (incl. control). Boltz ipTM saturated-high (0.93–0.97) for
  all → not an affinity discriminator for small cyclic peptides; control folded cleanest (confidence 0.944).
  Summary saved `results/pdl1_cofold_summary.json`, complexes in S3. MM-GBSA is the ranking step.
- 2026-10-14T01:15Z — MM-GBSA pool launched `mmgbsa-pool-5o45-s0of1-20261014T011511Z` (g4dn/T4 on-demand,
  NS=0.5, standard single-chain runner — pocket-truncation αvβ6 bug N/A here); monitoring.
- 2026-10-14T01:45Z — **MM-GBSA DONE, 14/14 OK.** `results/pdl1_mmgbsa_results.json`.

## Result — MM-GBSA ΔG ranking (A2 PASS: control #2 of 14)
| rank | design | ΔG (kcal/mol) | note |
|---|---|---|---|
| 1 | PDL1-K-05 | −39.86 | beats control |
| 2 | **CTRL-5O45-pep71** | **−34.22** | **positive control (known binder) — validates pipeline** |
| 3 | PDL1-G1-06 | −31.18 | top new candidate |
| 4 | PDL1-G1-03 | −30.53 | top new candidate |
| 5 | PDL1-G1-09 | −30.26 | top new candidate |
| 6 | PDL1-G1-04 | −27.66 | |
| 7 | PDL1-G1-05 | −25.46 | |
| 8 | PDL1-G1-01 | −24.70 | |
| 9 | PDL1-G1-08 | −23.52 | |
| 10 | PDL1-G1-07 | −22.94 | |
| 11 | PDL1-G1-02 | −20.67 | |
| 12 | PDL1-K-02 | −19.83 | prior, weak |
| 13 | PDL1-K-01 | −16.92 | prior, weak |
| 14 | PDL1-G1-10 | −14.98 | weakest |

**A2:** control ranks #2 and the scale separates a top tier (−30 to −40) from a weak tail (−15 to −20) → ranking is admissible.
**Caveats:** (1) canonical-backbone approximation (ncAA→canonical) → ΔG is a *relative* prioritizer, not absolute
affinity; (2) single short MD (0.5 ns, 1 trajectory) → differences within ~3 kcal/mol (e.g. G1-06/03/09) are a tie-tier, not a strict order; (3) ground truth = the PD-1/PD-L1 competition assay.

## Prioritized order (recommendation)
Order the control + the top tier at/near the control's affinity: **CTRL-5O45-pep71, PDL1-K-05, PDL1-G1-06,
PDL1-G1-03, PDL1-G1-09** (optionally PDL1-G1-04). Drop the weak tail (G1-10, K-01, K-02, G1-02, G1-07). Synthesize
with FULL stereochemistry (the real [2Nal]/[dP]/[NMe] molecule, not the docking backbone) + the BMS control.

## Gate-applied revision (2026-10-14, after external review)
A review flagged (correctly) that the ranking scored before gating and is fooled by hydrophobicity, and
(incorrectly) that candidates fail P3 for "no Lys chelator handle." **P3 handle is N/A — PD-L1 is a BLOCKER**
(no DOTA/radiometal), so absence of a Lys is not a defect (spec A11). Applying the *correct* gate — the
developability/hydrophobicity guard (A10) — the di-2Nal candidates are greasy docking artifacts:
| ID | ΔG | 2Nal | meanH (FP) | verdict |
|---|---|---|---|---|
| PDL1-K-05 | −39.86 | 0 | 0.60 | **ADVANCE** (cleanest) |
| PDL1-G1-09 | −30.26 | 0 | 0.61 | **ADVANCE** |
| PDL1-G1-06 | −31.18 | 0 | 1.00 | optional — greasy / 2×Trp (oxidation+aggregation risk) |
| PDL1-G1-03 | −30.53 | 2 | 0.85 | DROP — greasy (2×2Nal) docking artifact |
| PDL1-G1-04 | −27.66 | 2 | 0.96 | DROP — greasy (2×2Nal) docking artifact |

Revised order (`docs/20261014_PDL1_ORDER.xlsx`): **K-05 + G1-09** advance, **G1-06** optional, di-2Nal dropped.
Review's P3-handle objection rejected (stale radioligand premise). Still pending before final commit (P1/P2/P4):
per-pose groove-occupancy check + PD-L2 counter-score.

## Groove-occupancy check (P2, 2026-10-14) — PASS for both advance candidates
Metric: the native control pose (5O45 peptide-71) defines the validated PD-1-binding groove = the 15 receptor
residues it contacts (ILE38,TYR40,TRP41,GLU42,ASN47,ILE48,ILE49,GLN50,VAL60,MET99,ILE100,SER101,ALA105,ASP106,TYR107).
Overlap of each candidate's receptor-contact set with that groove (poses from the 5o45 cofold):
| candidate | groove overlap | aromatics buried | verdict |
|---|---|---|---|
| PDL1-K-05 | 14/15 = **93%** | 2/3 | binds the same groove as the known binder — clean |
| PDL1-G1-09 | 11/15 = **73%** | 2/2 | genuinely in the groove, slightly less complete |
Both occupy the real PD-1-binding hydrophobic groove (not an off-surface artifact). P2 (pose) satisfied.

## PD-L2 counter-score (P4) — in progress
Cofold `cofold-v2-pdl2-20261014T035108Z` (PD-L2 IgV, Q9BQ51) of K-05 + G1-09; MM-GBSA to follow. Selectivity =
ΔG(PD-L1) − ΔG(PD-L2); want PD-L1 clearly stronger. Results appended when the run completes.

## PD-L2 counter-score (P4) — DONE (2026-10-14): K-05 selective, G1-09 fails
Selectivity = ΔG(PD-L1) − ΔG(PD-L2); more negative = more PD-L1-selective. (`results/pdl1_pdl2_counter_mmgbsa.json`)
| candidate | PD-L1 ΔG | PD-L2 ΔG | gap | ipTM PD-L1→PD-L2 | PD-L2 contacts | verdict |
|---|---|---|---|---|---|---|
| PDL1-K-05 | −39.86 | −24.59 | **−15.3** | 0.97→0.37 | 18→11 | **PASS — PD-L1-selective** |
| PDL1-G1-09 | −30.26 | −25.90 | −4.4 (noise) | 0.97→0.63 | 16→18 | **FAIL — not selective vs PD-L2** |

## FINAL verdict — one fully-gated lead
**PDL1-K-05** clears every gate: top PD-L1 ΔG (−39.86), cleanest developability (0 × 2Nal, meanH 0.60),
93% groove occupancy vs the validated control pose, and ~15 kcal/mol PD-L1-over-PD-L2 selectivity on three
independent signals. **Order K-05.** G1-09 is dropped on selectivity (its PD-L1 binding is real — a redesign
candidate, not an order candidate). Caveats stand: relative (not absolute) ΔG on canonical-backbone approx;
confirm K-05 by PD-1/PD-L1 competition + a PD-L2 counter-assay (and FEP if desired) before trusting magnitudes.
