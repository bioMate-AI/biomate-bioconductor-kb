# Cryo-EM Paper: Evaluation Protocol and Dataset Plan
**Date:** 2026-02-25 11:38
**Status:** Protocol draft — pending innovation survey results
**Links to:** `20260225_1138_CRYOEM_PAPER_PLAN.md`

---

## Product Benefit Being Measured

**The claim:** BioMate catches cryo-EM dataset failures at the earliest possible pipeline step, before expensive GPU compute is wasted — and does so without sacrificing final reconstruction quality compared to expert manual processing.

**The counterfactual:** Without BioMate, a failure in motion correction or CTF estimation is discovered only at refinement or reconstruction (steps 16–21 of 23), after 12–40 GPU-hours and 1–3 days of calendar time have been spent.

---

## Experiment 1: Quality Parity (does automation match expert quality?)

**Question:** Does BioMate's automated 23-step pipeline achieve the same FSC 0.143 resolution as an expert CryoSPARC operator on the same dataset?

**Dataset:** EMPIAR-10061 (β-galactosidase, Bharat & Scheres 2016)
- Published resolution: 2.2Å
- Well-characterised, standard sample, no unusual QC challenges
- Widely used as the community benchmark — reviewers will recognise it

**Protocol:**
1. Download raw movies from EMPIAR-10061 (public, ~200 GB)
2. Run BioMate 23-step pipeline end-to-end (no human intervention)
3. Record: final FSC 0.143 resolution, total calendar time, total GPU-hours, number of QC events fired
4. Expert operator runs same dataset through CryoSPARC GUI manually
5. Record: final FSC 0.143 resolution, total expert time (hours at keyboard), total calendar time, GPU-hours

**Success criterion:** BioMate resolution within 0.2Å of expert. (Failure = BioMate > 0.5Å worse than expert.)

**Headline metric:**
> BioMate: 2.3Å, 2 hours expert time, 14 calendar hours
> Manual: 2.2Å, 18 hours expert time, 36 calendar hours
> **Expert time saved: 89%**

---

## Experiment 2: Early Failure Detection (the core product value)

**Question:** When a dataset has a real quality problem, at what step does BioMate catch it, and how much compute does early detection save?

### 2a: Simulated motion correction failure

**Dataset:** EMPIAR-10061 micrographs with injected artificial drift
- Take the first 100 micrographs from EMPIAR-10061
- Post-process to artificially inflate frame-to-frame displacement (simulate poorly tuned motion correction: total drift 90–150Å)
- This simulates the real-world scenario of a misconfigured dose rate or a malfunctioning stage

**Protocol:**
1. Run both original and drift-injected micrographs through BioMate
2. Confirm gate fires at step 2 (motion correction) for injected dataset, not for original
3. Record: step at which halt occurs, GPU-hours consumed at halt, GPU-hours that would have been consumed if run completed
4. Calculate: GPU cost saved = (total pipeline GPU-hours − GPU-hours at halt) × $/GPU-hour

**Expected result:**
- Original: no gate, full pipeline completes
- Injected: gate fires at step 2 (of 23); ~2% of total pipeline compute consumed; 98% saved

### 2b: Real problematic dataset

**Dataset:** EMPIAR-10017 (β-galactosidase dataset with documented stage drift, referenced in Bharat & Bharat 2015)
- Known to have higher beam-induced motion than EMPIAR-10061
- Use as a real-world "difficult dataset" rather than synthetically injected

**Protocol:**
1. Run through BioMate with default `cryoem_spa_purified` profile
2. Run through BioMate with `cryoem_spa_membrane` profile (relaxed drift threshold 50→80Å)
3. Record: which profile passes, which halts, final resolution if pipeline completes
4. Compare to published processing result

**Expected result:**
- Default profile: motion gate fires (documents the false-positive-prevention value of the membrane profile)
- OR: both profiles pass, full pipeline completes, confirming dataset is processable

### 2c: Bad CTF estimation

**Dataset:** Subset of EMPIAR-10028 (T20S proteasome) with artificially narrowed CTF search range
- Set CTF search range to 5,000–10,000Å (too narrow, will miss most micrographs)
- Expect CTF fit_quality < 0.7 on most micrographs → gate fires at step 3

**Protocol:**
1. Run artificially constrained CTF search through BioMate
2. Record: gate fires at step 3, message suggests "widen CTF search range minimum"
3. Record GPU-hours at halt vs full pipeline

