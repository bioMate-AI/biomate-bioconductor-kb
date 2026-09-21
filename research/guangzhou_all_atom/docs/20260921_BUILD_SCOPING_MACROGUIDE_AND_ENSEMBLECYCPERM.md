# Build scoping (2026-09-21): MacroGuide closure + EnsembleCycPerm ΔPSA3D

Two operational builds scoped from the 2026 leverage map (`20260921_LEVERAGE_AND_INSPIRATION.md`),
review-ready per CLAUDE.md "No Speculative Deploys" — scaffolds written, **compute NOT yet launched**.

---

## Build A — EnsembleCycPerm ΔPSA3D permeability  ✅ blocker eliminated, ready to launch (cheap)

**Files:** `perm_dpsa3d.sh` (this commit). Feeds need **N4** (beat the 2D R²≈0.45 ceiling; make N-methylation visible).

**The decisive finding:** our prior 2-env build (`perm_2env.sh`) died at `kept=0` because it parametrized every
macrocycle at runtime with GAFF/AM1-BCC → **`antechamber`/`sqm`** fails on unattended spot boxes (PROGRAM_STATE
2026-09-19 addendum). **EnsembleCycPerm's dataset, `CycPeptMPDB-4D` (Zenodo 21274695, CC-BY-4.0, 5,160 peptides,
100 frames each) already ships ensemble-averaged `Water_3D_PSA` and `Hexane_3D_PSA` per peptide.** So ΔPSA3D =
`Water_3D_PSA − Hexane_3D_PSA` is a one-line derived column — **the fragile per-peptide MD/`sqm` step is removed
by construction.** Build A collapses from an expensive, flaky MD job to a cheap deterministic featurize-and-fit
(RDKit 2D descriptors + column arithmetic over ~5,160 rows → minutes on CPU).

**Method (chameleon recipe):** ΔPSA3D = polar-surface hidden on membrane entry (large = permeable). Controlled
A/B/C: `2D_only` vs `2D+ΔPSA3D` vs `ΔPSA3D_only`, on **both** a random 5-fold and a **Bemis-Murcko scaffold**
GroupKFold (the honest generalization number).

**Reviewed launch (NOT executed) — CPU spot per `peptide-aws-launch-infra`:**
```
# save the launcher as launch_perm_dpsa3d.sh (clone launch_perm_2env.sh: spot, AZ-fallback,
# AutoimmuneCorpusProfile, SG sg-011121fdf81073ec8, key biomate-trial-resume-20260912, self-terminate)
# smaller box than the old c6i.8xlarge — no MD:
AWS_DEFAULT_REGION=us-west-2 BUCKET=knowledge-datasets-1759951976 TYPE=c6i.2xlarge \
RUNID=perm-dpsa3d-$(date -u +%Y%m%dT%H%M%SZ) \
OUT_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/runs/$RUNID \
  bash launch_perm_dpsa3d.sh   # UserData: aws s3 cp $S3RUN/code/perm_dpsa3d.sh . ; OUT_S3=$S3RUN bash perm_dpsa3d.sh
```
**Predicted (the required pre-run note):** `random 2D+ΔPSA3D ≈ 0.65–0.70` (EnsembleCycPerm reports random R²=0.70
on this term) vs our 2D ~0.45–0.55; **scaffold split is the real number — expect modest** (EnsembleCycPerm scaffold
R≈0.68 ⇒ R²≈0.46; 13-method benchmark best random R²≈0.555 with a significant scaffold drop). **Success = the
`ΔPSA3D_only` / `2D+ΔPSA3D` SCAFFOLD rows beat `2D_only` scaffold** — that proves the chameleon term generalizes;
the random-split lift alone does not. **Honest caveat:** the survey's "<2% variance" warning was about conformer
*variance/span* features (we already confirmed those add nothing); ΔPSA3D is the ensemble-*averaged* two-solvent
polar-surface difference — the mechanistically loaded term, not a spread statistic. Report scaffold R², not random.

**Risk:** low. No OpenMM/AmberTools/`sqm` → the `kept=0` failure mode cannot recur. Only external dep = fetch the
1.9 MB CSV (mirrored to our S3 on first run). Fallback for our OWN designed sequences not in the 4D set: our
existing CHARMM/psfgen + GBn2 toolchain (`peptide_psfgen_smoke.sh`) gives 2-env geometries without GAFF/`sqm`.

---

## Build B — MacroGuide persistent-homology ring-closure guidance  ⚠️ scaffold ready, GPU + latent-risk, verify checkpoint first

