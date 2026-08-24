# SNAT2 M1 — plan to generate the opposite (outward) state (2026-08-24)

Feasibility-gated plan for the one hard step of the SNAT2 application: generating the *outward-facing* state (the
second endpoint of the transport cycle) from the sister's inward structure. Built from two cited deep-dives
(AF2-based methods; diffusion/repeat-swap methods) done **before any run** — the discipline the OM-TPS episode
cost us. **Test-first gate is step zero (below).**

## Reframe (corrects earlier assumptions — both cited/verified)
1. **SNAT2 is a rocking-bundle (LeuT-fold / APC-superfamily) transporter, NOT an elevator.** ("Elevator" = SLC1/
   ASCT2.) Bundle = TM1,2,6,7; scaffold/hash = TM3,4,8,9; 5+5 inverted-topology internal repeats. **Good news:**
   the hardest thing to model (large elevator translations) is *not* our problem, and the **repeat-swap /
   internal-symmetry** literature applies directly. (Licht 2024 *Structure*; Lei 2018 SLC38A9.)
2. **No outward SLC38 template exists anywhere** — every solved SLC38 (SLC38A9 6C08/7KGV) is inward. So the outward
   state must be **built de novo and validated convergently** (no ground truth to TM-score against).
3. **Central risk = training-set memorization bias** (Montelione 2025): AF2/AF3 + enhanced-sampling variants tend
   to return only the PDB-present (inward) state *at high confidence with no warning*. pLDDT/PAE do **not** detect
   this. So no single generator is trustworthy.

## Recommended M1 route — ranked, with the winner being cheap + testable
**#1 (primary): Repeat-swap via ESM-flip → ESM-MODELLER** (Swapna/Montelione 2025, PLOS Comp Biol e1013590).
Build a *virtual flipped sequence* (swap N/C inverted-repeat halves) → run ESMFold to synthesize an
*opposite-state template* → drive MODELLER/AF with it.
- **Why most reliable:** deterministic; exploits SNAT2's real inverted-repeat symmetry; **does not require the
  model to have "seen" the outward state → immune to the memorization trap.** Same group that documented the AF
  memorization failure built this to beat it (ZnT8 outward @ 1.09 Å). Lineage: classic Forrest repeat-swap
  (LeuT 2008) was later **experimentally confirmed** (Krishnamurthy–Gouaux 2012).
- **Cheap + testable:** ESMFold + MODELLER on a single GPU/CPU, minutes–hour. No 1000-model GPU fleet.

**#2 (orthogonal cross-check): ConforFlux** (Boltz-2 backend, trunk-repulsion; 33%→75% dual-state on 12
transporters, leakage-controlled). Diffusion sampler that yields an ensemble containing the outward state.

**#3 (independent build): classic Forrest repeat-swap** (MODELLER + intra-domain Cα–Cα restraints) — a second,
mechanistically-different repeat-swap.

**Not primary:** AF2-MSA-subsampling / AFsample2 / SPEACH_AF (memorization-limited, ~50%); use only as a further
orthogonal vote, templates OFF.

**Standard of evidence = orthogonal convergence:** trust the outward model only if repeat-swap + ConforFlux (+ a
classic build) **agree** (low cross-method RMSD) and preserve the hard constraints.

## Hard constraints any outward model MUST preserve (verified)
- Na⁺ site: **TM1-Asn82 / TM8-Thr384** (Zhang & Grewer 2009).
- Extracellular **Cys245–Cys279** proximity (Chen 2016).

## Validation cascade (no ground truth — build a convergent case; pLDDT/PAE are NOT state evidence)
1. Repeat-swap self-consistency + hard constraints preserved.
2. **Cavity/tunnel (HOLE/MDpocket):** outward = extracellular vestibule open, inner gate closed (mirror-image of
   the inward pore profile we already computed).
3. Equilibrium **MD stability** in a membrane (stays outward, correct gate/hydration asymmetry).
4. **Coevolution (EVcouplings):** ECs unsatisfied by inward but satisfied by outward = orthogonal evidence.
5. Superpose on homolog **outward** structures (LeuT 3TT1, Mhp1 2JLN; Na⁺ site vs ApcT 3GIA/LeuT 2A65).
6. (headline) **string-method PMF** — outward is a true minimum connected to inward by a finite barrier.
7. (decisive future experiment) **DEER** — none exists for any SLC38; genuinely novel validation.

## ⛔ TEST-FIRST GATE (step zero — before touching SNAT2)
Per the hard rule: **prove the pipeline end-to-end on a KNOWN-answer transporter before running it on SNAT2 (unknown).**
- Pick a rocking-bundle transporter with **both** states solved (e.g., **LeuT** inward 3TT3 / outward 3TT1, or
  **LAT1**). Run the *exact* repeat-swap pipeline on its inward structure and check it **recovers the known outward
  state** (TM/RMSD to the deposited outward). This simultaneously: (a) tests every line of the code path end-to-end
  cheaply, (b) instruments/asserts each step ran, (c) proves the *output is genuinely a different, correct state*
  (not a copy — the exact check that would have caught the OM-TPS no-op), and (d) calibrates expected accuracy.
- **Only if the known-answer test passes** do we run it on SNAT2. If it can't recover a known outward state, the
  method isn't trusted and we stop — cheaply, before any SNAT2 spend.
- Compute for the whole gate: single GPU/CPU, ~hour, ~cents. No fleet, no speculative spend.

## Note — the density-steering idea (M6) is not dead as a *state* method
CryoBoltz (arXiv 2506.04490) already **flips a transporter's state with a density** (STP10) — it's the M6 idea
proven for *states* (not paths). If the sister provides the real `.mrc`, density-guided regeneration is a viable
*fourth* orthogonal generator / refinement — but its use with a *guessed* (non-experimental) density is untested.
Parked; the repeat-swap route needs no density.

## Change log
- **2026-08-24** — created from two cited deep-dives. Reframe: SNAT2 is rocking-bundle (tractable), no outward
  template (build+validate convergently), memorization bias is the central risk. M1 route: repeat-swap (ESM-flip)
  primary — cheap, deterministic, memorization-immune — + ConforFlux/classic-repeat-swap orthogonal; convergence
  is the standard of evidence. Test-first gate: reproduce a KNOWN inward→outward flip (LeuT/LAT1) end-to-end before
  any SNAT2 run.

## Test-gate progress (2026-08-24)
- ✅ **Known-answer reference established (LeuT 3TT3 inward → 3TT1 outward):** global CA RMSD 3.63 Å; motion is
  localized (58/492 residues >1 s.d.), dominated by **TM1a (res 11–21, up to 16.5 Å)** — the canonical
  rocking-bundle gate. This is the ground-truth "correct answer" the repeat-swap pipeline must recover, and it
  confirms the comparison code works (`research/snat2_state_call/leut_motion.py`). Featherweight (mdtraj, CPU).
- ⏳ **Remaining half of the gate — run the repeat-swap pipeline on 3TT3 and check it recovers 3TT1** — requires
  standing up the actual tools: repeat detection (CE-symm/SymD), model build (MODELLER, needs a free academic
  license key) and/or the ESM-flip route (ESMFold, one small GPU inference). That is a real, scoped setup — to be
  done deliberately (understand each tool first), not hacked. No SNAT2 run until this passes.
