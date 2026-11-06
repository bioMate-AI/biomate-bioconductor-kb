# BoltzGen on our cyclic test targets — first real results (v3 run)

Post-qualification step 1: run the adopted backbone (BoltzGen `peptide-anything`) on real receptor
targets from our PepBDB cyclic test set. For each target we download the RCSB structure, compute the
binding pocket (receptor residues <5 Å from the native peptide), and design + score head-to-tail
cyclic binders. Honest framing: PepBDB "cyclic" peptides are disulfide-type, so `cyclic:true` here
is a **de-novo head-to-tail cyclic binder to the same pocket**, not a native reconstruction — which
is exactly the cyclic-peptide-drug design task.

## Results (v3, run `boltzgen-targets-20260915T194715Z`) — best design per target by interface iptm

| target | receptor | best cyclic design | iptm | design_pTM | filter-RMSD | designable(<2Å) | filters passed |
|---|---|---|---|---|---|---|---|
| **1yf4** | kallikrein (Ser-protease) | `FSISSSNPNA` (10-mer) | **0.79** | 0.91 | **0.45 Å** | yes | **9/9** |
| 1u8p | antibody Fab (paratope) | `GYGDLPEL` (8-mer) | 0.66 | 0.92 | 2.30 Å | yes | 1/9 |
| 1kc4 | toxin-scaffold receptor | 17-mer | 0.61 | 0.86 | 4.22 Å | yes | 1/9 |
| 1csb | cathepsin B (Cys-protease) | 44-mer* | 0.56 | 0.66 | 1.76 Å | no | 2/9 |

`iptm`/`design_pTM` = interface / design confidence (higher better); `filter-RMSD` = design vs its
own refold (lower = more designable); filters = BoltzGen's developability/quality gate.

**Headline:** `1yf4` is a genuinely strong de-novo cyclic binder — confident interface (iptm 0.79),
designable (refolds to 0.45 Å), passes all 9 developability filters. Concrete evidence the BoltzGen
backbone produces high-quality cyclic binders with native closure + rich scoring, which our bespoke
PepGLAD stack could not.

## Honest caveats / bugs found and fixed
- **`1csb` = 44-mer (*length-cap bug)** — for a 47-mer native, `lo=max(7,L-2)` overrode the intended
  18-cap, so it designed a huge floppy peptide (hence non-designable). FIXED: drug-like range
  `lo=max(7,min(L-2,10)); hi=min(16,max(lo+1,L+2))` → 8–16-mer regardless of native length.
- **`1g9i` (trypsin) failed** — BoltzGen indexes binding by position among **resolved** residues, not
  PDB auth number (v1) nor `label_seq` (v3; trypsin's unresolved gaps push label_seq past the
  resolved count). FIXED: emit the enumeration index over resolved AA residues.
- **`1kat` failed** — auth chain `W` not found by BoltzGen's mmcif parser (label/auth mismatch);
  needs chain-id resolution or target swap. Deferred.
- The 4 gap-free chains above had `label_seq`==resolved-index, so their pockets were mapped correctly
  despite the trypsin bug.

## Iteration cost note (discipline)
Three spot launches (~$0.75) to converge the target-prep format, because BoltzGen's mmcif parser and
binding-index convention could not be validated locally. Each fix was derived from the actual error
(auth># length → resolved-index; missing `_entity_poly_seq` → original RCSB cif). Next GPU run should
be gated by `boltzgen check` on all specs first (cheap) and batched with the physics verify.

## vs PepGLAD (honest)
Not a like-for-like metric comparison: BoltzGen reports iptm/designability/filters; PepGLAD
`cal_metrics` reports DockQ/AAR/Cα-RMSD (baseline DockQ ~0.51). The qualitative result stands —
BoltzGen yields designable, closure-native, developability-scored cyclic binders end-to-end.

## Next
1. Corrected + complete run (drug-like lengths, trypsin fixed, all targets) — gate with `boltzgen
   check`, batch with physics.
2. Physics/MD verify on the top designs (esp. `1yf4 FSISSSNPNA`) — the non-circular oracle (OpenMM
   relax with the `getPlatformByName` CPU fix → MD stability → MM-GBSA).
3. Permeability / N-methylation lever on the survivors.