**Files:** `ph_closure_guidance.py` (this commit). Feeds need **N2** (validated closure / non-natural chemistry).

**Resource (verified):** MacroGuide — arXiv:2602.14977 (Oxford/Mila/AITHYRA), **code public + MIT** at
`github.com/ala1705/MacroGuide` (paper text is CC-BY-NC-ND; the *code* LICENSE is MIT → commercially usable).
Training-free guidance (no weights of its own). New dep: `torch_topological` (differentiable Vietoris-Rips).
Method = three differentiable topological penalties on the 3D point cloud: **H1-death** (ring size window),
**H1-birth** (ring edges ≤ bond length), **H0-death** (connectivity), gradient-descended into positions.

**Where it hooks:** PepGLAD already exposes a sampling-time guidance slot (`sample_opt['energy_func']`, applies
`s − λ∇F`) and already has a hand-rolled `cyclic_closure_energy` (head-to-tail first↔last term). **MacroGuide is
the principled replacement** in that same slot — added as a new `--guidance ph` mode alongside `none|default|cyclic`.
BoltzGen (our other generator) has **no sampler hook** → not wired here; its closure stays downstream-validated by
the MM-GBSA psfgen build. (Forking BoltzGen's diffusion loop is a separate, larger effort.)

**Load-bearing adaptation:** MacroGuide's `d_min/d_max/l_star` are physical Å on decoded atoms; PepGLAD guides in
**latent** space. The scaffold expresses all thresholds in units of the calibrated `consec_dist_mean/std` so the PH
term is commensurate with PepGLAD's existing energy. **This is the make-or-break assumption** — VR filtration on
latent points may not yield chemically meaningful H1 features; the smoke A/B exists to test exactly this.

**Reviewed launch (NOT executed) — GPU spot; requires a *calibrated* PepGLAD checkpoint:**
```
# reuse closure_smoke.sh (already A/Bs default vs cyclic + emits closure_rate); add run_mode 'ph',
# stage ph_closure_guidance.py into code/. GPU AMI + COMBO AZ loop like launch_boltzgen_oversample.sh.
CKPT_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/checkpoints/pepglad_calibrated.ckpt \
OUT_S3=s3://knowledge-datasets-1759951976/cyclic_peptide/runs/ph-closure-$(date -u +%Y%m%dT%H%M%SZ) \
LIMIT=20 ATTEMPTS=4 MAX_RUNTIME=2h  bash launch_closure_ph.sh
```
**Predicted:** stages `... generating_cyclic → generating_ph → closure_smoke_complete`; `serialized_rate≈1.0`;
`closure_rate` none < default < cyclic ≲ **ph**. **Success = ph closure_rate ≥ cyclic AND serialized_rate ≥ 0.95
AND mean_aar_over_baseline not lower than cyclic.** The paper's 1%→99% is on *unconditional MolDiff* — on
PepGLAD-with-a-decent-cyclic-term the honest question is "does topological guidance beat the hand-rolled first↔last
term at equal cost?", NOT "does it reach 99%." A wash on n=20 is a valid negative (scale LIMIT before concluding).

**Risks:** (1) latent-space mismatch (highest — the whole bet); fallback = PH on *decoded* coords in a post-hoc
relax loop. (2) incumbent cyclic term already works → expected lift is modest, not dramatic (don't over-claim
1%→99% on our peptides). (3) `torch_topological` dep + per-step VR cost (schedule guidance to a step subset).
(4) **needs a calibrated checkpoint** (`setup_latent_guidance.py` run) — verify `pepglad_calibrated.ckpt` exists on
S3 before the GPU launch. (5) port only MIT-covered `topology.py`/`terms.py`/`guidance.py` logic (done in the
scaffold), not MacroGuide's vendored MolDiff `src/`.

---

## Recommended sequencing
1. **Launch Build A now** — cheap CPU spot, blocker removed, high-confidence, self-terminating. Lowest-risk real result.
2. **Build B: verify the calibrated checkpoint on S3 first**, then GPU-smoke the `ph` A/B at LIMIT=20 before scaling.

## Change log
- 2026-09-21 — scoped both builds from research-agent findings; scaffolds `perm_dpsa3d.sh` + `ph_closure_guidance.py`
  written; launches reviewed but not executed (per no-speculative-deploy). Build A's `sqm` blocker eliminated by
  adopting CycPeptMPDB-4D precomputed 2-env descriptors.
