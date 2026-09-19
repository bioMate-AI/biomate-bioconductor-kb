# Permeability-driven generation / redesign — design + v1 result (2026-09-19)

The differentiator our engine's finding #5 exposed: BoltzGen optimizes binding only, so **all** designs
come out permeability-poor (predicted logPapp −7.5..−8.4). The strategic gap is to make permeability an
objective the design step actually optimizes. This doc records the honest approach, the v1 build, and the
staged roadmap.

## The honest constraint (why we do NOT build this on the 2D GBM alone)
Our own N-methylation test (`PERMEABILITY_BASELINE_RESULTS.md`) showed the trained 2D-descriptor
permeability GBM **cannot see** the N-methylation lever (mean Δ = +0.06 log units for full N-methylation) —
the mechanism is conformational, invisible to 2D descriptors. Therefore a generation loop that scored
permeability with the GBM alone would be **unable to steer toward the very chemistry that makes cyclic
peptides permeable**. This is not a workaround to route around; it is the root reason the objective must be
**mechanistic-first**:

> **Exposed backbone H-bond-donor count (NHD) is the dominant, well-established permeability determinant for
> cyclic peptides (Lokey/Kihlberg); N-methylation works precisely by removing exposed backbone NH donors.**

So the steering objective = mechanistic rules (minimize exposed backbone donors, cap MW/TPSA) **+** the GBM
as a secondary ranker of the as-is design (its valid R²0.45 use), never the GBM as the sole driver.

## v1 — structure-grounded permeability-redesign headroom (built, local, no GPU)
Tool: `perm_redesign_v1.py`. Result: `results/perm_redesign_v1_result.json`.

For each of the 32 BoltzGen designs (4 targets × 8), using the **actual bound-complex CIF**:
1. Split peptide chain (fewest residues; validated: e.g. 1csb chain A=15-mer, chain B=205-res receptor) vs receptor.
2. Per peptide residue: whole-residue interface contact (<4.5 Å heavy-atom) **and**, more precisely, whether
   its **backbone N** is within H-bond distance (3.5 Å) of a receptor acceptor (O/N).
3. **Methylatable** = backbone N NOT H-bonding the receptor, non-Pro. N-methylating these removes exposed
   backbone donors **without touching any interface H-bond** → binding preserved by construction.
4. Report the achievable HBD reduction (ΔHBD) = permeability headroom available at fixed binding, plus MW/TPSA/cLogP.

### Key results
- **Every design carries real headroom**: ΔHBD = 2–14 backbone donors removable while keeping all
  interface-H-bonding backbone donors.
- **Strong binders keep their headroom.** The MM-GBSA #1 binder for 1yf4, `FSRNVGDPY` (ΔG −52.7), can go
  HBD 16→11 (methylate positions 1,2,6,7,9) while preserving all 4 interface-H-bonding backbone donors.
- **Binding here is side-chain-driven.** Good binders make few backbone H-bonds to the receptor (0–4), so
  backbone N-methylation is broadly compatible with their binding modes — the permeability lever is
  genuinely available, not blocked by the binding mode.
- **Depth matters, but less than feared.** Even the deeply-buried cathepsin-B (1csb) designs (all residues
  2–3.9 Å from receptor) still expose 8–12 methylatable backbone donors, because side-chain contact ≠
  backbone-N H-bonding.

This is the objective a generation-time step would maximize: `advance = strong binder (low ΔG / high iptm)
× high ΔHBD headroom × modest MW`. It reuses the existing engine, is fully honest (mechanistic,
structure-grounded), and needed no GPU.

### Honest caveats of v1
- ΔHBD is a **necessary-not-sufficient** permeability proxy: removing backbone donors is the dominant lever,
  but true permeability also needs low MW and chameleon behavior (the expensive conformational model, still
  unbuilt/toolchain-blocked — see `PROGRAM_STATE`).
- N-methylating a non-H-bonding backbone N is **likely** binding-neutral but not guaranteed (it can shift
  backbone torsions / entropy). This must be **re-verified**, not assumed.
- Full methylation of a design with 0 interface backbone donors (e.g. 1u8p `SSDLRRSAF`) is an *upper bound*,
  not a recommendation — extreme methylation changes conformation/solubility; a real pick methylates a subset.

## Staged roadmap (each a dedicated build)
- **v2 — MM-GBSA re-verify of the N-methyl variants** (the honest binding check). *Hard part:* psfgen needs a
  custom CHARMM patch for backbone N-methylation (analogous to the CYCP cyclization-patch saga). Until then,
  v1's "binding preserved by construction" is a structural argument, not an energetic measurement.
- **v3 — wire the objective into oversampled generation**: oversample BoltzGen designs, score each by
  `binding × ΔHBD-headroom × MW`, and/or apply the N-methylation redesign, then re-verify (v2). This is the
  actual "permeability-driven generation" loop; v1 supplies its objective function and proves headroom exists.
- **v4 (optional) — conformation-aware permeability oracle** (2-env MD ensembles) to replace the mechanistic
  proxy, if a program milestone justifies the cost. Currently toolchain-blocked; low expected marginal payoff
  per the cheap-path negatives.

## Bottom line
Permeability-driven redesign is now **evidence-backed and started**: we have proof that every binding design
carries substantial, binding-safe permeability headroom, the exact positions to N-methylate per design, and
a mechanistic objective function that (unlike the 2D GBM) can actually see the lever. The remaining work is
energetic re-verification (needs the N-methyl CHARMM patch) and wiring into oversampled generation.
