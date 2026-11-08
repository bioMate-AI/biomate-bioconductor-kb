# Committee review — Cyclic-Peptide Engine Review Board (2026-09-20)

Three independent flagship models reviewed the manuscript + design docs + key source with adversarial
mandates (harness: `scratchpad/committee/review_committee.py`; raw reviews saved there). Chair = the agent;
I independently verified the top code finding before writing this. Committee cost ≈ $1.78 (OpenRouter).

| Reviewer | Model | Verdict |
|---|---|---|
| A — Scientific rigor & claims auditor | anthropic/claude-opus-5 | (reasoning-stream) — Major revision in substance |
| B — Methodology & statistics critic | openai/gpt-6-astra-pro | **MAJOR REVISION (0.98)** |
| C — Comp-chem SOTA & code reviewer | google/gemini-3.1-pro-preview | **MAJOR REVISION (0.95)** |

**Bottom line (unanimous):** the *engineering* (automated cyclic MM-GBSA, oversample→verify→select loop,
honest negative results) is a genuine methods contribution, but the work currently **overstates validated
discovery**. Multiple claims rest on (a) a real cheminformatics bug, (b) size-biased cross-sequence MM-GBSA,
and (c) small-n point estimates reported without uncertainty. Reframe as a reproducible
candidate-prioritization workflow, fix the code, add uncertainty, and stop calling computational agreement
"validation."

## Consensus critical issues (≥2 reviewers) with chair assessment

1. **FATAL: `cyclic_mol()` deletes the wrong carboxyl oxygen** (A, B, C). Both C-terminal oxygens are
   degree-1; the code removes the first found, so it strips the **carbonyl** O and leaves a spurious `–OH`
   donor. **Chair verified locally:** it is a *deterministic +1 donor / +2 Da offset on every design* (not
   50/50). Impact: absolute HBD/MW wrong; **relative rankings and ΔHBD-headroom survive** (constant offset
   cancels; ΔHBD = methylatable count, independent of the bug); the fix actually makes permeability look
   *better* (e.g. `GPFVPGL` → 0 donors after redesign, not 1). **Fix:** delete the SINGLE-bonded O; recompute
   absolute numbers. *(FIXED this commit; recompute pending.)*
