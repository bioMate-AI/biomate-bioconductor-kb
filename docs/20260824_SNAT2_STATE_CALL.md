# SNAT2 state call — step 1 of the application (2026-08-24)

First substantive analysis on the sister's actual structure (`SNAT2_cryoEM_stateA_3.0A.pdb`, chain A, res 67–500,
apo, no ions). Goal: confidently call the conformational state (inward-open / outward-open / occluded) — the
"step zero" needed before modeling the transport cycle. Analyses in `research/snat2_state_call/` (lightweight,
transparent mdtraj/numpy; run in `omtps-core`).

## Result
**✅ Confident: single-gate-open state — NOT occluded.** A HOLE-style pore profile centered on the N82/T384
Na⁺/substrate site (`pore_state_call.py`) is clearly asymmetric along the membrane normal (PA3): one side opens
fully to bulk solvent (pore clearance → 12 Å), the other is closed (~1–2 Å). This is a clean transport-cycle
**endpoint** — exactly what we want as one of the two states.

**❌ Inconclusive from the fitted PDB: inward vs outward.** Three independent lightweight orientation methods are
weak or contradictory:

| Method | call | why not decisive |
|---|---|---|
| TM-align to SLC38A9 6C08/7KGV (earlier state-ID) | weakly inward | ΔTM = 0.01 (within noise); whole-protein TM-score can't distinguish states — the fold is near-identical, difference is local to the gates |
| Positive-inside rule (`orient.py`) | weakly "open side = cytoplasm" (→inward) | net charge +5 (open) vs +4 (closed) — essentially tied |
| Terminus topology (`term.py`, SLC38 termini cytoplasmic) | contradictory | **invalid here**: SNAT2's cytoplasmic N-tail (~1–66) is unmodeled, so res 67 is mid-protein, not a terminus — N-"term" landed on the open side, C-term on the closed side |

Over-calling this "inward" (as earlier docs leaned) is not warranted.

## What resolves it (cleanly)
1. **Ask the sister** (fastest, authoritative): which side is open + the capture conditions. She solved it; the
   state is central to her interpretation — this is "only-she-can-provide" info and settles it in one sentence.
   Draft question below.
2. **Rigorous computational route** (if needed): HOLE + OPM/PPM membrane embedding + a proper cross-species
   *scaffold* superposition onto SLC38A9 (compare which gate is open, not whole-protein TM-score). Set up with the
   tools understood first.

## Implication for the plan
- We now have **one clean endpoint** (a single-gate-open state) — good.
- To model the transport cycle we still need: (a) confirm this endpoint's **direction** (inward/outward), and
  (b) **generate the other endpoint** (the opposite-facing state) — the M1 step, not yet run on SNAT2.
- The raw `.mrc` map + capture conditions (the standing external ask) would resolve the direction immediately and
  anchor the modeling.

## Draft question to the sister (resolves the state call in one line)
> "For your SNAT2 cryo-EM structure — which side is the substrate cavity open to: the cytoplasm (inward-open) or
>  the extracellular/lumen side (outward-open), or is it occluded/closed both sides? And what were the sample
>  conditions (apo vs with substrate/Na⁺, pH)? I've confirmed computationally it's a single-gate-open state but
>  can't tell inward vs outward from the fitted coordinates alone — your call on the state settles it."

## Change log
- **2026-08-24** — created. Pore profile → single-gate-open (not occluded), a clean cycle endpoint; inward-vs-outward
  not confidently callable from the fitted PDB (3 heuristics weak/contradictory; res-67 ≠ true N-terminus gotcha);
  resolve via the sister/density. Next: confirm direction + generate the opposite endpoint (M1).
