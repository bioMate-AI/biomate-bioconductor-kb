# Generic target-spec engine — de-hard-coding the design system

**Date:** 2026-10-15 · Internal. Replaces per-target hard-coding (metal ligands, RGD scaffold, per-target
registries, duplicated pose tables) with **one data schema + one generic engine**. Directly addresses the
feedback: *"too hard-coded; metal-aware is just one type of input."*

## The principle
A target is **DATA** (a spec); one engine reads it. No axis is special-cased in code — every mechanism
difference is a spec value:

| Axis | Spec field | Metal is NOT special — it is just this |
|---|---|---|
| cofactor(s) | `cofactors: [{ccd, n, site}]` | `[]` = none · `[{MN,n:3}]` = β-integrin MIDAS · `[{MG,n:1}]` = I-domain · `[{ZN}]`/`[{HEM}]`/`[{ATP}]` — **identical code path** |
| pose method | `epitope` → `target_spec.POSE_BY_EPITOPE` (data table) | linear-motif / I-domain / discontinuous |
| generation mode | `motif` | present → scaffold-conditioned; `null` → de-novo |
| selectivity | `counter_targets` | from the spec |
| A2 anchoring | `controls` | from the spec |
| structure | `receptor_pdb` + prepared chains | spec-derived cofold input |

**Adding a target = adding a spec row. Zero new code.** A new cofactor chemistry, a new epitope class, a new
motif — all are data edits.

## What changed
- **`cyclic_llm/target_spec.py`** (new) — the canonical engine: `load_spec(target)`, `cofactor_ccds(spec)`,
  `build_cofold_input(spec, candidates)` (generic: receptor chains + cofactors + peptides → cofold input, metal
  just one case of cofactors), `POSE_BY_EPITOPE` (the one pose table).
- **16 KB entries** now carry explicit `cofactors` + `receptor_pdb` as DATA (β-integrins `[MN×3]`, LFA-1 `[MG]`,
  all PPIs `[]`).
- **`scorer_config.py`** is now a thin **view** over `target_spec` (removed its duplicate metal/pose logic — one
  source of truth). `physics_dispatch`, `fto_score`, `loop` unchanged and green.
- **avb6 physics** is now **spec-derived**: the cofold ligands come from `cofactors=[MN,MN,MN]`, not a hard-coded
  JSON field. The in-flight avb6 run becomes *the first spec instance*, not a special case.

## Verified
All 16 targets configure from data with zero per-target code (metal = cofactors: avb6 `MN,MN,MN`, lfa1 `MG`,
pdl1/cytokines `—`; pose + scaffold-mode per spec). `build_cofold_input(avb6)` → `ligands=['MN','MN','MN']`,
`chains=['A','B']`. physics_dispatch admissibility + the loop are unaffected.

## This is also the BioMate-integration unit
The `target_spec` row is exactly what belongs in **BioMate's workflow DB** so the engine runs through the
product (not per-target scripts): one spec → `search_workflow`/`run_workflow` → Batch cofold/MM-GBSA via
`nextflow_executor`. Next integration step: register the spec-driven generate→cofold→score as a BioMate workflow
and route the physics through Batch instead of the standalone EC2 launcher.

## Generation is now spec-driven too (`cyclic_llm/propose.py`)
`propose(spec, n)` picks the mode from the spec — **not from metal**:
- `motif` present (+ a scaffold impl, today RGD.L) → **scaffold-conditioned** (integrins).
- otherwise → **de-novo**: the v4 generator conditioned on the target's **receptor sequence** — this is the path
  for every non-metal PPI target (TNF, IL-17, IL-23, C5, FcRn, CD40, BAFF, IL-2Rα, CD20, and PD-L1).

Verified non-metal, our-own-target, end-to-end: `propose(pdl1)` → de-novo macrocycles conditioned on the real
118-aa PD-L1 sequence (ncAA-rich: `[Sar]`, `[Phe(4-CF3)]`, `[Me_dL]`…), scored generically (developability +
FTO-novelty, all novel). No metal, no RGD scaffold, no avb6 special-case.

## Scaffolds are data too (`cyclic_llm/scaffold.py`) ✅
A scaffold is a **template keyed by canonical motif** (motif residues + β-turn + handle + free slots); one generic
fill routine (neural-ranked via the v4 model, else enumeration) works for every motif. Registered: `RGDL` (αvβ6)
and `LDV` (α4β7 / α4β1). `propose(spec)` now routes a4b7/a4b1 through the **LDV scaffold** — zero per-motif code;
add a template row to extend.

## Launcher reads the spec ✅
`launch_cofold_v2.sh` now builds the cofold input via `target_spec.build_cofold_input(spec, candidates)` — the
**ligands come from `spec.cofactors`** (avb6 → `[MN,MN,MN]`, pdl1 → `[]`), not a hand-set per-target field.

## Still spec-able (follow-ons)
- `physics_dispatch` result registry: make per-target result locations spec data rather than the `REG` dict.
- Prep receptor structures for the autoimmune targets so their physics tier can run (today: cold-start).
- Register the spec-driven generate→cofold→score as a BioMate workflow (Batch via `nextflow_executor`).
