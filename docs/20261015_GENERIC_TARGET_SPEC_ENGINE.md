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

## Still spec-able (follow-ons)
- Generator: wire `motif → scaffold` (and de-novo when `motif=null`) so generation is spec-driven too (today the
  RGD scaffold is still avb6-family-specific in `rule_conditioned_generator`/`neural_generator`).
- `physics_dispatch` result registry: make per-target result locations spec data rather than the `REG` dict.
- Cofold launcher: read `build_cofold_input(spec, candidates)` instead of the hand-written plan JSON.
