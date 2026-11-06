# MM-GBSA verify oracle — first within-target physics ranking of BoltzGen designs

The generate→**verify** loop, closed with a real physics number. Fully-automated pipeline built this
session: BoltzGen design → gemmi split → **psfgen head-to-tail cyclic build** (the breakthrough, 5
smokes to solve) → OpenMM GBn2 implicit minimize → single-trajectory MM-GBSA (peptide vs receptor by
coordinate slice). Runs on CPU, no manual CHARMM-GUI, FF cached in our S3. Code:
`research/guangzhou_all_atom/peptide_mmgbsa_run.sh`.

## Result — all 8 `1yf4` (kallikrein) designs ranked by ΔG (minimized single-point, GBn2/CHARMM36m)
| physics rank | design | sequence | ΔG (kcal/mol) | ring closed | BoltzGen rank |
|---|---|---|---|---|---|
| 1 | rank6_1yf4_5 | `FSRNVGDPY` | **−52.7** | ✅ | 6 |
| 2 | rank3_1yf4_2 | `SFEASGFAPM` | −43.3 | ✅ | 3 |
| 3 | rank2_1yf4_6 | `SSLLFVPG` | −42.4 | ✅ | 2 |
| 4 | rank4_1yf4_0 | `SIYGTGLVPL` | −40.2 | ✅ | 4 |
| 5 | rank2_1yf4_1 | `SPSINGPMI` | −39.7 | ✅ | 2 |
| 6 | rank1_1yf4_3 | **`GSGLLKS`** | −36.6 | ✅ | **1 (BoltzGen top)** |
| 7 | rank7_1yf4_4 | `YVAGQPDPK` | −35.7 | ✅ | 7 |
| 8 | rank5_1yf4_7 | `YSGGGGV` | −24.3 | ✅ | 5 |

## The finding that matters: physics disagrees with the ML generator
BoltzGen's **#1** design (`GSGLLKS`, iptm-ranked) is only **6th** by physics MM-GBSA; the physics
favorite (`FSRNVGDPY`, −52.7) was ranked 6th by BoltzGen. **This is precisely the value of a
non-circular oracle** — an independent physics check that surfaces designs the ML under-ranked, rather
than re-confirming the generator's own scoring. If we had trusted iptm alone we'd have carried the
wrong design forward.

## Honest caveats (this nominates, it does not decide)
- **Single-point minimized MM-GBSA, entropy omitted** — a *relative ranking* oracle (Sun PCCP 2019
  rₚ≈0.75 for short peptides), not absolute affinity.
- **Residual size bias**: designs vary 7–10 residues; MM-GBSA trends more-negative with size, so the
  ranking is not fully length-controlled. `FSRNVGDPY` (9-mer, −52.7) vs `GSGLLKS` (7-mer) is partly size.
- Therefore: treat the top group (`FSRNVGDPY`, `SFEASGFAPM`, `SSLLFVPG`) as **FEP candidates**, not a
  verdict. FEP (ATM/FEP+, ~1 kcal/mol) is the arbiter for the finalists.

## Why this is the deliverable of the verify thread
- The **automated cyclic-peptide MM-GBSA pipeline works end-to-end** (the hard psfgen ring-build problem
  is solved and cached-FF robust).
- It produced the **first independent physics ranking** of our designs, and it **materially disagrees**
  with the generator — the loop now has a real, non-circular selection signal.

## Cross-target coverage (all 4 targets, 2026-09-18)
Ran the validated pipeline on all 4 v5 targets (8 designs each = 32 scored). **All 32 rings closed**
(incl. Pro-containing 1u8p/1csb — confirming psfgen cyclization is robust; earlier "ring open" flags were
the crude bonds==atoms artifact, not real).

**Robust finding — physics reorders the generator on EVERY target:** BoltzGen's #1 (top-iptm) design
lands 5th–7th of 8 by MM-GBSA ΔG on all four:
| target | receptor | BoltzGen #1 | its MM-GBSA rank | MM-GBSA #1 |
|---|---|---|---|---|
| 1yf4 | kallikrein | GSGLLKS | 6 | FSRNVGDPY |
| 1u8p | antibody Fab | GRYSPSG | 6 | SSSFGPG |
| 1kc4 | toxin-scaffold | SGGVVVATSGIVGV | 7 | SALGVVANGPII |
| 1csb | cathepsin B | TIRVPRTFQVPG | 5 | SRYTTMGSGWSIAFG |

The single-target observation is now a **consistent pattern across 4 diverse receptors** — relying on
iptm alone would systematically advance physics-suboptimal designs.

**Honest caveat (still holds, now cross-target):** MM-GBSA has a size bias — the physics-#1 designs tend
to be the *longer* ones (more contacts → more negative ΔG; e.g. 1csb's 15-mer at −65.9). So within-target
ranking is still length-confounded, and neither iptm-alone NOR MM-GBSA-alone is sufficient → the
multi-objective + length-aware + FEP funnel is the right call, exactly as designed.

**Enables the LEARN step:** 32 MM-GBSA-scored designs is now a usable dataset to train an active-learning
surrogate (design features → ΔG) for the iterating loop.

## Next
1. **LEARN step** — active-learning surrogate on the 32-design dataset (design features → MM-GBSA ΔG) to
   pre-screen larger batches cheaply before expensive MM-GBSA.
2. **FEP finalist tier** on the top physics candidates (length-controlled arbiter).
3. **Register the workflow in BioMate** (productionize, per docs/BIOMATE_CLOSED_LOOP_INTEGRATION.md).