---

## Experiment 3: Protocol-Aware Profile Validation (the false positive elimination story)

**Question:** Does the membrane protein profile correctly pass a membrane protein dataset that the default profile would incorrectly halt?

**Dataset:** EMPIAR-10005 (TRPV1 ion channel, Liao et al. 2013 Nature)
- Membrane protein embedded in lipid nanodisc
- Known to exhibit higher beam-induced motion than soluble proteins (larger complex, more flexible)
- Published resolution: 3.4Å

**Protocol:**
1. Run EMPIAR-10005 with `cryoem_spa_purified` profile (drift threshold: 50Å)
2. Run EMPIAR-10005 with `cryoem_spa_membrane` profile (drift threshold: 80Å)
3. Record: which profile halts, which passes, final resolution if pipeline completes
4. Compute: how many good membrane protein datasets would be incorrectly rejected by the default profile?

**Success criterion:**
- Default profile: motion correction gate fires (false positive — this is a valid dataset)
- Membrane profile: gate passes, pipeline completes, resolution within 0.5Å of published 3.4Å

**Headline metric:**
> "Applying default (soluble protein) thresholds to EMPIAR-10005 would incorrectly halt a valid membrane protein dataset. BioMate's `cryoem_spa_membrane` profile eliminates this false positive."

---

## Experiment 4: Non-Expert Usability

**Question:** Can a wet-lab structural biologist with no bioinformatics/programming training complete a full cryo-EM processing run using BioMate?

**Participants:** 5–8 people from structural biology labs who use CryoSPARC GUI themselves but have not used Nextflow or scripted pipelines

**Task:** Given raw movies from EMPIAR-10061 (pre-staged on S3), complete a full SPA processing run and retrieve the final map

**Metrics:**
- Task completion rate (target ≥ 70%)
- Time to first QC decision (should be < 30 min)
- Time to final map (calendar hours)
- Number of support requests needed
- User satisfaction score (1–5, target ≥ 4.0)

---

## Metrics Summary Table

| Metric | Experiment | Target value | Failure threshold |
|---|---|---|---|
| FSC resolution parity | Exp 1 | Within 0.2Å of expert | > 0.5Å worse |
| Expert time saved | Exp 1 | ≥ 80% reduction | < 50% reduction |
| Compute saved on failed datasets | Exp 2a | ≥ 85% at step 2 halt | < 50% |
| False-positive prevention (membrane) | Exp 3 | Default halts, membrane profile passes | Both halt = no differentiation |
| Non-expert task completion rate | Exp 4 | ≥ 70% | < 50% |
| False-positive rate on good data | Exp 1 | < 5% | > 15% |

---

## Compute Budget

| Run | Dataset | Instance | Estimated cost |
|---|---|---|---|
| Full pipeline (EMPIAR-10061) | 1,200 micrographs | g6.8xlarge, ~14h | ~$85 |
| Expert manual (same dataset) | Same | Same instance | ~$85 (same compute, different time) |
| Drift-injected subset | 100 micrographs | g6.2xlarge, ~2h | ~$12 |
| EMPIAR-10005 (TRPV1) × 2 profiles | ~800 micrographs | g6.8xlarge, ~10h | ~$120 |
| EMPIAR-10028 (T20S, CTF test) | Subset 200 | g6.2xlarge, ~2h | ~$12 |
| **Total** | | | **~$314** |

---

## What Must Be Built Before Running

| Prerequisite | Status | Effort |
|---|---|---|
| FSC 0.143 gate (parse CryoSPARC FSC JSON) | ❌ Not built | 1 day — P0 |
| 2D class rejection rate gate | ❌ Not built | 1 day — P1 |
| AWS Batch GPU job configuration for CryoSPARC | Partial | 0.5 day |
| EMPIAR-10061 staged to S3 | ❌ Not done | 0.5 day (download + upload) |
| Expert operator recruited for manual comparison | ❌ Not done | Recruit from co-author lab |

---

## Timeline

| Week | Action |
|---|---|
| 1 | Build FSC gate; stage EMPIAR-10061 to S3 |
| 2 | Run Experiment 1 (BioMate vs expert); record metrics |
| 3 | Run Experiments 2a, 2b, 2c (failure detection) |
| 4 | Run Experiment 3 (EMPIAR-10005 membrane profile) |
| 5–6 | Usability sessions (Experiment 4) |
| 7 | Analyse all results; draft figures |
