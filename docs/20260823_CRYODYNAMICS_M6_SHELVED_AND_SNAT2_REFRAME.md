# CryoDynamics — M6 cloud-proof SHELVED; reframe to the SNAT2 application (2026-08-23)

Honest close-out of the M6-via-OM-TPS effort, the meta-lessons, and the go-forward decision.
Pairs with `20260822_CRYODYNAMICS_M6_AWS_EXECUTION_LOG.md` (the build/run log) and
`20260818_CRYODYNAMICS_M6_DESIGN_AND_ABLATION.md` (the design).

## Decision
**The M6 cloud-proof via OM-TPS is shelved (dead path).** AWS cleaned up (no Batch jobs, no builder
instances, GPU compute env back to 0 vCPUs). Nothing was requested from the SNAT2 collaborator (that was always
gated behind a working public proof, which we do not have).

## What is actually true (facts, verified)
- ✅ **Base tool runs on GPU.** OM-TPS builds (image `om-tps:v2` in ECR) and its alanine `om_interpolate` runs
  end-to-end on an AWS T4, producing a real transition path + energy profile + `js_divergence=0.4712`.
- ✅ **The density-term science is correct in isolation.** `research/m6_density_guidance/density_guidance.py`:
  gradient matches finite-diff to 1.2e-10 against the real OM action; moves a path in a controlled toy.
- ❌ **The M6 feature never actually ran on the real pipeline.** Every "steered" run was **byte-identical** to
  the unsteered one (`max|diff| = 0.0` across λ = 0…1e8). Injected trace prints never fired. The steering code
  provably **did not execute**, despite being present in the source file.
- **Ruled out by evidence (not guesses):** wrong model file (fixed), env var not set (it was set), GitHub
  version drift (live source identical), patch-not-in-source (`inspect.getsource` = present), stale `.pyc`
  (cleared + `PYTHONDONTWRITEBYTECODE`), duplicate anchors (all unique, all inside `om_interpolate`). The final
  "why the imported source's loop never executes" was **not cracked** remotely.

**Critical interpretation:** the byte-identical result is an **invalid experiment, not a negative one.** It says
**nothing** about whether M6 works scientifically — the treatment was never applied. Do not read it as evidence
against the idea.

## Root-cause meta-lessons (the real value of this write-up)
1. **I modified a tool I did not understand deeply.** Found an injection point that *looked* right, validated the
   component in isolation, and assumed the integration worked. The wrong-model-file bug and the un-crackable
   non-firing hook are both symptoms of a missing mental model of how the tool actually executes.
2. **Verified components, not the integration.** Every isolated check passed (gradient, patch text-insert, env,
   imports); the integrated execution was never asserted ("did this line run and change the output?").
3. **Debugged at production scale via the cloud, one hypothesis per expensive run.** The two checks that finally
   localized it — **byte-comparing outputs across λ** (free, local) and a **single fully-instrumented trace run** —
   should have been *first*, not 15 runs in.
4. This is the exact failure the project's own mistakes log warns about, repeated. Spend ≈ a few $ but hours of
   time and trust.

## Strategic reframe — do we even need M6?
**No — M6 is a "make it novel" ambition, not a "make it valuable" requirement.**
- M6 (cryo-EM-density-anchored *path + kinetics*) is CryoDynamics' claimed methodological **novelty**; proving it
  on public data was the gate before (a) a methods-novelty paper and (b) using the sister's SNAT2 data.
- But the **useful deliverable** — a model of SNAT2's transport cycle for the sister — is an **application** built
  from commodity, already-working tools (state generation + membrane MD + transition path). It does **not** require
  the M6 novelty to be proven.
- Given how hard even a clean M6 *test* is proving, the novelty layer is high-effort / uncertain-payoff, while the
  application underneath is achievable now.

## What is left for the real protein (SNAT2 / SLC38A2, Q96QD8) — none of it needs M6
Status: **essentially all substantive modeling is un-started.** Prior sessions validated the pipeline on
benchmarks (GltPh, AdK); SNAT2 itself is at the starting line. Done so far = prep only (structure located, fitted
3.0 Å model + FASTA + ortholog refs on S3; an *ambiguous* inward-leaning state-ID, ΔTM 0.01).

Remaining (application, commodity tools):
1. **Confident state call** (inward/outward/occluded) — resolve the ambiguous state-ID (pore/gate analysis, HOLE).
2. **Generate the alternate elevator state** (M1 — Boltz-2 or ortholog template). Second endpoint.
3. **Build + equilibrate membrane systems** for both states (M2 — infra proven on GltPh).
4. **Generate the inward↔outward transition path** (M3) — the actual useful transport-cycle model.
5. (later/optional) Na⁺/substrate coupling; kinetics/energetics (converged rates = HPC-scale, deferrable).

External dependency (helps, not blocks): the raw `.mrc` map + capture conditions would firm up steps 1–2; steps
1–4 can proceed on the fitted PDB we already have.

## Go-forward: GROUNDWORK FIRST, no execution until it's done
Per the discipline this session earned the hard way — **understand before running**:
1. **Verify/update the prior-art + novelty review** (`20260802_SNAT2_RELATED_WORK.md` is thorough on paper but
   dated 08-02) against *current* literature — especially **any newly published SNAT2/SLC38A2 structures**, which
   would change both novelty and the value of the sister's unpublished structure.
2. **Build real, deep understanding of the tools** we'd actually run for steps 1–4 (Boltz-2 state-gen behavior on
   transporters; the membrane-MD setup; the transition-path method) — *before* any spend, not as failures.
3. Only then propose a concrete, feasibility-gated plan for SNAT2 steps 1–4.

## Change log
- **2026-08-23** — created. M6-via-OM-TPS shelved (invalid experiment, root-caused as a tool-understanding
  failure); AWS cleaned up; strategic reframe (M6 novelty optional vs. SNAT2 application valuable); SNAT2 remaining
  work enumerated (no M6 needed); go-forward = groundwork-first (verified prior art + deep tool understanding)
  before any execution.
