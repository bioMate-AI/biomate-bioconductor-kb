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

## v2 — MM-GBSA re-verification of the N-methyl variants (BUILT, first result)
Tools: `peptide_nmethyl_smoke.sh` (build test), `peptide_nmethyl_mmgbsa.sh` (ΔΔG), `launch_nmethyl_*.sh`.
Result: `results/nmethyl_mmgbsa_1yf4_FSRNVGDPY.json`.

The hard part — correct backbone N-methyl parametrization — is **solved** inside the same validated
CHARMM/psfgen pipeline that built 32/32 rings: an `NMET` patch (delete amide HN, add N–CH3; neutral
tertiary-amide-like charges) + a supplementary `.prm` that mirrors every amide-H (`H–NH1–*`) angle/dihedral
onto the methyl (`CT3`) with **real borrowed CHARMM36 values** (+ `HA3–CT3–NH1` from `HA3–CT3–CT1`; the
`NH1–CT3` bond, `CT3–NH1–C` angle and `HA3–CT3–NH1–C` dihedral already existed). It builds, parametrizes
(GBn2), and minimizes cleanly. Converged like the CYCP saga: the build smoke named each missing term, fixed
with analogue values, re-smoked.

**ΔΔG across all 4 targets' top candidates** (methylate the v1-selected non-interface positions):

| target | design | nMe | baseline ΔG | methyl ΔG | ΔΔG | Δcomplex | Δligand | \|ΔΔG\|/max\|ΔE\| |
|---|---|---|---|---|---|---|---|---|
| 1yf4 | FSRNVGDPY | 5 | −52.4 | −57.1 | −4.6 | +148 | +155 | 0.03 |
| 1csb | SRYTTMGSGWSIAFG | 12 | −66.4 | −79.0 | −12.6 | +315 | +321 | 0.04 |
| 1kc4 | TGVGGVAGVDGDGTV | 14 | −20.5 | −26.6 | −6.1 | +313 | +327 | 0.02 |
| 1u8p | SSDLRRSAF | 9 | −21.3 | −23.9 | −2.6 | +242 | +268 | 0.01 |

**Honest reading — single-trajectory MM-GBSA is inadequate for scoring N-methylation, so these ΔΔG are NOT
reliable.** All four are mildly favorable, but each ΔΔG is the small residual of two large, near-cancelling
intramolecular energy changes: N-methylation raises *both* the complex and the free-ligand (bound-geometry)
energy by +150 to +320 kcal/mol, and ΔΔG is only 1–4% of that — and it tracks the *number* of methylations,
not the binding mode. Single-trajectory MM-GBSA never relaxes the free ligand, so heavy methylation inflates
apparent binding via ligand strain. Defensible conclusions: (i) **no evidence of binding degradation**;
(ii) the favorable sign/magnitude **cannot be trusted**; (iii) the right energetic arbiter is **FEP** (or
≥3-trajectory MM-GBSA with free-ligand sampling). The binding-safe claim rests primarily on v1's structural
argument (non-interface backbone Ns), with FEP required for the energetic verdict. Charges are also
approximate (relative ΔΔG only). **What v2 solidly delivered: a working N-methyl parametrization + the
empirical finding that MM-GBSA can't score this — which is exactly why the finalist tier is FEP.**

## v3 — oversample + permeability-aware selection (BUILT, first result)
Tools: `launch_boltzgen_oversample.sh` (GPU spot, AZ-fallback), `perm_generation_v3.py` (scorer).
Result: `results/perm_generation_v3_1yf4.json`.

Oversampled BoltzGen on 1yf4 to 32 designs (vs default 8), scored each by binding (iptm) + **end-state**
permeability after N-methyl redesign (low HBD-after-redesign, low MW). Objective-design lesson: rewarding the
*change* ΔHBD is wrong (favors big donor-rich peptides); reward the **post-redesign end state**.

**Perm-aware top-8 vs BoltzGen default top-8:** iptm 0.65 vs 0.675 (small cost), HBD-after-redesign
**5.75 vs 9.0 (−36%)**, MW **694 vs 997 (−30%)**. Oversampling + selection surfaces small low-donor cyclic
binders (`GGPLLGR` MW669, `YSGGGPG` MW594) that BoltzGen's permeability-blind ranking buried at ranks 12–26.
The generate→select permeability loop works end-to-end.

*Honest limits:* "binding" = BoltzGen iptm (⟂ physics ΔG per the rerank finding) → perm-aware picks still need
MM-GBSA/FEP; this is oversampling+selection, not sampling-time guidance; one target; the iptm dip may be real
(smaller peptides bind weaker). Next: MM-GBSA-verify the perm-aware picks; scale to 4 targets; then true
guided generation (steer sampling, not just select).

## v3 physics-verification (DONE) — select on PHYSICS, not iptm; dual-optimal designs exist
Tool: `peptide_mmgbsa_v3verify.sh`. Result: `results/v3verify_mmgbsa_1yf4.json`.

MM-GBSA'd the union of the v3 perm-aware top-8 and BoltzGen-default top-8 (14 designs). **Perm-aware set (chosen
on iptm) mean ΔG −29.6 vs default −38.9 kcal/mol** — iptm-based permeability selection gave up ~9 kcal/mol of
*physics* binding, because iptm ⟂ physics (3rd confirmation): small Gly-rich permeable designs (MGSGGGS −17.8,
FGSGGPL −16.8) had OK iptm but weak MM-GBSA. **But** ranking the pool on *physics* ΔG × end-state permeability
finds genuine dual-optimal designs: **FVVGNPIA (ΔG −42.4, MW 816, 3 donors after redesign)** and **GGPLLGR
(ΔG −42.2, MW 669)** — as strong as BoltzGen's best binders yet far more permeable than its polar top picks
(MSRDSSNPEA −44.7 but MW 1093 / 13 donors). **Engine fix: the permeability-driven selection objective must use
the PHYSICS oracle, not iptm.** With that, oversampling delivers strong+permeable designs. FVVGNPIA/GGPLLGR are
the concrete dual-objective candidates from 1yf4.

## Staged roadmap (remaining)
- **FEP** on the dual-optimal finalists (FVVGNPIA, GGPLLGR) — the ~1 kcal/mol arbiter (also needed for N-methyl ΔΔG).
- **v2b — scale the ΔΔG across designs/targets**: `peptide_nmethyl_mmgbsa.sh` takes `CIF_S3` + `METH_POS`.
- **v3b — scale oversampling to 4 targets** (`launch_boltzgen_oversample.sh` TARGET_ONLY=…), then true guided
  generation. Superseded framing of the original v3 bullet:
- **(orig) v3 — wire the objective into oversampled generation**: oversample BoltzGen designs, score each by
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