2. **v3 computes descriptors on the LINEAR peptide** (`MolFromSequence`), never cyclizes (A, B, C). MW ~+18 Da,
   donors +1–2 vs the real macrocycle; v1 (cyclizes) and v3 (doesn't) are inconsistent. **Fix:** shared
   validated cyclic builder; recompute v3 tables. *(FIXED this commit; recompute pending.)*
3. **Cross-sequence MM-GBSA is size-biased → several headline ΔG comparisons are confounded** (A, B, C).
   Comparing ΔG across different lengths/MW favors bigger peptides. A: the "~9 kcal/mol binding lost" in §3.9
   is *exactly what the MW gap (694 vs 997) predicts under size bias* — so "physics binding lost" may be an
   artifact, not a real effect. C: the iptm⟂physics −0.04 may itself be an artifact of size-biased MM-GBSA vs
   length-agnostic iptm. **Fix:** report per-design length/MW/heavy-atom count with every ΔG; regress ΔG on
   heavy-atom count; report ligand-efficiency / size-corrected values; re-examine dual-optimal and
   orthogonality claims after correction. **This is the highest-impact scientific issue.**
4. **Small-n, no uncertainty; overclaiming from point estimates** (A, B). Spearman −0.04 at n=32 has ~±0.35
   CI → "orthogonal / essentially no signal" is unsupported; ΔG set-differences (−29.6 vs −38.9; −23.7 vs
   −22.4) and the conformer-span 0.246 vs 0.262 are reported with **no error bars / sample size**; 4 targets
   cannot establish "systematic" or "universal." **Fix:** CIs, per-target stratified stats, replicate noise,
   soften language.
5. **Auto-verdict "binding PRESERVED" is a baked-in overclaim** (A, B, C) that contradicts the "unvalidated"
   caveat. **Fix:** emit the score difference + an `UNRELIABLE` flag, no biological verdict. *(FIXED this commit.)*
6. **N-methyl force field not validated; CMAP not updated** (B, C). C (critical): keeping atom type `NH1` +
   the secondary-amide **CMAP** on an N-methylated backbone gives physically wrong φ/ψ energies — so the v2
   free-ligand strain is partly a force-field artifact, not just lack of relaxation. **Fix:** use a real
   N-methyl-amide parameterization (CGenFF / sarcosine analogue with correct CMAP), or state explicitly the
   v2 energies are invalid on these grounds. *(Documented now; proper fix deferred — it's a real FF build.)*
7. **`split()` keeps only the single longest receptor chain** (C). Drops other receptor chains/cofactors —
   *consequential for 1u8p (a Fab = heavy+light chains): our 1u8p "receptor" was likely incomplete*, so the
   1u8p ΔG values (and the "generalization" conclusion) are suspect. **Fix:** assemble the full receptor;
   re-run 1u8p. **Chair: this materially weakens §3.10 and must be flagged now.**
8. **§3.7 single-trajectory cancellation explanation is technically wrong** (B; A partially). Intramolecular
   cancellation is the *intended* feature; a small residual of large components is not itself evidence of
   unreliability. The real limitation is the omitted free-state reorganization/entropy. **Fix:** correct the
   interpretation (right conclusion — MM-GBSA unreliable here — but for the right reason).
9. **"Binding preserved by construction" is chemically unjustified** (B). Absence of one backbone-N/receptor
   contact ≠ neutral modification; all receptor N/O treated as acceptors without chemical typing or H-bond
   geometry; "not H-bonding" ≠ "exposed." **Fix:** rename to "candidate N-methylation sites lacking a
   detected direct backbone contact"; add typed acceptors + geometry + methyl-clash checks.
10. **Selection evaluates its own objective; parent vs product mismatch** (B). v3 MM-GBSA is on *unmethylated
    parents* while the permeability objective is on *methylated products* — no single molecule demonstrated to
    have both properties; only the 14-design union scored, not the full pool; no random/MW-only/ΔG-only
    baselines. **Fix:** score full pool, matched baselines, and the *same final molecules* for both axes.

## Other issues worth fixing
- R²=0.45 with Spearman=0.75 is internally odd (monotone would imply R²≈0.58) → nonlinearity/heteroscedasticity to explain (A).
- "0.45–0.55 static-descriptor ceiling" overclaims from one model/split; soften to "did not exceed 0.45 here" (A, B).
- Proline wrongly retained in `keep_bb_donors` (B). `HBD_redesign` is a site count, not exposed polar SA (B).
- v3 JSON note still rewards ΔHBD after the switch to end-state (B). "Pareto" in text is a weighted scalar in code (B).
- Reproducibility: pin commit IDs, seeds, data manifests, env locks; explain 28 vs 32 and −52.7 vs −52.4 (B).
- Hardcoded `Threads=os.cpu_count()` over-subscribes in containers (C); `2.0 nm` nonperiodic cutoff truncates electrostatics on the 205-res receptor without correction (A).

## Genuine disagreement / chair adjudication
- **Is iptm⟂physics real or a size artifact?** C/A say the −0.04 could be a size-bias artifact; the manuscript
  treats it as a clean finding. **Chair:** partially concede — must recompute the correlation with
  size-corrected ΔG (ligand efficiency) and report the CI before claiming orthogonality. The *operational*
  point (don't advance on iptm alone) stands; the *strong* orthogonality claim does not, yet.
- **Does the cyclization bug invalidate conclusions?** Reviewers implied yes; chair verification shows the
  offset is constant, so *relative* conclusions hold but *absolute* numbers must be recomputed. Both are true:
  fix + recompute, but the qualitative story (headroom exists; physics reranks; select on physics not iptm)
  is not overturned by this particular bug.

## Prioritized action list
**P0 (correctness, do now):** (1) cyclization O-bug ✓fixed; (2) v3 linear→cyclic ✓fixed; (5) kill auto-verdict
✓fixed; then recompute all v1/v3 absolute numbers.
**P1 (validity of claims):** (3) size-correct every cross-sequence ΔG + re-examine dual-optimal/orthogonality;
(7) rebuild full 1u8p receptor and re-run §3.10; (4) add CIs/replicates and soften small-n language; (8)(9)
fix the §3.7 explanation and the "binding-safe by construction" framing.
**P2 (rigor for publication):** (6) proper N-methyl FF with CMAP (or FEP with validated params); (10) full-pool
scoring + matched baselines + same-molecule dual-objective eval; reproducibility artifacts.

## What the committee agreed is genuinely good
Automated headless cyclic MM-GBSA (build feasibility 32/32); separating generator confidence from downstream
scoring; the honest self-correction on single-traj MM-GBSA for N-methylation (C: "excellent, honest science");
the mechanistic fallback when the 2D GBM proved blind to N-methylation; and disclosing negative results.
