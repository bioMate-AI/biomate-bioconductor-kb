# Extending the engine to other drug modalities — a plug-in map (2026-09-20)

Design note (no new compute; architecture + honest boundaries). The cyclic-peptide
generate→verify→select→redesign engine is **structure-centric**: the verify and select layers consume
target–ligand *structures*, not chemistry-specific objects. So any generator that emits a target-conditioned
complex structure can feed the same downstream pipeline. Extending to a new modality = wiring **three
plug-in points**, not rebuilding the engine.

```
GENERATE ──(plug-in A: generator/protocol)──► complex structure
   │
   ▼
VERIFY  ──(plug-in B: ligand force field)───► physics ΔG  (MM-GBSA framework is universal)
   │
   ▼
SELECT  ──(plug-in C: developability oracle)─► binding × developability Pareto  (machinery is universal)
   │
   ▼
REDESIGN → re-VERIFY   (methodology ports; the specific lever is per-modality)
```

## Plug-in A — generator / protocol
BoltzGen (adopted) is already a "one backbone, per-modality plugin" model (the UniMoMo / Boltz-2 direction).
Demonstrated here: protein protease target (1yf4) and antibody Fab paratope target (1u8p) — same protocol.
- **Protein / antibody binders:** same BoltzGen protocol. Cheapest extension.
- **Small molecules:** swap in an all-atom SBDD generator (TargetDiff-successors, flow-matching).
- **PROTAC / molecular glue:** ternary-complex generation (harder; emerging).

## Plug-in B — ligand force field (the real per-modality work in VERIFY)
The MM-GBSA decomposition `ΔG = E_complex − E_receptor − E_ligand` is modality-agnostic; only ligand
parametrization changes. Our pipeline (`peptide_mmgbsa_run.sh`, psfgen + OpenMM GBn2, CHARMM36m) already
parametrizes proteins on the receptor side — so:

| modality | ligand FF plug-in | difficulty vs cyclic peptides |
|---|---|---|
| protein / antibody binder | **same** CHARMM protein FF; no `CYCP`/`NMET` patch | **easier** (it's what the receptor side already does) |
| linear / cyclic / N-methyl peptide | protein FF + our `CYCP` (cyclize) / `NMET` (N-methyl) patches | **done** |
| small molecule | GAFF2/CGenFF + AM1-BCC charges (openff `SystemGenerator`) | new plug-in — same `sqm`/openff toolchain that broke the 2-env run (finicky, not free) |
| PROTAC / molecular glue | hybrid small-mol + protein FF, ternary complex | hardest |
| nucleic acid (aptamer/siRNA) | CHARMM36 nucleic-acid FF | moderate |

## Plug-in C — developability oracle (swap the axis in SELECT)
The multi-objective Pareto (`perm_generation_v3.py`, `perm_redesign_v1.py`) is shared; the developability axis
changes per modality:
- **cyclic peptide:** permeability (backbone-donor / N-methylation lever — our v1–v3) + proteolytic stability.
- **small molecule:** ADMET (hERG, CYP, solubility, oral bioavailability) — **already a BioMate workflow set**;
  route the small-molecule modality's developability through BioMate.
- **antibody:** aggregation, immunogenicity, viscosity, PK/developability index.
- **nucleic acid:** nuclease stability, delivery/uptake.

## What ports and what does NOT
- **Ports (methodology):** oversample → physics-verify → multi-objective select → structure-grounded redesign
  at non-interface positions → re-verify. Modality-independent.
- **Does NOT port (specifics):** the permeability science (v1 headroom, `NMET` N-methyl patch, v2/v3) is
  cyclic-peptide-specific — backbone N-methylation is a peptide lever. Each modality brings its own
  developability lever and its own redesign move.

## Cross-modality lessons (already established here — apply to every modality)
1. **Always physics-verify.** The generator's own confidence (BoltzGen iptm) is orthogonal to physics ΔG
   (Spearman −0.04; re-confirmed 3× incl. v3, where iptm-based selection gave up ~9 kcal/mol of real binding).
   This is a property of learned generators, not of peptides — it will bite any modality that ranks on
   self-confidence.
2. **MM-GBSA is a relative ranking oracle with real limits** (size bias; cannot score large perturbations —
   it failed on N-methylation). **FEP is the arbiter across all modalities.**
3. **Small-molecule parametrization (AM1-BCC/`sqm`) is the fussy bit** — budget for it; it is the toolchain
   that repeatedly broke this session.

## Honest status
Demonstrated: **cyclic peptides** end-to-end (+ an antibody *target*, but with a peptide *ligand*).
Architecturally supported but **not yet validated by us**: small-molecule, antibody-ligand, PROTAC, nucleic
extensions. Each needs its plug-ins B/C wired **and its own benchmarking** — the framework invites the
extension; it does not grant it for free. The cheapest first extension is protein/antibody binders (plug-in B
is trivial — reuse the protein FF); the highest-leverage is small molecules via BioMate's existing ADMET.

See `PERMEABILITY_DRIVEN_GENERATION.md` (the peptide instance of this pattern) and `MANUSCRIPT.md` §3.2/§3.7/§3.9
(the physics-verification lessons that generalize).
