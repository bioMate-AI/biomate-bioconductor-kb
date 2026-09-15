# Closing the generate–verify–learn loop (it's currently open)

Honest state: the pieces exist (generator, auto-metrics, developability predictors, selection,
physics relaxer) but as **disconnected manual scripts**. There is **no closed loop** — no
orchestration and, critically, **no feedback to the generator**. What ran so far is
generate→verify→select (OPEN). This documents how to actually close it.

## Why it isn't closed yet
1. **No orchestrator** — each stage is a hand-launched bootstrap; nothing iterates.
2. **No learn/feedback rung** — validation results never improved the next generation.
3. **Circularity trap** — closing the loop on the ML predictor's own scores (select high-predicted,
   feed back) just reinforces the predictor's blind spots. A real loop needs an **independent,
   non-circular verify signal**. Physics/MD provides it (ΔG, stability, energy) computationally;
   wet lab provides it eventually. The ML surrogate alone cannot close the loop honestly.

## The closable-now loop — physics-in-the-loop expert iteration (all in silico)
```
 ┌─ generate: cyclic generator (N candidates/target, best-of-N pool)
 │
 ├─ VERIFY (non-circular oracle):
 │     rung-1 auto-metrics: DockQ, Cα-RMSD, validity/clash
 │     rung-2 PHYSICS: OpenMM relax + energy → short MD stability → MM-GBSA ΔG
 │
 ├─ SELECT: rank by physics ΔG + stability + validity (NOT by the ML score that would be circular);
 │          keep uncertainty for acquisition
 │
 ├─ LEARN: fine-tune the generator on the physics-validated winners (expert iteration /
 │         self-distillation) — or property-condition on the ΔG labels
 │
 └─ ITERATE until ΔG / validity / designability plateau; only the converged set → wet lab
```

## What each cycle needs (and the honest cost)
- Generation + physics per cycle is GPU-heavy (relax + MD + MM-GBSA over many candidates). Bound
  it: small target set, modest N, short MD. Each cycle is hours of GPU.
- Feedback = fine-tune on winners (cheap given small sets) — reuses `cyclic_finetune.sh`.
- Convergence signal: physics ΔG / MD-stability improving cycle-over-cycle (the real "learning").
- Orchestrator: a driver (workflow or controller script) that runs the rungs in order, applies
  the selection, triggers the fine-tune, and loops — with per-cycle metrics logged to S3.

## Why physics is the linchpin
It makes the loop **non-circular** and answers the questions the ML surrogates can't:
- permeability = conformational/chameleon behavior (MD/solvation), not a static-FP guess;
- binding = MM-GBSA ΔG, not a docking/ML proxy;
- validity = force-field energy/clash, not just geometry.
Learning from physics signal is a genuine improvement loop; learning from the ML predictor's own
selections is not.

## Immediate build
Orchestrator that runs ONE full cycle end-to-end (generate → auto-metrics → OpenMM relax/energy →
select by energy/validity → fine-tune on winners), logs per-cycle metrics, then iterates. Start
with the cheapest physics (OpenMM relax/energy) as the oracle; add MD-stability + MM-GBSA as the
loop proves out. This is the 生成–验证–学习 engine, closed and computational.
