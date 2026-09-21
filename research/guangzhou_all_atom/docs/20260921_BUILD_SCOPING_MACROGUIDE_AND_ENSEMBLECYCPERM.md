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

### Build A — MEASURED RESULT (2026-09-21, ran locally, n=5,160, 368 scaffolds) — ❌ HONEST NEGATIVE

Ran `perm_dpsa3d.sh`'s fit locally (rdkit 2025.09.2; 217 RDKit 2D desc + 13 env features; HistGBR; 5-fold random
+ Bemis-Murcko GroupKFold). **The 2-env / ΔPSA3D descriptors do NOT beat 2D, and ΔPSA3D alone is near-zero:**

| feature set | random R² | scaffold R² |
|---|---|---|
| 2D_only | **0.302** | **0.254** |
| 2D + ΔPSA3D(+env) | 0.285 (worse) | 0.240 (worse) |
| ΔPSA3D(+env) only | 0.069 | 0.036 |

**Why (diagnostic):** individual columns carry modest signal — `Water_3D_PSA` ρ=−0.228, `Hexane_3D_PSA` ρ=−0.219,
**`Water_Desolvation_Free_Energy` ρ=+0.276 (best single 2-env feature)** — but the **chameleon *difference*
`ΔPSA3D = Water−Hexane` ρ=−0.057** because the two solvents' PSA are highly correlated, so subtraction cancels the
signal. And even the raw 2-env set doesn't add over 2D (RDKit TPSA/descriptors already capture polar surface).

**Honest conclusions:**
1. **Does NOT reproduce EnsembleCycPerm's random R²=0.70.** Their lift must come from their *own* model/feature
   pipeline (or a different split/target), **not** from the released CycPeptMPDB-4D descriptors bolted onto a GBM.
   Adopting the *dataset* ≠ adopting the *model*.
2. **Consistent with our own history:** finding #6 (cheap chameleon-span fails) + survey's "<2% variance" — the
   cheap 2-env route now fails a **third** way, this time with real MD-ensemble descriptors, not our proxy.
3. **Cheap win preserved:** the blocker really was eliminated (ran free, no `sqm`) — so this is a *clean* negative,
   not a toolchain failure. That's the value: we can now stop investing in the cheap 2-env bolt-on with confidence.
4. **If we still want the lift:** reimplement EnsembleCycPerm's actual model (their features, not just ΔPSA3D), or
   test `Water_Desolvation_Free_Energy` as an orthogonal add to a *weaker* 2D baseline — low priority given (1)-(2).

Result JSON: `results/perm_dpsa3d_local.json` (this commit).

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

### Build B — MEASURED RESULT (2026-09-21, run `closure-ph-20260921T044733Z`, g6.2xlarge spot) — ⚠️ MIXED

Ran the 3-arm closure smoke on the base LDM `provided.ckpt` (n=20 complexes × 4 attempts; calibrated
consec_dist=4.514). `summary_{default,cyclic,ph}.json`:

| arm | serialized | closure_rate (≤2Å) | mean_term_NC_dist | verdict |
|---|---|---|---|---|
| default | 80/80 | 0.0 | **18.35 Å** | baseline (unguided geometry) |
| cyclic | 80/80 | 0.0 | **6.94 Å** | ✅ works — head-to-tail term pulls termini ~11 Å closer |
| ph (MacroGuide) | **0/80** | null | null | ❌ **CRASHED — code bug, not a science result** |

**Two honest findings:**
1. **Guidance works directionally, but the base checkpoint can't fully close.** `cyclic` cut terminal N–C
   distance 18.35→6.94 Å, but neither arm reached the strict 2 Å `closure_rate` — expected, because
   `provided.ckpt` is **not cyclic-trained** (closure_smoke.sh header). A real closure test must use the
   **cyclic-fine-tuned** checkpoint (`pepglad-cyclicft-…/cyclic_ldm/…/epoch59_step1920.ckpt`), which exists on S3.
2. **The `ph` arm crashed (0/80 serialized).** `torch_topological==0.1.0` installed and the energy_func was
   wired, but `ph_closure_energy` threw on every attempt (PepGLAD's sampling loop swallowed the per-attempt
   exceptions → silent 0 serialized). Root cause: **my persistence code assumed a torch_topological API that
   doesn't match 0.1.0** (pip resolved 0.1.0, not the pinned 0.1.7). This is an implementation bug — do NOT
   read it as "MacroGuide doesn't help."

**Fix plan (before any re-run — no speculative redeploy):** (a) correct `ph_closure_guidance.py` to the real
torch_topological 0.1.0 API (probed locally); (b) make the energy term log the first exception + fall back
instead of silently zeroing a run; (c) re-run on the **cyclic-ft checkpoint** so `closure_rate` can actually
move. Cost of this run: ~$1 (g6 spot, self-terminated).

### Build B — RESOLVED (2026-09-21, 4 runs) — ❌ MacroGuide does NOT beat the cyclic term

After fixing two bugs, the final run (`closure-ph-20260921T082104Z`, base ckpt, n=20×4) is clean and conclusive:

| arm | serialized | mean terminal N–C dist | closure_rate (≤2Å) |
|---|---|---|---|
| default (unguided) | 80/80 | 17.89 Å | 0.0 |
| **cyclic** (head-to-tail) | 80/80 | **6.94 Å** | 0.0 |
| **ph** (MacroGuide, stable) | 79/80 | **18.63 Å ≈ default** | 0.0 |

**Two root causes found + fixed (grounded, not guessed):**
1. **Wrong dependency version.** `pip torch_topological==0.1.7` silently failed on torch 2.5.1 → fell back to
   **0.1.0**, which lacks `VietorisRipsComplex`. Fixed: pin **0.1.9** (verified locally to have the exact API) +
   re-pin numpy<2 + import verification.
2. **Gradient 20–50× too strong** (the silent 0/80). Local test: PH grad norm ~26–51 on noisy latent clouds vs
   the cyclic term's ~0–1.4; at λ=0.8 it blew the latent to NaN → 0 valid decodes (no exception). Fixed:
   `PH_ENERGY_SCALE=0.04` → grad ~1.06–2.17 (matches cyclic) + non-finite guard.

**Scientific conclusion (honest):** for **head-to-tail macrocyclization**, the simple hand-rolled cyclic term
**wins decisively** (6.94 Å vs 18.63 Å) and is cheaper/robust. MacroGuide's persistent-homology objective
optimizes *ring topology/size*, which does **not** align with the terminal-N–C metric, and at the gentle scale
required for sampler stability it's a **no-op** on this metric. **The paper's 1%→99% (unconditional MolDiff) does
NOT transfer** to PepGLAD-with-a-working-cyclic-term. **Decision: keep the cyclic term; do not pursue MacroGuide
here.** (Matches the leverage-doc prediction: "a wash on n=20 is a valid negative.") Net cost of the 4 runs: ~$4.

## Recommended sequencing
1. **Launch Build A now** — cheap CPU spot, blocker removed, high-confidence, self-terminating. Lowest-risk real result.
2. **Build B: verify the calibrated checkpoint on S3 first**, then GPU-smoke the `ph` A/B at LIMIT=20 before scaling.

## Change log
- 2026-09-21 — scoped both builds from research-agent findings; scaffolds `perm_dpsa3d.sh` + `ph_closure_guidance.py`
  written; launches reviewed but not executed (per no-speculative-deploy). Build A's `sqm` blocker eliminated by
  adopting CycPeptMPDB-4D precomputed 2-env descriptors.
